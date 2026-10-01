// Resident posts: 주민 평가 (reviews), 지역 채팅 (channel) and 정책 토론 (threads).
//
//   GET    /districts/{id}/reviews     {summary: {average, respondents, axes[]}, reviews[]}
//   POST   /districts/{id}/reviews     {scores: {소통, 공약이행, 지역발전, 도덕성}, body, anonymous}
//                                      → the board as it stands afterwards
//   DELETE /reviews/{id}               own only → {deleted: true}
//   GET    /districts/{id}/community   {messages[], threads[]}
//   POST   /districts/{id}/messages    {body, anonymous?} → {message}
//   DELETE /messages/{id}              own only → {deleted: true}
//
// Reading needs no account. A signed-in reader gets `mine` on their own posts, so those
// answers are no-store; anonymous reads are cached briefly.
//
// Writing needs a signed-in user with an unexpired residency for the same district
// (403 residency_required), a body free of the hate list (422 content_rejected, with the
// reason, never the matched text; possible false claims stay an app-side warning, see
// _shared/content_guard.ts) and at most five posts a minute (429 rate_limited). The SQL functions repeat the residency and rate checks under the insert.
// Bodies are never logged.
//
// Who wrote it is shown as the 활동명, or 「익명 주민」 when the author chose anonymous
// (the default), or 「탈퇴한 주민」 once the account is deleted. Threads are opened from
// the incumbent's sponsored bills (sync_bill_threads), never by a resident.

import type { AuthUser } from "../_shared/auth.ts";
import { bearerFrom } from "../_shared/auth.ts";
import {
  inspectContent,
  MESSAGE_BODY,
  normaliseBody,
  REVIEW_BODY,
} from "../_shared/content_guard.ts";
import { isDistrictId } from "../_shared/district_names.ts";
import { ApiError } from "../_shared/envelope.ts";
import { PostgrestError } from "../_shared/postgrest.ts";
import { type AccountContext, accountError, readBody, requireUser } from "./account.ts";
import {
  type CommunityStore,
  type MessageRec,
  REVIEW_AXES,
  type ReviewRec,
  type ReviewSummaryRec,
  type WithHandle,
} from "./community_store.ts";

/** Anonymous reads: short, so a new post shows within seconds for everyone. */
export const COMMUNITY_CACHE = "public, max-age=15";
const REVIEW_LIMIT = 50;
const MESSAGE_LIMIT = 50;
const THREAD_LIMIT = 30;

export const ANONYMOUS_AUTHOR = "익명 주민";
/** Shown in place of a post hidden by reports or staff; the body never leaves. */
export const HIDDEN_BODY = "신고로 가려진 글입니다.";
export const DELETED_AUTHOR = "탈퇴한 주민";
export const BILL_THREAD_ORIGIN = "법안 발의로 자동 생성";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

export interface CommunityContext extends AccountContext {
  community: CommunityStore;
}

export interface Answer {
  data: unknown;
  cache?: string;
}

function authorOf(
  row: { author_id: string | null; anonymous: boolean; author_handle: string | null },
) {
  if (row.author_id === null) return DELETED_AUTHOR;
  if (row.anonymous) return ANONYMOUS_AUTHOR;
  return row.author_handle ?? DELETED_AUTHOR;
}

const iso = (s: string) => new Date(s).toISOString();

function summaryView(s: ReviewSummaryRec) {
  // No reviews yet: respondents 0 and no axes. The app renders that as the empty board,
  // not as a zero rating.
  if (s.respondents === 0) return { average: 0, respondents: 0, axes: [] };
  return {
    average: s.average ?? 0,
    respondents: s.respondents,
    axes: REVIEW_AXES.map(([label, col]) => ({ label, score: s[col] ?? 0 })),
  };
}

function reviewView(r: WithHandle<ReviewRec>, me: string | null) {
  const hidden = Boolean(r.hidden_at);
  return {
    id: r.id,
    author: authorOf(r),
    score: Number(r.score),
    verifiedResident: r.verified_resident,
    body: hidden ? HIDDEN_BODY : r.body,
    hidden,
    mine: me !== null && r.author_id === me,
    createdAt: iso(r.updated_at),
  };
}

