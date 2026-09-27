// Storage for resident posts: reviews, channel messages, threads and their replies.
// Kept apart from ReadStore (public records) and AccountStore (one user's own rows):
// these are written by one user and read by everyone.
//
// Two implementations, like the others: PostgREST (prod) and in-memory (tests). The rules
// that must hold under concurrency -- profile, residency for the same district, the rate
// limit, one review per user per district -- live in the SQL functions of the community
// migration; the memory store mirrors them and fails with the same PostgrestError code and
// message. Deleted accounts are mirrored too: the memory store treats an author without a
// profile as null, which is what `on delete set null` leaves behind.

import { type Postgrest, PostgrestError } from "../_shared/postgrest.ts";
import { isPresentableSourceUrl } from "../_shared/provenance.ts";
import { type AccountTables, raised } from "./account_store.ts";
import { emptyTables, type MemoryTables } from "./store.ts";

/** The app's ReviewDraft.axes, in its order, and the column each is stored in. */
export const REVIEW_AXES = [
  ["소통", "communication"],
  ["공약이행", "pledges"],
  ["지역발전", "development"],
  ["도덕성", "integrity"],
] as const;

/** Posts per user per minute, across reviews, messages and replies. Mirrors the SQL. */
export const POSTS_PER_MINUTE = 5;

export interface ReviewRec {
  id: string;
  district_id: string;
  author_id: string | null;
  communication: number;
  pledges: number;
  development: number;
  integrity: number;
  score: number;
  body: string;
  anonymous: boolean;
  verified_resident: boolean;
  created_at: string;
  updated_at: string;
}

export interface MessageRec {
  id: string;
  district_id: string;
  author_id: string | null;
  body: string;
  anonymous: boolean;
  verified_resident: boolean;
  created_at: string;
}

export interface ThreadRec {
  id: string;
  district_id: string;
  origin: "bill";
  bill_id: string | null;
  title: string;
  source_url: string;
  opened_at: string;
}

export interface ReplyRec {
  id: string;
  thread_id: string;
  author_id: string | null;
  body: string;
  anonymous: boolean;
  verified_resident: boolean;
  created_at: string;
}

/** A post as read for display: the author's current 활동명, or null when the account is gone. */
export type WithHandle<T> = T & { author_handle: string | null };

export interface ThreadView {
  id: string;
  title: string;
  origin: "bill";
  source_url: string;
  opened_at: string;
  replies: number;
}

export interface ReviewSummaryRec {
  respondents: number;
  average: number | null;
  communication: number | null;
  pledges: number | null;
  development: number | null;
  integrity: number | null;
}

export interface NewReview {
  userId: string;
  districtId: string;
  communication: number;
  pledges: number;
  development: number;
  integrity: number;
  body: string;
  anonymous: boolean;
}

export interface NewMessage {
  userId: string;
  districtId: string;
  body: string;
  anonymous: boolean;
}

export interface CommunityStore {
  reviewSummary(districtId: string): Promise<ReviewSummaryRec>;
  recentReviews(districtId: string, limit: number): Promise<WithHandle<ReviewRec>[]>;
  review(id: string): Promise<ReviewRec | null>;
  /** post_review: raises consent_required / residency_required / rate_limited. */
  postReview(r: NewReview): Promise<ReviewRec>;
  deleteReview(id: string): Promise<void>;
  /** The newest [limit] messages, oldest first (the channel reads from the bottom). */
  recentMessages(districtId: string, limit: number): Promise<WithHandle<MessageRec>[]>;
  message(id: string): Promise<MessageRec | null>;
  /** post_message: raises like postReview. */
  postMessage(m: NewMessage): Promise<MessageRec>;
  deleteMessage(id: string): Promise<void>;
  threads(districtId: string, limit: number): Promise<ThreadView[]>;
  /** Everything the user wrote, for GET /me/export. */
  postsBy(userId: string): Promise<{
    reviews: ReviewRec[];
    messages: MessageRec[];
    replies: ReplyRec[];
  }>;
  /** DELETE /me?posts=delete: removes the user's posts before the profile goes. */
  deletePostsBy(userId: string): Promise<void>;
}

// ---------------------------------------------------------------- memory

export interface CommunityTables {
  reviews: ReviewRec[];
  messages: MessageRec[];
  threads: ThreadRec[];
  replies: ReplyRec[];
}

export function emptyCommunityTables(): CommunityTables {
  return { reviews: [], messages: [], threads: [], replies: [] };
}

