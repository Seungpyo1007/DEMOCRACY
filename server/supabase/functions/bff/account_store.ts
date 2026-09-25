// Account storage for the BFF: profiles, consents, 활동명 offers and residency.
// Kept apart from ReadStore: those are public records any caller may read, these are
// one user's rows and every call is scoped to a verified user id.
//
// Two implementations, like ReadStore: PostgREST (prod) and in-memory (tests). The
// rules that must hold under concurrency (offered-only handles, the 30-day change limit,
// profile-before-residency) live in the SQL functions of the accounts migration; the
// memory store mirrors them and fails with the same PostgrestError code and message,
// so the handler maps one error shape for both.

import { type Postgrest, PostgrestError } from "../_shared/postgrest.ts";
import { inList } from "../_shared/postgrest.ts";

export interface ProfileRec {
  user_id: string;
  provider: string;
  email: string | null;
  handle: string;
  handle_changed_at: string | null;
  notify: boolean;
  created_at: string;
}

export type ConsentKind = "age14" | "terms" | "privacy" | "notify";

export interface ConsentRec {
  user_id: string;
  kind: ConsentKind;
  version: string;
  granted: boolean;
  at: string;
}

export interface ResidencyRec {
  user_id: string;
  district_id: string;
  method: string;
  token_hash: string;
  verified_at: string;
  expires_at: string;
}

export interface OfferRec {
  user_id: string;
  handle: string;
  expires_at: string;
}

export interface NewProfile {
  userId: string;
  provider: string;
  email: string | null;
  handle: string;
  notify: boolean;
  version: string;
}

export interface NewResidency {
  userId: string;
  districtId: string;
  method: string;
  tokenHash: string;
  verifiedAt: string;
  expiresAt: string;
}

/** Days between 활동명 changes; mirrors interval '30 days' in claim_handle. */
export const HANDLE_CHANGE_DAYS = 30;

export interface AccountStore {
  profile(userId: string): Promise<ProfileRec | null>;
  consents(userId: string): Promise<ConsentRec[]>;
  residency(userId: string): Promise<ResidencyRec | null>;
  /** Which of `handles` already belong to someone. */
  takenHandles(handles: string[]): Promise<string[]>;
  /** Replaces the user's outstanding offers. */
  offerHandles(userId: string, handles: string[], expiresAt: string): Promise<void>;
  /** accept_consent: creates the profile, or re-records consents for an existing one. */
  acceptConsent(p: NewProfile): Promise<ProfileRec>;
  /** claim_handle: raises too_soon / not_offered / consent_required. */
  claimHandle(userId: string, handle: string): Promise<ProfileRec>;
  setNotify(userId: string, notify: boolean, version: string, at: string): Promise<void>;
  /** issue_residency: raises consent_required. */
  issueResidency(r: NewResidency): Promise<ResidencyRec>;
  deleteResidency(userId: string): Promise<void>;
  /** Removes the profile (consents and residency cascade) and any offers. */
  deleteAccount(userId: string): Promise<void>;
}

/** The error a raising account function produces through PostgREST. */
export function raised(message: string, hint: string | null = null): PostgrestError {
  return new PostgrestError(`postgrest 400: ${message}`, 400, "P0001", message, hint);
}

export function handleChangeAvailableAt(changedAt: string | null): Date | null {
  if (!changedAt) return null;
  return new Date(Date.parse(changedAt) + HANDLE_CHANGE_DAYS * 86_400_000);
}

// ---------------------------------------------------------------- memory

export interface AccountTables {
  profiles: ProfileRec[];
  consents: ConsentRec[];
  offers: OfferRec[];
  residency: ResidencyRec[];
}

export function emptyAccountTables(): AccountTables {
  return { profiles: [], consents: [], offers: [], residency: [] };
}

export class MemoryAccountStore implements AccountStore {
  constructor(
    readonly t: AccountTables = emptyAccountTables(),
    /** Stands in for the database's now(). */
    private readonly now: () => Date = () => new Date(),
  ) {}

