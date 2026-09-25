// Account routes. Every one needs a signed-in user (Authorization: Bearer <user JWT>);
// the anon key alone is 401. Responses are never cached.
//
//   GET    /me                  {profile|null, consents, residency|null}
//   POST   /me/consent          {age14, terms, privacy, notify, handle} → /me
//   POST   /me/under14          deletes the auth user; nothing is created
//   GET    /me/handle/options   {handles: [5], expiresAt}; stored as the only valid picks
//   POST   /me/handle           {handle} → /me   (30-day limit → 429 too_soon)
//   PATCH  /me                  {notify} → /me
//   GET    /me/export           everything held about the user, minus secrets
//   DELETE /me?posts=keep|delete
//
// No route accepts or returns a real name, phone number or birth date.

import type { Auth, AuthUser } from "../_shared/auth.ts";
import { bearerFrom } from "../_shared/auth.ts";
import { ApiError } from "../_shared/envelope.ts";
import { drawHandles, HANDLE_PATTERN } from "../_shared/handles.ts";
import { PostgrestError } from "../_shared/postgrest.ts";
import {
  type AccountStore,
  type ConsentRec,
  handleChangeAvailableAt,
  type ProfileRec,
  type ResidencyRec,
} from "./account_store.ts";
import type { ReadStore } from "./store.ts";

/** Version stamped on consent rows; bump when the terms or privacy text changes. */
export const CONSENT_VERSION = "2026-09-26";
/** How long drawn 활동명 stay pickable. */
export const HANDLE_OFFER_MINUTES = 30;
const OFFER_COUNT = 5;
/** Drawn before dropping taken ones, so five usually survive. */
const OFFER_DRAW = 12;
const PROVIDERS = new Set(["apple", "kakao", "google", "email"]);
/** Account request bodies are a few small fields. */
const MAX_BODY = 2048;

export interface AccountContext {
  store: ReadStore;
  accounts: AccountStore;
  auth: Auth;
  randomBytes: (n: number) => Uint8Array;
  now: () => Date;
}

export async function requireUser(ctx: AccountContext, req: Request): Promise<AuthUser> {
  const user = await ctx.auth.user(bearerFrom(req));
  if (!user) throw new ApiError("unauthorized", "Sign in to continue.");
  return user;
}

export async function requireProfile(ctx: AccountContext, userId: string): Promise<ProfileRec> {
  const profile = await ctx.accounts.profile(userId);
  if (!profile) throw new ApiError("consent_required", "Accept the terms first.");
  return profile;
}

export async function readBody(req: Request): Promise<Record<string, unknown>> {
  const text = await req.text();
  if (text.length > MAX_BODY) throw new ApiError("bad_request", "Body too large.");
  try {
    const json = JSON.parse(text);
    if (json && typeof json === "object" && !Array.isArray(json)) return json;
  } catch {
    // fall through
  }
  throw new ApiError("bad_request", "Body must be a JSON object.");
}

const iso = (s: string | null) => (s === null ? null : new Date(s).toISOString());

/**
 * Maps what the account SQL functions raise to API errors. Anything else is left for
 * the router's generic handling (internal).
 */
export function accountError(error: unknown): unknown {
  if (!(error instanceof PostgrestError)) return error;
  if (error.code === "23505") {
    return new ApiError("conflict", "That name was just taken. Draw new options.");
  }
  if (error.code !== "P0001") return error;
  switch (error.dbMessage) {
    case "consent_required":
      return new ApiError("consent_required", "Accept the terms first.");
    case "not_offered":
      return new ApiError("forbidden", "Pick one of the names you were offered.");
    case "too_soon":
      return new ApiError(
        "too_soon",
        "The name can change once every 30 days.",
        error.hint ? { availableAt: iso(error.hint)! } : undefined,
      );
  }
  return error;
}

function profileView(p: ProfileRec) {
  const next = handleChangeAvailableAt(p.handle_changed_at);
  return {
    handle: p.handle,
    provider: p.provider,
    email: p.email,
    notify: p.notify,
    handleChangedAt: iso(p.handle_changed_at),
    handleChangeAvailableAt: next ? next.toISOString() : null,
    createdAt: iso(p.created_at),
  };
}

const consentView = (c: ConsentRec) => ({
  kind: c.kind,
  version: c.version,
  granted: c.granted,
  at: iso(c.at),
});

/** The token hash stays server-side; the device holds the token itself. */
async function residencyView(ctx: AccountContext, r: ResidencyRec) {
  const d = await ctx.store.district(r.district_id);
  return {
    districtId: r.district_id,
    displayName: d?.display_name ?? null,
    method: r.method,
    verifiedAt: iso(r.verified_at),
    expiresAt: iso(r.expires_at),
  };
}

export async function mePayload(ctx: AccountContext, userId: string) {
  const [profile, consents, residency] = await Promise.all([
    ctx.accounts.profile(userId),
    ctx.accounts.consents(userId),
    ctx.accounts.residency(userId),
  ]);
  const live = residency && Date.parse(residency.expires_at) > ctx.now().getTime();
  return {
    profile: profile ? profileView(profile) : null,
    consents: consents.map(consentView),
    residency: live ? await residencyView(ctx, residency) : null,
  };
}

function tooSoon(p: ProfileRec, now: Date): ApiError | null {
  const next = handleChangeAvailableAt(p.handle_changed_at);
  if (!next || next <= now) return null;
  return new ApiError("too_soon", "The name can change once every 30 days.", {
    availableAt: next.toISOString(),
  });
}