function messageView(m: WithHandle<MessageRec>, me: string | null) {
  const hidden = Boolean(m.hidden_at);
  return {
    id: m.id,
    author: authorOf(m),
    body: hidden ? HIDDEN_BODY : m.body,
    hidden,
    verifiedResident: m.verified_resident,
    mine: me !== null && m.author_id === me,
    createdAt: iso(m.created_at),
  };
}

/** Leaves out the posts of authors the reader blocked. */
function notBlocked<T extends { author_id: string | null }>(rows: T[], blocked: Set<string>) {
  return blocked.size === 0
    ? rows
    : rows.filter((r) => r.author_id === null || !blocked.has(r.author_id));
}

async function blockedBy(ctx: CommunityContext, me: string | null): Promise<Set<string>> {
  return new Set(me ? await ctx.community.blockedAuthors(me) : []);
}

/** Maps what the community SQL functions raise; the rest goes to accountError. */
export function communityError(error: unknown): unknown {
  if (error instanceof PostgrestError) {
    if (error.code === "P0001" && error.dbMessage === "residency_required") {
      return new ApiError("residency_required", "Verify residency in this district to post.");
    }
    if (error.code === "P0001" && error.dbMessage === "rate_limited") {
      return new ApiError("rate_limited", "Too many posts. Wait a minute and try again.");
    }
    if (error.code === "23503") return new ApiError("not_found", "No such district.");
    if (error.code === "23514") return new ApiError("bad_request", "The post is out of bounds.");
  }
  return accountError(error);
}

const codePoints = (s: string) => [...s].length;

function bodyFrom(raw: unknown, limits: { min: number; max: number }): string {
  if (typeof raw !== "string") throw new ApiError("bad_request", "body must be a string.");
  const body = normaliseBody(raw);
  const n = codePoints(body);
  if (n < limits.min || n > limits.max) {
    throw new ApiError("bad_request", `body must be ${limits.min}-${limits.max} characters.`);
  }
  const reason = inspectContent(body);
  if (reason) {
    throw new ApiError("content_rejected", "The post contains wording that cannot be posted.", {
      reason,
    });
  }
  return body;
}

function anonymousFrom(raw: unknown): boolean {
  // Anonymous unless the author explicitly chose to show their 활동명: the irreversible
  // choice is never the one made by omission.
  if (raw === undefined) return true;
  if (typeof raw !== "boolean") throw new ApiError("bad_request", "anonymous must be a boolean.");
  return raw;
}

function scoresFrom(raw: unknown) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    throw new ApiError("bad_request", "scores must be an object of the four axes.");
  }
  const scores = raw as Record<string, unknown>;
  const out = {} as Record<(typeof REVIEW_AXES)[number][1], number>;
  for (const [label, col] of REVIEW_AXES) {
    const v = scores[label];
    if (typeof v !== "number" || !Number.isInteger(v) || v < 1 || v > 5) {
      throw new ApiError("bad_request", `scores.${label} must be an integer 1-5.`);
    }
    out[col] = v;
  }
  if (Object.keys(scores).length !== REVIEW_AXES.length) {
    throw new ApiError("bad_request", "scores must hold exactly the four axes.");
  }
  return out;
}

/** The caller when a user token came with a read; reads never fail for a bad token. */
async function reader(ctx: CommunityContext, req: Request): Promise<AuthUser | null> {
  const bearer = bearerFrom(req);
  return bearer ? await ctx.auth.user(bearer) : null;
}

/**
 * Checked before any content rule, so an unverified resident hears about the gate, not
 * about their wording. The SQL function checks again under the insert.
 */
async function requireResidency(ctx: CommunityContext, userId: string, districtId: string) {
  const r = await ctx.accounts.residency(userId);
  if (!r || r.district_id !== districtId || Date.parse(r.expires_at) <= ctx.now().getTime()) {
    throw new ApiError("residency_required", "Verify residency in this district to post.");
  }
}