  private offered(userId: string, handle: string): boolean {
    const at = this.now().toISOString();
    return this.t.offers.some((o) =>
      o.user_id === userId && o.handle === handle && o.expires_at > at
    );
  }

  profile(userId: string) {
    const p = this.t.profiles.find((p) => p.user_id === userId);
    return Promise.resolve(p ? { ...p } : null);
  }
  consents(userId: string) {
    return Promise.resolve(
      this.t.consents.filter((c) => c.user_id === userId).map((c) => ({
        ...c,
      })),
    );
  }
  residency(userId: string) {
    const r = this.t.residency.find((r) => r.user_id === userId);
    return Promise.resolve(r ? { ...r } : null);
  }
  takenHandles(handles: string[]) {
    return Promise.resolve(
      this.t.profiles.map((p) => p.handle).filter((h) => handles.includes(h)),
    );
  }
  offerHandles(userId: string, handles: string[], expiresAt: string) {
    this.t.offers = [
      ...this.t.offers.filter((o) => o.user_id !== userId),
      ...handles.map((handle) => ({ user_id: userId, handle, expires_at: expiresAt })),
    ];
    return Promise.resolve();
  }
  acceptConsent(p: NewProfile) {
    const at = this.now().toISOString();
    const existing = this.t.profiles.find((x) => x.user_id === p.userId);
    if (!existing) {
      if (!this.offered(p.userId, p.handle)) return Promise.reject(raised("not_offered"));
      if (this.t.profiles.some((x) => x.handle === p.handle)) {
        return Promise.reject(new PostgrestError("postgrest 409", 409, "23505", "duplicate key"));
      }
      this.t.profiles.push({
        user_id: p.userId,
        provider: p.provider,
        email: p.email,
        handle: p.handle,
        handle_changed_at: null,
        notify: p.notify,
        created_at: at,
      });
      this.t.offers = this.t.offers.filter((o) => o.user_id !== p.userId);
    } else {
      existing.notify = p.notify;
    }
    const grants: [ConsentKind, boolean][] = [
      ["age14", true],
      ["terms", true],
      ["privacy", true],
      ["notify", p.notify],
    ];
    for (const [kind, granted] of grants) this.putConsent(p.userId, kind, p.version, granted, at);
    return this.profile(p.userId) as Promise<ProfileRec>;
  }
  claimHandle(userId: string, handle: string) {
    const p = this.t.profiles.find((x) => x.user_id === userId);
    if (!p) return Promise.reject(raised("consent_required"));
    const next = handleChangeAvailableAt(p.handle_changed_at);
    if (next && next > this.now()) {
      return Promise.reject(raised("too_soon", next.toISOString().replace(/\.\d{3}Z$/, "Z")));
    }
    if (!this.offered(userId, handle)) return Promise.reject(raised("not_offered"));
    if (this.t.profiles.some((x) => x.handle === handle && x.user_id !== userId)) {
      return Promise.reject(new PostgrestError("postgrest 409", 409, "23505", "duplicate key"));
    }
    p.handle = handle;
    p.handle_changed_at = this.now().toISOString();
    this.t.offers = this.t.offers.filter((o) => o.user_id !== userId);
    return Promise.resolve({ ...p });
  }
  setNotify(userId: string, notify: boolean, version: string, at: string) {
    const p = this.t.profiles.find((x) => x.user_id === userId);
    if (p) p.notify = notify;
    this.putConsent(userId, "notify", version, notify, at);
    return Promise.resolve();
  }
  issueResidency(r: NewResidency) {
    if (!this.t.profiles.some((p) => p.user_id === r.userId)) {
      return Promise.reject(raised("consent_required"));
    }
    const row: ResidencyRec = {
      user_id: r.userId,
      district_id: r.districtId,
      method: r.method,
      token_hash: r.tokenHash,
      verified_at: r.verifiedAt,
      expires_at: r.expiresAt,
    };
    this.t.residency = [...this.t.residency.filter((x) => x.user_id !== r.userId), row];
    return Promise.resolve({ ...row });
  }
  deleteResidency(userId: string) {
    this.t.residency = this.t.residency.filter((r) => r.user_id !== userId);
    return Promise.resolve();
  }
  deleteAccount(userId: string) {
    this.t.profiles = this.t.profiles.filter((r) => r.user_id !== userId);
    this.t.consents = this.t.consents.filter((r) => r.user_id !== userId);
    this.t.offers = this.t.offers.filter((r) => r.user_id !== userId);
    this.t.residency = this.t.residency.filter((r) => r.user_id !== userId);
    return Promise.resolve();
  }

