// Reports (신고), blocks (차단) and the staff side that resolves reports.
//
//   POST   /reports                  {targetType, targetId, reason, note?} → {reported, hidden}
//   GET    /blocks                   {blocks[]: {id, label, createdAt, authorTag}}
//   POST   /blocks                   {targetType, targetId} → {block}
//   DELETE /blocks/{id}              → {deleted: true}
//   GET    /staff/reports            {reports[]}                staff only
//   POST   /staff/reports/{id}/resolve  {action, reason}        staff only
//
// All signed-in and no-store. A report needs an account but no residency: a reader of
// any district can report what they read. Blocking names a post, never a person; the
// reader learns only how the author showed (활동명 or 익명 주민) and today's author tag,
// which the live channel carries so the app can drop a blocked author's new messages.
// What happens to a reported post (hidden on one privacy report or three readers, never
// on false-claim reports alone) lives in report_post(); see the moderation migration.

import { ApiError } from "../_shared/envelope.ts";
import { PostgrestError } from "../_shared/postgrest.ts";
import { readBody, requireUser } from "./account.ts";
import { type Answer, type CommunityContext, communityError } from "./community.ts";
import {
  type BlockView,
  POST_TYPES,
  type PostType,
  REPORT_REASONS,
  type ReportReason,
  type ResolveAction,
} from "./community_store.ts";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const STAFF_LIST_LIMIT = 100;
const NOTE_MAX = 200;
const ACTIONS: readonly ResolveAction[] = ["keep", "hide", "delete"];

/** Maps what the moderation SQL functions raise; the rest goes to communityError. */
export function moderationError(error: unknown): unknown {
  if (error instanceof PostgrestError && error.code === "P0001") {
    switch (error.dbMessage) {
      case "not_found":
        return new ApiError("not_found", "No such post.");
      case "own_post":
        return new ApiError("bad_request", "You cannot report or block your own post.");
      case "no_author":
        return new ApiError("bad_request", "The author's account no longer exists.");
      case "already_reported":
        return new ApiError("conflict", "You already reported this post.");
      case "rate_limited":
        return new ApiError("rate_limited", "Too many reports today. Try again tomorrow.");
      case "not_staff":
        return new ApiError("forbidden", "Staff only.");
    }
  }
  return communityError(error);
}

function target(body: Record<string, unknown>): { type: PostType; id: string } {
  const type = body.targetType;
  const id = body.targetId;
  if (typeof type !== "string" || !POST_TYPES.includes(type as PostType)) {
    throw new ApiError("bad_request", "targetType must be review, message or reply.");
  }
  if (typeof id !== "string" || !UUID.test(id)) {
    throw new ApiError("bad_request", "targetId must be a post id.");
  }
  return { type: type as PostType, id };
}

function noteFrom(raw: unknown): string | null {
  if (raw === undefined || raw === null) return null;
  if (typeof raw !== "string") throw new ApiError("bad_request", "note must be a string.");
  const note = raw.trim();
  if ([...note].length > NOTE_MAX) {
    throw new ApiError("bad_request", `note must be at most ${NOTE_MAX} characters.`);
  }
  return note === "" ? null : note;
}

const iso = (s: string) => new Date(s).toISOString();

function blockView(b: BlockView) {
  return { id: b.id, label: b.label, createdAt: iso(b.created_at), authorTag: b.author_tag };
}

async function requireStaff(ctx: CommunityContext, req: Request) {
  const user = await requireUser(ctx, req);
  if (!(await ctx.community.isStaff(user.id))) throw new ApiError("forbidden", "Staff only.");
  return user;
}

/** Handles moderation paths; null when `path` is not one of them. */
export async function handleModeration(
  ctx: CommunityContext,
  req: Request,
  path: string,
): Promise<Answer | null> {
  const blockId = /^\/blocks\/([^/]+)$/.exec(path);
  const resolve = /^\/staff\/reports\/([^/]+)\/resolve$/.exec(path);
  const known = path === "/reports" || path === "/blocks" || path === "/staff/reports" ||
    blockId !== null || resolve !== null;
  if (!known) return null;

  try {
    const route = `${req.method} ${
      blockId ? "/blocks/{id}" : resolve ? "/staff/reports/{id}/resolve" : path
    }`;
    switch (route) {
      case "POST /reports": {
        const user = await requireUser(ctx, req);
        const body = await readBody(req);
        const { type, id } = target(body);
        const reason = body.reason;
        if (typeof reason !== "string" || !REPORT_REASONS.includes(reason as ReportReason)) {
          throw new ApiError("bad_request", "reason must be hate, privacy, false, spam or other.");
        }
        const hidden = await ctx.community.report({
          reporterId: user.id,
          targetType: type,
          targetId: id,
          reason: reason as ReportReason,
          note: noteFrom(body.note),
        });
        return { data: { reported: true, hidden } };
      }
      case "GET /blocks": {
        const user = await requireUser(ctx, req);
        return { data: { blocks: (await ctx.community.myBlocks(user.id)).map(blockView) } };
      }
      case "POST /blocks": {
        const user = await requireUser(ctx, req);
        const { type, id } = target(await readBody(req));
        const row = await ctx.community.block(user.id, type, id);
        const view = (await ctx.community.myBlocks(user.id)).find((b) => b.id === row.id);
        return { data: { block: view ? blockView(view) : null } };
      }
      case "DELETE /blocks/{id}": {
        const user = await requireUser(ctx, req);
        const id = blockId![1];
        if (!UUID.test(id)) throw new ApiError("bad_request", "Malformed id.");
        if (!(await ctx.community.unblock(user.id, id))) {
          throw new ApiError("not_found", "No such block.");
        }
        return { data: { deleted: true } };
      }
      case "GET /staff/reports": {
        await requireStaff(ctx, req);
        const rows = await ctx.community.openReports(STAFF_LIST_LIMIT);
        return {
          data: {
            reports: rows.map((r) => ({
              reportId: r.report_id,
              targetType: r.target_type,
              targetId: r.target_id,
              districtId: r.district_id,
              body: r.body,
              hidden: r.hidden,
              reasons: r.reasons,
              reports: r.reports,
              firstAt: iso(r.first_at),
            })),
          },
        };
      }
      case "POST /staff/reports/{id}/resolve": {
        const staff = await requireStaff(ctx, req);
        const id = resolve![1];
        if (!UUID.test(id)) throw new ApiError("bad_request", "Malformed id.");
        const body = await readBody(req);
        const action = body.action;
        if (typeof action !== "string" || !ACTIONS.includes(action as ResolveAction)) {
          throw new ApiError("bad_request", "action must be keep, hide or delete.");
        }
        const reason = typeof body.reason === "string" ? body.reason.trim() : "";
        if (reason === "" || [...reason].length > 300) {
          throw new ApiError("bad_request", "reason is required (at most 300 characters).");
        }
        await ctx.community.resolveReport(staff.id, id, action as ResolveAction, reason);
        return { data: { resolved: true } };
      }
      default:
        throw new ApiError("bad_request", `${req.method} is not supported here.`);
    }
  } catch (error) {
    throw moderationError(error);
  }
}
