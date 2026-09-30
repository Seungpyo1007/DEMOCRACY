// An offline stand-in for Supabase Auth (GoTrue): GET /auth/v1/user answers for the
// tokens it was given and 401s everything else; DELETE /auth/v1/admin/users/{id}
// needs the service key and is recorded. Handlers get it through the real
// createAuth, so tests exercise _shared/auth.ts as deployed.

import { type Auth, createAuth } from "../supabase/functions/_shared/auth.ts";
import type { FetchLike } from "../supabase/functions/_shared/http.ts";
import { MemoryAccountStore } from "../supabase/functions/bff/account_store.ts";
import { MemoryCommunityStore } from "../supabase/functions/bff/community_store.ts";

export const SUPABASE_URL = "https://ref.supabase.co";
export const ANON_KEY = "test-anon-jwt";
export const SERVICE_KEY = "test-service-role-jwt";

export interface FakeUser {
  id: string;
  email?: string | null;
  provider?: string;
  isAnonymous?: boolean;
}

export interface FakeGotrue {
  auth: Auth;
  /** Every URL reached, for asserting what went to GoTrue. */
  requests: string[];
  /** Ids the admin API deleted. */
  deleted: string[];
}

export function fakeGotrue(tokens: Record<string, FakeUser> = {}): FakeGotrue {
  const requests: string[] = [];
  const deleted: string[] = [];
  const fetch: FetchLike = (input, init) => {
    const url = new URL(
      typeof input === "string" ? input : input instanceof URL ? input.href : input.url,
    );
    requests.push(url.toString());
    const headers = new Headers(init?.headers);
    const bearer = (headers.get("Authorization") ?? "").replace(/^Bearer /, "");
    if (url.pathname === "/auth/v1/user" && (init?.method ?? "GET") === "GET") {
      const u = tokens[bearer];
      if (!u || headers.get("apikey") !== ANON_KEY) {
        return Promise.resolve(Response.json({ msg: "invalid JWT" }, { status: 401 }));
      }
      return Promise.resolve(Response.json({
        id: u.id,
        email: u.email ?? null,
        is_anonymous: u.isAnonymous ?? false,
        app_metadata: { provider: u.provider ?? "kakao" },
      }));
    }
    const admin = /^\/auth\/v1\/admin\/users\/([^/]+)$/.exec(url.pathname);
    if (admin && init?.method === "DELETE") {
      if (bearer !== SERVICE_KEY) return Promise.resolve(new Response(null, { status: 403 }));
      deleted.push(decodeURIComponent(admin[1]));
      return Promise.resolve(Response.json({}));
    }
    return Promise.resolve(new Response("not found", { status: 404 }));
  };
  return { auth: createAuth(fetch, SUPABASE_URL, ANON_KEY, SERVICE_KEY), requests, deleted };
}

/** A deterministic byte source (xorshift32) standing in for crypto.getRandomValues. */
export function seededBytes(seed: number): (n: number) => Uint8Array {
  let x = seed >>> 0 || 1;
  return (n) => {
    const out = new Uint8Array(n);
    for (let i = 0; i < n; i++) {
      x ^= x << 13;
      x >>>= 0;
      x ^= x >>> 17;
      x ^= x << 5;
      x >>>= 0;
      out[i] = x & 0xff;
    }
    return out;
  };
}

/** Account dependencies for tests that only exercise the public routes. */
export function signedOut() {
  const accounts = new MemoryAccountStore();
  return {
    accounts,
    community: new MemoryCommunityStore(accounts.t),
    auth: fakeGotrue().auth,
  };
}