  private putConsent(
    userId: string,
    kind: ConsentKind,
    version: string,
    granted: boolean,
    at: string,
  ) {
    this.t.consents = [
      ...this.t.consents.filter((c) =>
        !(c.user_id === userId && c.kind === kind && c.version === version)
      ),
      { user_id: userId, kind, version, granted, at },
    ];
  }
}

// ---------------------------------------------------------------- postgrest

const PROFILE_COLS = "user_id,provider,email,handle,handle_changed_at,notify,created_at";
const RESIDENCY_COLS = "user_id,district_id,method,token_hash,verified_at,expires_at";

export class PostgrestAccountStore implements AccountStore {
  constructor(private readonly db: Postgrest) {}

  async profile(userId: string) {
    const [row] = await this.db.select<ProfileRec>("profiles", {
      select: PROFILE_COLS,
      user_id: `eq.${userId}`,
    });
    return row ?? null;
  }
  consents(userId: string) {
    return this.db.select<ConsentRec>("consents", {
      select: "user_id,kind,version,granted,at",
      user_id: `eq.${userId}`,
      order: "at.asc",
    });
  }
  async residency(userId: string) {
    const [row] = await this.db.select<ResidencyRec>("residency_verifications", {
      select: RESIDENCY_COLS,
      user_id: `eq.${userId}`,
    });
    return row ?? null;
  }
  async takenHandles(handles: string[]) {
    if (handles.length === 0) return [];
    const rows = await this.db.select<{ handle: string }>("profiles", {
      select: "handle",
      handle: inList(handles),
    });
    return rows.map((r) => r.handle);
  }
  async offerHandles(userId: string, handles: string[], expiresAt: string) {
    await this.db.delete("handle_offers", { user_id: `eq.${userId}` });
    await this.db.upsert(
      "handle_offers",
      handles.map((handle) => ({ user_id: userId, handle, expires_at: expiresAt })),
      "user_id,handle",
    );
  }
  async acceptConsent(p: NewProfile) {
    const [row] = await this.db.rpc<ProfileRec[]>("accept_consent", {
      p_user_id: p.userId,
      p_provider: p.provider,
      p_email: p.email,
      p_handle: p.handle,
      p_notify: p.notify,
      p_version: p.version,
    });
    return row;
  }
  async claimHandle(userId: string, handle: string) {
    const [row] = await this.db.rpc<ProfileRec[]>("claim_handle", {
      p_user_id: userId,
      p_handle: handle,
    });
    return row;
  }
  async setNotify(userId: string, notify: boolean, version: string, at: string) {
    await this.db.update("profiles", { user_id: `eq.${userId}` }, { notify });
    await this.db.upsert(
      "consents",
      [{ user_id: userId, kind: "notify", version, granted: notify, at }],
      "user_id,kind,version",
    );
  }
  async issueResidency(r: NewResidency) {
    const [row] = await this.db.rpc<ResidencyRec[]>("issue_residency", {
      p_user_id: r.userId,
      p_district_id: r.districtId,
      p_method: r.method,
      p_token_hash: r.tokenHash,
      p_verified_at: r.verifiedAt,
      p_expires_at: r.expiresAt,
    });
    return row;
  }
  deleteResidency(userId: string) {
    return this.db.delete("residency_verifications", { user_id: `eq.${userId}` });
  }
  async deleteAccount(userId: string) {
    await this.db.delete("handle_offers", { user_id: `eq.${userId}` });
    await this.db.delete("profiles", { user_id: `eq.${userId}` });
  }
}