/** Handles account paths; null when `path` is not one of them. */
export async function handleAccount(
  ctx: AccountContext,
  req: Request,
  url: URL,
  path: string,
): Promise<unknown | null> {
  if (path !== "/me" && !path.startsWith("/me/")) return null;
  const route = `${req.method} ${path}`;
  const known = [
    "GET /me",
    "PATCH /me",
    "DELETE /me",
    "POST /me/consent",
    "POST /me/under14",
    "GET /me/handle/options",
    "POST /me/handle",
    "GET /me/export",
  ];
  if (!known.includes(route)) {
    const pathKnown = known.some((k) => k.endsWith(` ${path}`));
    throw pathKnown
      ? new ApiError("bad_request", `${req.method} is not supported here.`)
      : new ApiError("not_found", "No such route.");
  }

  const user = await requireUser(ctx, req);
  try {
    return await accountRoute(ctx, req, url, route, user);
  } catch (error) {
    throw accountError(error);
  }
}

async function accountRoute(
  ctx: AccountContext,
  req: Request,
  url: URL,
  route: string,
  user: AuthUser,
): Promise<unknown> {
  const now = ctx.now();
  switch (route) {
    case "GET /me":
      return mePayload(ctx, user.id);

    case "POST /me/consent": {
      const body = await readBody(req);
      for (const required of ["age14", "terms", "privacy"]) {
        if (body[required] !== true) {
          throw new ApiError("bad_request", `${required} must be accepted.`);
        }
      }
      if (body.notify !== undefined && typeof body.notify !== "boolean") {
        throw new ApiError("bad_request", "notify must be a boolean.");
      }
      if (typeof body.handle !== "string" || !HANDLE_PATTERN.test(body.handle)) {
        throw new ApiError("bad_request", "handle must be one of the offered names.");
      }
      if (!user.provider || !PROVIDERS.has(user.provider)) {
        throw new ApiError("forbidden", "This sign-in method is not supported.");
      }
      await ctx.accounts.acceptConsent({
        userId: user.id,
        provider: user.provider,
        email: user.email,
        handle: body.handle,
        notify: body.notify === true,
        version: CONSENT_VERSION,
      });
      return mePayload(ctx, user.id);
    }

    case "POST /me/under14": {
      // Before any profile exists: the user said they are under 14, so nothing about them
      // may be kept. With a profile this would bypass DELETE /me's posts choice.
      if (await ctx.accounts.profile(user.id)) {
        throw new ApiError("conflict", "An account exists; use DELETE /me.");
      }
      await ctx.accounts.deleteAccount(user.id);
      await ctx.auth.deleteUser(user.id);
      return { deleted: true };
    }

    case "GET /me/handle/options": {
      const profile = await ctx.accounts.profile(user.id);
      const blocked = profile && tooSoon(profile, now);
      if (blocked) throw blocked;
      const drawn = drawHandles(
        OFFER_DRAW,
        ctx.randomBytes,
        new Set(profile ? [profile.handle] : []),
      );
      const taken = new Set(await ctx.accounts.takenHandles(drawn));
      const handles = drawn.filter((h) => !taken.has(h)).slice(0, OFFER_COUNT);
      const expiresAt = new Date(now.getTime() + HANDLE_OFFER_MINUTES * 60_000).toISOString();
      await ctx.accounts.offerHandles(user.id, handles, expiresAt);
      return { handles, expiresAt };
    }

    case "POST /me/handle": {
      const body = await readBody(req);
      if (typeof body.handle !== "string" || !HANDLE_PATTERN.test(body.handle)) {
        throw new ApiError("bad_request", "handle must be one of the offered names.");
      }
      await ctx.accounts.claimHandle(user.id, body.handle);
      return mePayload(ctx, user.id);
    }

    case "PATCH /me": {
      const body = await readBody(req);
      if (typeof body.notify !== "boolean") {
        throw new ApiError("bad_request", "notify must be a boolean.");
      }
      await requireProfile(ctx, user.id);
      await ctx.accounts.setNotify(user.id, body.notify, CONSENT_VERSION, now.toISOString());
      return mePayload(ctx, user.id);
    }

    case "GET /me/export": {
      // What is held, not what is shown: includes an expired residency. Never the token
      // hash, and there is no address or coordinate anywhere to export.
      const [profile, consents, residency] = await Promise.all([
        ctx.accounts.profile(user.id),
        ctx.accounts.consents(user.id),
        ctx.accounts.residency(user.id),
      ]);
      return {
        exportedAt: now.toISOString(),
        account: { id: user.id, provider: user.provider, email: user.email },
        profile: profile ? profileView(profile) : null,
        consents: consents.map(consentView),
        residency: residency ? await residencyView(ctx, residency) : null,
      };
    }

    case "DELETE /me": {
      const posts = url.searchParams.get("posts");
      if (posts !== "keep" && posts !== "delete") {
        throw new ApiError("bad_request", "posts must be keep or delete.");
      }
      // There is no posts table yet. When there is, posts=delete removes the user's posts
      // here, and posts=keep relies on author_id ... on delete set null (see migration).
      await ctx.accounts.deleteAccount(user.id);
      await ctx.auth.deleteUser(user.id);
      return { deleted: true, posts };
    }
  }
  throw new ApiError("not_found", "No such route.");
}