const mean = (xs: number[]) =>
  xs.length === 0 ? null : Math.round((xs.reduce((a, b) => a + b, 0) / xs.length) * 100) / 100;

export class MemoryCommunityStore implements CommunityStore {
  private seq = 0;

  constructor(
    /** The account tables, for profiles (handles, deleted authors) and residency. */
    private readonly accounts: AccountTables,
    /** The public tables: districts (the foreign key), bills and members (threads). */
    private readonly read: MemoryTables = emptyTables(),
    readonly t: CommunityTables = emptyCommunityTables(),
    /** Stands in for the database's now(). */
    private readonly now: () => Date = () => new Date(),
  ) {}

  private nextId(): string {
    this.seq += 1;
    return `00000000-0000-4000-9000-${String(this.seq).padStart(12, "0")}`;
  }

  /** `on delete set null`: an author whose profile is gone reads as null. */
  private author(id: string | null): string | null {
    return id !== null && this.accounts.profiles.some((p) => p.user_id === id) ? id : null;
  }

  private handle(id: string | null): string | null {
    return this.accounts.profiles.find((p) => p.user_id === id)?.handle ?? null;
  }

  private writeCheck(userId: string, districtId: string): PostgrestError | null {
    if (!this.accounts.profiles.some((p) => p.user_id === userId)) {
      return raised("consent_required");
    }
    const at = this.now().toISOString();
    if (
      !this.accounts.residency.some((r) =>
        r.user_id === userId && r.district_id === districtId && r.expires_at > at
      )
    ) {
      return raised("residency_required");
    }
    if (!this.read.districts.some((d) => d.id === districtId)) {
      return new PostgrestError("postgrest 409", 409, "23503", "foreign key");
    }
    const since = new Date(this.now().getTime() - 60_000).toISOString();
    const recent = this.t.reviews.filter((r) => r.author_id === userId && r.updated_at > since)
      .length +
      this.t.messages.filter((m) => m.author_id === userId && m.created_at > since).length +
      this.t.replies.filter((r) => r.author_id === userId && r.created_at > since).length;
    return recent >= POSTS_PER_MINUTE ? raised("rate_limited") : null;
  }

  private live<T extends { author_id: string | null }>(row: T): T {
    return { ...row, author_id: this.author(row.author_id) };
  }

