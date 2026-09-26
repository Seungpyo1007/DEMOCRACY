// The BFF response envelope.
// 200 {"servedAt": ISO, "data": {...}}; non-2xx {"servedAt": ISO, "error": {code, message}}.

export type ErrorCode =
  | "not_found"
  | "no_match"
  | "not_curated"
  | "bad_request"
  | "upstream"
  | "internal";

const STATUS: Record<ErrorCode, number> = {
  not_found: 404,
  no_match: 404,
  not_curated: 404,
  bad_request: 400,
  upstream: 502,
  internal: 500,
};

export const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
};

export function ok(data: unknown, now: Date, cacheControl?: string): Response {
  const headers: Record<string, string> = {
    ...CORS_HEADERS,
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": cacheControl ?? "no-store",
  };
  return new Response(JSON.stringify({ servedAt: now.toISOString(), data }), {
    status: 200,
    headers,
  });
}

export function fail(code: ErrorCode, message: string, now: Date): Response {
  return new Response(
    JSON.stringify({ servedAt: now.toISOString(), error: { code, message } }),
    {
      status: STATUS[code],
      headers: {
        ...CORS_HEADERS,
        "Content-Type": "application/json; charset=utf-8",
        "Cache-Control": "no-store",
      },
    },
  );
}

export class ApiError extends Error {
  constructor(readonly code: ErrorCode, message: string) {
    super(message);
    this.name = "ApiError";
  }
}
