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
  hidden_at?: string | null;
}

export interface MessageRec {
  id: string;
  district_id: string;
  author_id: string | null;
  body: string;
  anonymous: boolean;
  verified_resident: boolean;
  created_at: string;
  hidden_at?: string | null;
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
  hidden_at?: string | null;
}

/** What can be reported or blocked: a review, a channel message or a thread reply. */
export type PostType = "review" | "message" | "reply";
export const POST_TYPES: readonly PostType[] = ["review", "message", "reply"];
export type ReportReason = "hate" | "privacy" | "false" | "spam" | "other";
export const REPORT_REASONS: readonly ReportReason[] = [
  "hate",
  "privacy",
  "false",
  "spam",
  "other",
];
export type ResolveAction = "keep" | "hide" | "delete";

/** Reports one reader may file in a day. Mirrors report_post(). */
export const REPORTS_PER_DAY = 20;
/** Distinct readers whose open reports hide a post. Mirrors report_post(). */
export const REPORTS_TO_HIDE = 3;

export interface NewReport {
  reporterId: string;
  targetType: PostType;
  targetId: string;
  reason: ReportReason;
  note: string | null;
}

export interface ReportRec {
  id: string;
  target_type: PostType;
  target_id: string;
  reporter_id: string | null;
  reason: ReportReason;
  note: string | null;
  status: "open" | "kept" | "hidden" | "deleted";
  created_at: string;
  resolved_by: string | null;
  resolved_at: string | null;
}

export interface BlockRec {
  id: string;
  blocker_id: string;
  blocked_id: string;
  label: string;
  created_at: string;
}

/** A reader's block as they see it: never the account, only how it showed and its tag. */
export interface BlockView {
  id: string;
  label: string;
  created_at: string;
  author_tag: string | null;
}

export interface StaffReportView {
  report_id: string;
  target_type: PostType;
  target_id: string;
  district_id: string | null;
  body: string | null;
  hidden: boolean;
  reasons: ReportReason[];
  reports: number;
  first_at: string;
}

export interface StaffActionRec {
  id: string;
  staff_id: string | null;
  action: ResolveAction;
  target_type: PostType;
  target_id: string;
  reason: string;
  at: string;
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

  /**
   * report_post: files a report; true when the post is hidden afterwards. Raises
   * consent_required / not_found / own_post / already_reported / rate_limited.
   */
  report(r: NewReport): Promise<boolean>;
  /** block_author: raises consent_required / not_found / no_author / own_post. */
  block(blockerId: string, targetType: PostType, targetId: string): Promise<BlockRec>;
  /** Removes one of the blocker's blocks; false when it is not theirs or not there. */
  unblock(blockerId: string, blockId: string): Promise<boolean>;
  myBlocks(userId: string): Promise<BlockView[]>;
  /** The authors whose posts are left out of this reader's lists. */
  blockedAuthors(userId: string): Promise<string[]>;
  isStaff(userId: string): Promise<boolean>;
  openReports(limit: number): Promise<StaffReportView[]>;
  /** resolve_report: raises not_staff / not_found. */
  resolveReport(
    staffId: string,
    reportId: string,
    action: ResolveAction,
    reason: string,
  ): Promise<void>;
}

// ---------------------------------------------------------------- memory

export interface CommunityTables {
  reviews: ReviewRec[];
  messages: MessageRec[];
  threads: ThreadRec[];
  replies: ReplyRec[];
  reports: ReportRec[];
  blocks: BlockRec[];
  staff: string[];
  staffActions: StaffActionRec[];
}

export function emptyCommunityTables(): CommunityTables {
  return {
    reviews: [],
    messages: [],
    threads: [],
    replies: [],
    reports: [],
    blocks: [],
    staff: [],
    staffActions: [],
  };
}

/**
 * Stands in for author_tag(): stable within a KST day, different the next. The SQL one is
 * an HMAC under a key only the database holds.
 */
