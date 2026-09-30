// Supabase Auth (GoTrue) client for the BFF: who is calling, and account deletion.
//
// The user's JWT is checked by asking GoTrue (GET /auth/v1/user) rather than by
// verifying the signature locally: that also catches a session revoked by sign-out or
// deletion, and needs no JWT secret in the function. The anon key is a valid JWT too,
// so a request that carries only it is treated as signed out.

import type { FetchLike } from "./http.ts";
import { UpstreamError } from "./http.ts";

export interface AuthUser {
  id: string;
  email: string | null;
  /** The sign-in provider: apple, kakao, google or email. */
  provider: string | null;
}

export interface Auth {
  /** The user behind a bearer token, or null when there is none or it is not a user's. */
  user(bearer: string | null): Promise<AuthUser | null>;
  /** Deletes the auth user; profile rows go with it (on delete cascade). */
  deleteUser(id: string): Promise<void>;
}

/** The token from an `Authorization: Bearer <token>` header, or null. */
export function bearerFrom(req: Request): string | null {
  const header = req.headers.get("Authorization") ?? "";
  const m = /^Bearer\s+(\S+)$/i.exec(header.trim());
  return m ? m[1] : null;
}

function authBase(supabaseUrl: string): string {
  return `${supabaseUrl.replace(/\/$/, "")}/auth/v1`;
}

/** A network failure reaching GoTrue is an outage (502), not a signed-out caller. */
async function reach(fetchFn: FetchLike, url: string, init: RequestInit): Promise<Response> {
  try {
    return await fetchFn(url, init);
  } catch (error) {
    throw new UpstreamError(`auth: ${(error as Error)?.name ?? "network"}`);
  }
}

export async function getUser(
  fetchFn: FetchLike,
  supabaseUrl: string,
  anonKey: string,
  bearer: string | null,
): Promise<AuthUser | null> {
  if (!bearer || bearer === anonKey) return null;
  const res = await reach(fetchFn, `${authBase(supabaseUrl)}/user`, {
    method: "GET",
    headers: { apikey: anonKey, Authorization: `Bearer ${bearer}` },
  });
  if (res.status !== 200) {
    // Expired, revoked or not a user token. Not an outage: GoTrue answers 401/403.
    await res.body?.cancel();
    return null;
  }
  const json = (await res.json()) as Record<string, unknown>;
  const id = typeof json.id === "string" ? json.id : null;
  // Anonymous sign-ins are not accounts here.
  if (!id || json.is_anonymous === true) return null;
  const meta = json.app_metadata as Record<string, unknown> | undefined;
  return {
    id,
    email: typeof json.email === "string" && json.email !== "" ? json.email : null,
    provider: typeof meta?.provider === "string" ? meta.provider : null,
  };
}

export async function deleteAuthUser(
  fetchFn: FetchLike,
  supabaseUrl: string,
  serviceRoleKey: string,
  id: string,
): Promise<void> {
  const res = await reach(
    fetchFn,
    `${authBase(supabaseUrl)}/admin/users/${encodeURIComponent(id)}`,
    {
      method: "DELETE",
      headers: { apikey: serviceRoleKey, Authorization: `Bearer ${serviceRoleKey}` },
    },
  );
  await res.body?.cancel();
  // 404: already gone (a retried delete, or the orphan purge got there first).
  if (!res.ok && res.status !== 404) {
    throw new UpstreamError(`auth admin delete answered ${res.status}`, res.status);
  }
}

export function createAuth(
  fetchFn: FetchLike,
  supabaseUrl: string,
  anonKey: string,
  serviceRoleKey: string,
): Auth {
  return {
    user: (bearer) => getUser(fetchFn, supabaseUrl, anonKey, bearer),
    deleteUser: (id) => deleteAuthUser(fetchFn, supabaseUrl, serviceRoleKey, id),
  };
}