async function district(ctx: CommunityContext, id: string) {
  if (!isDistrictId(id)) throw new ApiError("bad_request", "Malformed district id.");
  if (!(await ctx.store.district(id))) throw new ApiError("not_found", "No such district.");
}

async function board(ctx: CommunityContext, id: string, me: string | null) {
  const [summary, reviews, blocked] = await Promise.all([
    ctx.community.reviewSummary(id),
    ctx.community.recentReviews(id, REVIEW_LIMIT),
    blockedBy(ctx, me),
  ]);
  return {
    summary: summaryView(summary),
    reviews: notBlocked(reviews, blocked).map((r) => reviewView(r, me)),
  };
}

/** Handles community paths; null when `path` is not one of them. */
export async function handleCommunity(
  ctx: CommunityContext,
  req: Request,
  path: string,
): Promise<Answer | null> {
  const inDistrict = /^\/districts\/([^/]+)\/(reviews|community|messages)$/.exec(path);
  const own = /^\/(reviews|messages)\/([^/]+)$/.exec(path);
  if (!inDistrict && !own) return null;

  try {
    if (own) {
      if (req.method !== "DELETE") {
        throw new ApiError("bad_request", `${req.method} is not supported here.`);
      }
      const [, kind, id] = own;
      if (!UUID.test(id)) throw new ApiError("bad_request", "Malformed id.");
      const user = await requireUser(ctx, req);
      const row = kind === "reviews"
        ? await ctx.community.review(id)
        : await ctx.community.message(id);
      if (!row) throw new ApiError("not_found", "No such post.");
      if (row.author_id !== user.id) {
        throw new ApiError("forbidden", "Only the author can delete this.");
      }
      await (kind === "reviews" ? ctx.community.deleteReview(id) : ctx.community.deleteMessage(id));
      return { data: { deleted: true } };
    }

    const [, id, what] = inDistrict!;
    const route = `${req.method} ${what}`;
    const allowed = ["GET reviews", "POST reviews", "GET community", "POST messages"];
    if (!allowed.includes(route)) {
      throw new ApiError("bad_request", `${req.method} is not supported here.`);
    }

    if (req.method === "GET") {
      await district(ctx, id);
      const me = await reader(ctx, req);
      const cache = me ? undefined : COMMUNITY_CACHE;
      if (what === "reviews") return { data: await board(ctx, id, me?.id ?? null), cache };
      const [messages, threads, blocked] = await Promise.all([
        ctx.community.recentMessages(id, MESSAGE_LIMIT),
        ctx.community.threads(id, THREAD_LIMIT),
        blockedBy(ctx, me?.id ?? null),
      ]);
      return {
        data: {
          messages: notBlocked(messages, blocked).map((m) => messageView(m, me?.id ?? null)),
          threads: threads.map((t) => ({
            id: t.id,
            title: t.title,
            origin: BILL_THREAD_ORIGIN,
            replies: t.replies,
            sourceUrl: t.source_url,
            openedAt: iso(t.opened_at),
          })),
        },
        cache,
      };
    }

    if (!isDistrictId(id)) throw new ApiError("bad_request", "Malformed district id.");
    const user = await requireUser(ctx, req);
    const body = await readBody(req);
    await requireResidency(ctx, user.id, id);

    if (what === "reviews") {
      const scores = scoresFrom(body.scores);
      const text = bodyFrom(body.body, REVIEW_BODY);
      await ctx.community.postReview({
        userId: user.id,
        districtId: id,
        ...scores,
        body: text,
        anonymous: anonymousFrom(body.anonymous),
      });
      return { data: await board(ctx, id, user.id) };
    }

    const text = bodyFrom(body.body, MESSAGE_BODY);
    const row = await ctx.community.postMessage({
      userId: user.id,
      districtId: id,
      body: text,
      anonymous: anonymousFrom(body.anonymous),
    });
    const handle = (await ctx.accounts.profile(user.id))?.handle ?? null;
    return { data: { message: messageView({ ...row, author_handle: handle }, user.id) } };
  } catch (error) {
    throw communityError(error);
  }
}
