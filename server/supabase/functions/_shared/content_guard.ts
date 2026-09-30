// Server-side content rule for resident posts, ported from the app's ContentGuard
// (app/lib/src/features/reviews/domain/review_draft.dart). The app still runs the same
// check before sending, as UX; this is the one that holds, because a check that lives in
// the app can be edited out of it.
//
// Only the hate list is enforced. The app's second list (possibly false claims, e.g.
// "확실히 조작") stays a client-side warning the author may send past: a keyword cannot
// tell a false claim from a true one or a quotation, and refusing it here would be the
// app deciding what residents may say about a politician. That is a product and legal
// call that has not been made.
//
// The hate list must match the app's, or the app would let through what the server then
// refuses. A real classifier replaces both. Bodies are never logged: callers get a reason
// code, not the matched text.

export type ContentReason = "hate";

const HATE_TERMS = ["멍청", "쓰레기 같은", "꺼져"];

/** Why [text] may not be posted, or null. Spaces are ignored, as in the app. */
export function inspectContent(text: string): ContentReason | null {
  const normalised = text.replaceAll(" ", "");
  return HATE_TERMS.some((t) => normalised.includes(t.replaceAll(" ", ""))) ? "hate" : null;
}

/** Collapses runs of blank lines and trims; what is stored is what was checked. */
export function normaliseBody(raw: string): string {
  return raw.replace(/\r\n?/g, "\n").replace(/\n{3,}/g, "\n\n").trim();
}

export const REVIEW_BODY = { min: 10, max: 500 } as const;
export const MESSAGE_BODY = { min: 1, max: 300 } as const;