  reviewSummary(districtId: string) {
    const rows = this.t.reviews.filter((r) => r.district_id === districtId);
    return Promise.resolve({
      respondents: rows.length,
      average: mean(rows.map((r) => r.score)),
      communication: mean(rows.map((r) => r.communication)),
      pledges: mean(rows.map((r) => r.pledges)),
      development: mean(rows.map((r) => r.development)),
      integrity: mean(rows.map((r) => r.integrity)),
    });
  }
  recentReviews(districtId: string, limit: number) {
    return Promise.resolve(
      this.t.reviews
        .filter((r) => r.district_id === districtId)
        .sort((a, b) => b.updated_at.localeCompare(a.updated_at) || b.id.localeCompare(a.id))
        .slice(0, limit)
        .map((r) => ({ ...this.live(r), author_handle: this.handle(this.author(r.author_id)) })),
    );
  }
  review(id: string) {
    const r = this.t.reviews.find((r) => r.id === id);
    return Promise.resolve(r ? this.live(r) : null);
  }
  postReview(r: NewReview) {
    const failed = this.writeCheck(r.userId, r.districtId);
    if (failed) return Promise.reject(failed);
    const at = this.now().toISOString();
    const scores = {
      communication: r.communication,
      pledges: r.pledges,
      development: r.development,
      integrity: r.integrity,
    };
    const score = (r.communication + r.pledges + r.development + r.integrity) / 4;
    const existing = this.t.reviews.find((x) =>
      x.district_id === r.districtId && x.author_id === r.userId
    );
    if (existing) {
      Object.assign(existing, scores, {
        score,
        body: r.body,
        anonymous: r.anonymous,
        verified_resident: true,
        updated_at: at,
      });
      return Promise.resolve({ ...existing });
    }
    const row: ReviewRec = {
      id: this.nextId(),
      district_id: r.districtId,
      author_id: r.userId,
      ...scores,
      score,
      body: r.body,
      anonymous: r.anonymous,
      verified_resident: true,
      created_at: at,
      updated_at: at,
    };
    this.t.reviews.push(row);
    return Promise.resolve({ ...row });
  }
  deleteReview(id: string) {
    this.t.reviews = this.t.reviews.filter((r) => r.id !== id);
    return Promise.resolve();
  }
  recentMessages(districtId: string, limit: number) {
    return Promise.resolve(
      this.t.messages
        .filter((m) => m.district_id === districtId)
        .sort((a, b) => b.created_at.localeCompare(a.created_at) || b.id.localeCompare(a.id))
        .slice(0, limit)
        .reverse()
        .map((m) => ({ ...this.live(m), author_handle: this.handle(this.author(m.author_id)) })),
    );
  }
  message(id: string) {
    const m = this.t.messages.find((m) => m.id === id);
    return Promise.resolve(m ? this.live(m) : null);
  }
  postMessage(m: NewMessage) {
    const failed = this.writeCheck(m.userId, m.districtId);
    if (failed) return Promise.reject(failed);
    const row: MessageRec = {
      id: this.nextId(),
      district_id: m.districtId,
      author_id: m.userId,
      body: m.body,
      anonymous: m.anonymous,
      verified_resident: true,
      created_at: this.now().toISOString(),
    };
    this.t.messages.push(row);
    return Promise.resolve({ ...row });
  }
  deleteMessage(id: string) {
    this.t.messages = this.t.messages.filter((m) => m.id !== id);
    return Promise.resolve();
  }
  threads(districtId: string, limit: number) {
    return Promise.resolve(
      this.t.threads
        .filter((t) => t.district_id === districtId)
        .sort((a, b) => b.opened_at.localeCompare(a.opened_at) || b.id.localeCompare(a.id))
        .slice(0, limit)
        .map((t) => ({
          id: t.id,
          title: t.title,
          origin: t.origin,
          source_url: t.source_url,
          opened_at: t.opened_at,
          replies: this.t.replies.filter((r) => r.thread_id === t.id).length,
        })),
    );
  }
  postsBy(userId: string) {
    const mine = <T extends { author_id: string | null }>(rows: T[]) =>
      rows.filter((r) => this.author(r.author_id) === userId).map((r) => ({ ...r }));
    return Promise.resolve({
      reviews: mine(this.t.reviews),
      messages: mine(this.t.messages),
      replies: mine(this.t.replies),
    });
  }
  deletePostsBy(userId: string) {
    this.t.reviews = this.t.reviews.filter((r) => r.author_id !== userId);
    this.t.messages = this.t.messages.filter((m) => m.author_id !== userId);
    this.t.replies = this.t.replies.filter((r) => r.author_id !== userId);
    return Promise.resolve();
  }

  /**
   * Mirrors sync_bill_threads(): a thread per current-term bill whose 대표발의자 is a
   * district's current member, existing threads left alone.
   */
  syncBillThreads(): number {
    const read = this.read;
    const age = Math.max(...read.bills.map((b) => b.age));
    let added = 0;
    for (const b of read.bills.filter((b) => b.age === age)) {
      const m = read.members.find((m) =>
        m.mona_cd === b.rst_mona_cd && m.is_current && m.district_id !== null
      );
      const id = `bill-${b.bill_id}`;
      if (!m || this.t.threads.some((t) => t.id === id)) continue;
      const link = b.detail_link;
      this.t.threads.push({
        id,
        district_id: m.district_id!,
        origin: "bill",
        bill_id: b.bill_id,
        title: b.bill_name,
        source_url: isPresentableSourceUrl(link) ? link : b.source_url!,
        opened_at: b.propose_dt ? new Date(b.propose_dt).toISOString() : b.fetched_at!,
      });
      added += 1;
    }
    return added;
  }
}

// ---------------------------------------------------------------- postgrest

const REVIEW_COLS = "id,district_id,author_id,communication,pledges,development,integrity," +
  "score,body,anonymous,verified_resident,created_at,updated_at";
const MESSAGE_COLS = "id,district_id,author_id,body,anonymous,verified_resident,created_at";
const REPLY_COLS = "id,thread_id,author_id,body,anonymous,verified_resident,created_at";

/** Rows read with the author's handle embedded through the profiles foreign key. */
type Embedded<T> = T & { author: { handle: string } | null };

function flatten<T>(row: Embedded<T>): WithHandle<T> {
  const { author, ...rest } = row;
  return { ...(rest as T), author_handle: author?.handle ?? null };
}

const num = (v: unknown) => (v === null || v === undefined ? null : Number(v));

export class PostgrestCommunityStore implements CommunityStore {
  constructor(private readonly db: Postgrest) {}

