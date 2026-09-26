// Shared plumbing for ingest functions: auth, raw storage, JSON replies.

import type { Postgrest } from "./postgrest.ts";

/** Constant-time comparison of the x-ingest-secret header. */
export function authorizeIngest(req: Request, secret: string): boolean {
  const given = req.headers.get("x-ingest-secret") ?? "";
  if (secret === "" || given.length !== secret.length) return false;
  let diff = 0;
  for (let i = 0; i < secret.length; i++) diff |= secret.charCodeAt(i) ^ given.charCodeAt(i);
  return diff === 0;
}

/** Canonical, credential-free string for request params (raw_* dedupe key). */
export function requestKey(params: Record<string, string>): string {
  return Object.keys(params)
    .filter((k) => !/^(KEY|ServiceKey|confmKey)$/i.test(k))
    .sort()
    .map((k) => `${k}=${params[k]}`)
    .join("&");
}

export interface RawWrite {
  table: "raw_assembly" | "raw_nec";
  service: string;
  params: Record<string, string>;
  page: number;
  payload: unknown;
  sourceUrl: string;
  fetchedAt: string;
}

export async function writeRaw(db: Postgrest, w: RawWrite): Promise<void> {
  await db.upsert(w.table, [{
    service: w.service,
    request_key: requestKey(w.params),
    page: w.page,
    payload: w.payload,
    source_url: w.sourceUrl,
    fetched_at: w.fetchedAt,
  }], "service,request_key,page");
}

export function jsonReply(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8" },
  });
}

/** Wraps an ingest runner with the secret check and uniform replies. */
export function ingestHandler(
  secret: string,
  run: (mode: string, url: URL) => Promise<unknown>,
): (req: Request) => Promise<Response> {
  return async (req) => {
    if (req.method !== "POST") return jsonReply(405, { error: "POST only" });
    if (!authorizeIngest(req, secret)) return jsonReply(401, { error: "unauthorized" });
    const url = new URL(req.url);
    const mode = url.searchParams.get("mode") ?? "";
    try {
      const summary = await run(mode, url);
      return jsonReply(200, { mode, ok: true, summary });
    } catch (error) {
      const message = error instanceof Error ? error.message : "error";
      console.error(`ingest ${mode} failed: ${message}`);
      return jsonReply(error instanceof RangeError ? 400 : 502, {
        mode,
        ok: false,
        error: message,
      });
    }
  };
}