export function memoryAuthorTag(author: string | null, at: Date): string | null {
  if (author === null) return null;
  const kstDay = new Date(at.getTime() + 9 * 3_600_000).toISOString().slice(0, 10);
  // FNV-1a: opaque enough that a test can check the author id never shows.
  let h = 0x811c9dc5;
  for (const c of `${author}:${kstDay}`) {
    h = Math.imul(h ^ c.charCodeAt(0), 0x01000193) >>> 0;
  }
  return `tag${h.toString(16).padStart(8, "0")}`;
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
    const rows = this.t.reviews.filter((r) => r.district_id === districtId && !r.hidden_at);
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

  private posts(
    type: PostType,
  ): {
    id: string;
    author_id: string | null;
    anonymous: boolean;
    hidden_at?: string | null;
    hidden_reason?: string | null;
  }[] {
    return type === "review"
      ? this.t.reviews
      : type === "message"
      ? this.t.messages
      : this.t.replies;
  }

  private hide(type: PostType, id: string, reason: string | null) {
    const row = this.posts(type).find((p) => p.id === id);
    if (row) {
      row.hidden_at = reason === null ? null : this.now().toISOString();
      row.hidden_reason = reason;
    }
  }

  report(r: NewReport) {
    if (!this.accounts.profiles.some((p) => p.user_id === r.reporterId)) {
      return Promise.reject(raised("consent_required"));
    }
    const post = this.posts(r.targetType).find((p) => p.id === r.targetId);
    if (!post) return Promise.reject(raised("not_found"));
    if (this.author(post.author_id) === r.reporterId) return Promise.reject(raised("own_post"));
    const since = new Date(this.now().getTime() - 86_400_000).toISOString();
    if (
      this.t.reports.filter((x) => x.reporter_id === r.reporterId && x.created_at > since)
        .length >= REPORTS_PER_DAY
    ) {
      return Promise.reject(raised("rate_limited"));
    }
    const same = (x: ReportRec) => x.target_type === r.targetType && x.target_id === r.targetId;
    if (this.t.reports.some((x) => same(x) && x.reporter_id === r.reporterId)) {
      return Promise.reject(raised("already_reported"));
    }
    this.t.reports.push({
      id: this.nextId(),
      target_type: r.targetType,
      target_id: r.targetId,
      reporter_id: r.reporterId,
      reason: r.reason,
      note: r.note,
      status: "open",
      created_at: this.now().toISOString(),
      resolved_by: null,
      resolved_at: null,
    });
    const reporters = new Set(
      this.t.reports.filter((x) => same(x) && x.status === "open").map((x) => x.reporter_id),
    ).size;
    if (r.reason === "privacy" || reporters >= REPORTS_TO_HIDE) {
      this.hide(r.targetType, r.targetId, r.reason === "privacy" ? "privacy" : "reports");
      return Promise.resolve(true);
    }
    return Promise.resolve(false);
  }
  block(blockerId: string, targetType: PostType, targetId: string) {
    if (!this.accounts.profiles.some((p) => p.user_id === blockerId)) {
      return Promise.reject(raised("consent_required"));
    }
    const post = this.posts(targetType).find((p) => p.id === targetId);
    if (!post) return Promise.reject(raised("not_found"));
    const author = this.author(post.author_id);
    if (author === null) return Promise.reject(raised("no_author"));
    if (author === blockerId) return Promise.reject(raised("own_post"));
    const existing = this.t.blocks.find((b) =>
      b.blocker_id === blockerId && b.blocked_id === author
    );
    if (existing) return Promise.resolve({ ...existing });
    const row: BlockRec = {
      id: this.nextId(),
      blocker_id: blockerId,
      blocked_id: author,
      label: post.anonymous ? "익명 주민" : this.handle(author) ?? "익명 주민",
      created_at: this.now().toISOString(),
    };
    this.t.blocks.push(row);
    return Promise.resolve({ ...row });
  }
  unblock(blockerId: string, blockId: string) {
    const before = this.t.blocks.length;
    this.t.blocks = this.t.blocks.filter((b) => !(b.id === blockId && b.blocker_id === blockerId));
    return Promise.resolve(this.t.blocks.length < before);
  }
  myBlocks(userId: string) {
    return Promise.resolve(
      this.t.blocks
        .filter((b) => b.blocker_id === userId && this.author(b.blocked_id) !== null)
        .sort((a, b) => b.created_at.localeCompare(a.created_at))
        .map((b) => ({
          id: b.id,
          label: b.label,
          created_at: b.created_at,
          author_tag: memoryAuthorTag(b.blocked_id, this.now()),
        })),
    );
  }
  blockedAuthors(userId: string) {
    return Promise.resolve(
      this.t.blocks.filter((b) => b.blocker_id === userId).map((b) => b.blocked_id),
    );
  }
  isStaff(userId: string) {
    return Promise.resolve(this.t.staff.includes(userId));
  }
  openReports(limit: number) {
    const groups = new Map<string, ReportRec[]>();
    for (const r of this.t.reports.filter((r) => r.status === "open")) {
      const key = `${r.target_type}:${r.target_id}`;
      groups.set(key, [...(groups.get(key) ?? []), r]);
    }
    const views = [...groups.values()].map((rs) => {
      rs.sort((a, b) => a.created_at.localeCompare(b.created_at));
      const first = rs[0];
      const post = this.posts(first.target_type).find((p) => p.id === first.target_id) as
        | (MessageRec | ReviewRec | ReplyRec)
        | undefined;
      const district = post && "district_id" in post
        ? post.district_id
        : this.t.threads.find((t) => post && "thread_id" in post && t.id === post.thread_id)
          ?.district_id ?? null;
      return {
        report_id: first.id,
        target_type: first.target_type,
        target_id: first.target_id,
        district_id: district,
        body: post?.body ?? null,
        hidden: Boolean(post?.hidden_at),
        reasons: [...new Set(rs.map((r) => r.reason))],
        reports: rs.length,
        first_at: first.created_at,
      };
    });
    views.sort((a, b) => a.first_at.localeCompare(b.first_at));
    return Promise.resolve(views.slice(0, limit));
  }
  resolveReport(staffId: string, reportId: string, action: ResolveAction, reason: string) {
    if (!this.t.staff.includes(staffId)) return Promise.reject(raised("not_staff"));
    const r = this.t.reports.find((x) => x.id === reportId);
    if (!r) return Promise.reject(raised("not_found"));
    if (action === "keep") this.hide(r.target_type, r.target_id, null);
    if (action === "hide") this.hide(r.target_type, r.target_id, "staff");
    if (action === "delete") {
      if (r.target_type === "review") {
        this.t.reviews = this.t.reviews.filter((x) => x.id !== r.target_id);
      } else if (r.target_type === "message") {
        this.t.messages = this.t.messages.filter((x) => x.id !== r.target_id);
      } else {
        this.t.replies = this.t.replies.filter((x) => x.id !== r.target_id);
      }
    }
    const status = action === "keep" ? "kept" : action === "hide" ? "hidden" : "deleted";
    const at = this.now().toISOString();
    for (const x of this.t.reports) {
      if (x.target_type === r.target_type && x.target_id === r.target_id && x.status === "open") {
        Object.assign(x, { status, resolved_by: staffId, resolved_at: at });
      }
    }
    this.t.staffActions.push({
      id: this.nextId(),
      staff_id: staffId,
      action,
      target_type: r.target_type,
      target_id: r.target_id,
      reason,
      at,
    });
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
  "score,body,anonymous,verified_resident,created_at,updated_at,hidden_at";
const MESSAGE_COLS =
  "id,district_id,author_id,body,anonymous,verified_resident,created_at,hidden_at";
const REPLY_COLS = "id,thread_id,author_id,body,anonymous,verified_resident,created_at,hidden_at";

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
  report(r: NewReport) {
    return this.db.rpc<boolean>("report_post", {
      p_reporter: r.reporterId,
      p_type: r.targetType,
      p_id: r.targetId,
      p_reason: r.reason,
      p_note: r.note,
    });
  }
  async block(blockerId: string, targetType: PostType, targetId: string) {
    const [row] = await this.db.rpc<BlockRec[]>("block_author", {
      p_blocker: blockerId,
      p_type: targetType,
      p_id: targetId,
    });
    return row;
  }
  async unblock(blockerId: string, blockId: string) {
    const query = { id: `eq.${blockId}`, blocker_id: `eq.${blockerId}` };
    const [row] = await this.db.select<{ id: string }>("blocks", { select: "id", ...query });
    if (!row) return false;
    await this.db.delete("blocks", query);
    return true;
  }
  myBlocks(userId: string) {
    return this.db.rpc<BlockView[]>("bff_my_blocks", { p_user: userId });
  }
  blockedAuthors(userId: string) {
    return this.db.rpc<string[]>("bff_blocked_authors", { p_user: userId });
  }
  async isStaff(userId: string) {
    const rows = await this.db.select<{ user_id: string }>("staff", {
      select: "user_id",
      user_id: `eq.${userId}`,
    });
    return rows.length > 0;
  }
  openReports(limit: number) {
    return this.db.rpc<StaffReportView[]>("staff_open_reports", { p_limit: limit });
  }
  async resolveReport(staffId: string, reportId: string, action: ResolveAction, reason: string) {
    await this.db.rpc("resolve_report", {
      p_staff: staffId,
      p_report: reportId,
      p_action: action,
      p_reason: reason,
    });
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