  async reviewSummary(districtId: string) {
    const [row] = await this.db.rpc<Record<string, unknown>[]>("bff_review_summary", {
      p_district_id: districtId,
    });
    return {
      respondents: Number(row?.respondents ?? 0),
      average: num(row?.average),
      communication: num(row?.communication),
      pledges: num(row?.pledges),
      development: num(row?.development),
      integrity: num(row?.integrity),
    };
  }
  async recentReviews(districtId: string, limit: number) {
    const rows = await this.db.select<Embedded<ReviewRec>>("reviews", {
      select: `${REVIEW_COLS},author:profiles(handle)`,
      district_id: `eq.${districtId}`,
      order: "updated_at.desc,id.desc",
      limit: String(limit),
    });
    return rows.map((r) => ({ ...flatten(r), score: Number(r.score) }));
  }
  async review(id: string) {
    const [row] = await this.db.select<ReviewRec>("reviews", {
      select: REVIEW_COLS,
      id: `eq.${id}`,
    });
    return row ?? null;
  }
  async postReview(r: NewReview) {
    const [row] = await this.db.rpc<ReviewRec[]>("post_review", {
      p_user_id: r.userId,
      p_district_id: r.districtId,
      p_communication: r.communication,
      p_pledges: r.pledges,
      p_development: r.development,
      p_integrity: r.integrity,
      p_body: r.body,
      p_anonymous: r.anonymous,
    });
    return row;
  }
  deleteReview(id: string) {
    return this.db.delete("reviews", { id: `eq.${id}` });
  }
  async recentMessages(districtId: string, limit: number) {
    const rows = await this.db.select<Embedded<MessageRec>>("community_messages", {
      select: `${MESSAGE_COLS},author:profiles(handle)`,
      district_id: `eq.${districtId}`,
      order: "created_at.desc,id.desc",
      limit: String(limit),
    });
    return rows.map(flatten).reverse();
  }
  async message(id: string) {
    const [row] = await this.db.select<MessageRec>("community_messages", {
      select: MESSAGE_COLS,
      id: `eq.${id}`,
    });
    return row ?? null;
  }
  async postMessage(m: NewMessage) {
    const [row] = await this.db.rpc<MessageRec[]>("post_message", {
      p_user_id: m.userId,
      p_district_id: m.districtId,
      p_body: m.body,
      p_anonymous: m.anonymous,
    });
    return row;
  }
  deleteMessage(id: string) {
    return this.db.delete("community_messages", { id: `eq.${id}` });
  }
  threads(districtId: string, limit: number) {
    return this.db.rpc<ThreadView[]>("bff_district_threads", {
      p_district_id: districtId,
      p_limit: limit,
    });
  }
  async postsBy(userId: string) {
    const by = { author_id: `eq.${userId}` };
    const [reviews, messages, replies] = await Promise.all([
      this.db.select<ReviewRec>("reviews", { select: REVIEW_COLS, ...by, order: "created_at.asc" }),
      this.db.select<MessageRec>("community_messages", {
        select: MESSAGE_COLS,
        ...by,
        order: "created_at.asc",
      }),
      this.db.select<ReplyRec>("thread_replies", {
        select: REPLY_COLS,
        ...by,
        order: "created_at.asc",
      }),
    ]);
    return { reviews: reviews.map((r) => ({ ...r, score: Number(r.score) })), messages, replies };
  }
  async deletePostsBy(userId: string) {
    const by = { author_id: `eq.${userId}` };
    await this.db.delete("thread_replies", by);
    await this.db.delete("community_messages", by);
    await this.db.delete("reviews", by);
  }
}

// ---------------------------------------------------------------- export

const iso = (s: string) => new Date(s).toISOString();

/** The user's own posts for GET /me/export. */
export async function exportPosts(community: CommunityStore, userId: string) {
  const { reviews, messages, replies } = await community.postsBy(userId);
  return {
    reviews: reviews.map((r) => ({
      id: r.id,
      districtId: r.district_id,
      scores: Object.fromEntries(REVIEW_AXES.map(([label, col]) => [label, r[col]])),
      body: r.body,
      anonymous: r.anonymous,
      verifiedResident: r.verified_resident,
      createdAt: iso(r.created_at),
      updatedAt: iso(r.updated_at),
    })),
    messages: messages.map((m) => ({
      id: m.id,
      districtId: m.district_id,
      body: m.body,
      anonymous: m.anonymous,
      verifiedResident: m.verified_resident,
      createdAt: iso(m.created_at),
    })),
    threadReplies: replies.map((r) => ({
      id: r.id,
      threadId: r.thread_id,
      body: r.body,
      anonymous: r.anonymous,
      verifiedResident: r.verified_resident,
      createdAt: iso(r.created_at),
    })),
  };
}
