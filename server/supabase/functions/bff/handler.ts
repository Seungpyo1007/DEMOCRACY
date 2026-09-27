// BFF router. Paths (after /functions/v1/bff):
//   GET /districts/{id}/profile | /history | /pledges | /results | /direction
//   GET /address/search?q=
//   GET /location/district?lat=&lng=
//   /me/... (account routes, signed-in only; see account.ts)
//   POST /residency/verify, DELETE /residency (signed-in; see residency.ts)
//   GET|POST /districts/{id}/reviews, GET /districts/{id}/community,
//   POST /districts/{id}/messages, DELETE /reviews/{id} | /messages/{id} (see community.ts)
//
// The public routes are GET only and need no account. Signed-in routes are no-store.
// Privacy: the address query and coordinates are never logged or stored, nor are post bodies.

import type { Auth } from "../_shared/auth.ts";
import { ApiError, CORS_HEADERS, fail, ok } from "../_shared/envelope.ts";
import { isDistrictId } from "../_shared/district_names.ts";
import { lookupPlace, searchJuso } from "../_shared/geo.ts";
import type { FetchLike } from "../_shared/http.ts";
import { UpstreamError } from "../_shared/http.ts";
import { findKeyedUrls } from "../_shared/provenance.ts";
import { type AccountContext, handleAccount } from "./account.ts";
import type { AccountStore } from "./account_store.ts";
import { type CommunityContext, handleCommunity } from "./community.ts";
import type { CommunityStore } from "./community_store.ts";
import { buildHistory, buildPledges, buildProfile } from "./builders.ts";
import { buildDirection } from "./direction.ts";
import { districtForPlace, suggestionsFor } from "./mapping.ts";
import { buildResults } from "./results.ts";
import { handleResidency, type ResidencyContext } from "./residency.ts";
import type { ReadStore } from "./store.ts";

export interface BffDeps {
  store: ReadStore;
  fetch: FetchLike;
  jusoKey: string;
  vworldKey: string;
  /** The service URL the V-World key was issued for, when the key asks for it. */
  vworldDomain?: string;
  accounts: AccountStore;
  community: CommunityStore;
  auth: Auth;
  /** Source of randomness for 활동명 draws and tokens; crypto.getRandomValues by default. */
  randomBytes?: (n: number) => Uint8Array;
  now?: () => Date;
  /** Error reporter; receives no request data. */
  logError?: (message: string) => void;
}

const PROFILE_CACHE = "public, max-age=300";

function routePath(url: URL): string {
  // Supabase passes "/bff/..." (the function name is the first segment).
  const path = url.pathname.replace(/\/+$/, "");
  const idx = path.indexOf("/bff");
  return idx >= 0 ? path.slice(idx + 4) || "/" : path;
}

function parseCoord(raw: string | null, min: number, max: number): number | null {
  if (raw === null || raw.trim() === "") return null;
  const n = Number(raw);
  return Number.isFinite(n) && n >= min && n <= max ? n : null;
}

export function createHandler(deps: BffDeps): (req: Request) => Promise<Response> {
  const now = deps.now ?? (() => new Date());
  const account: AccountContext & CommunityContext = {
    store: deps.store,
    accounts: deps.accounts,
    community: deps.community,
    auth: deps.auth,
    randomBytes: deps.randomBytes ?? ((n) => crypto.getRandomValues(new Uint8Array(n))),
    now,
  };
  const residency: ResidencyContext = {
    ...account,
    fetch: deps.fetch,
    jusoKey: deps.jusoKey,
    vworldKey: deps.vworldKey,
    vworldDomain: deps.vworldDomain,
  };

  const respond = (data: unknown, cache?: string) => {
    // Last line of defence: a credential-bearing URL must never leave.
    if (findKeyedUrls(data).length > 0) {
      throw new ApiError("internal", "Refusing to serve a keyed URL.");
    }
    return ok(data, now(), cache);
  };

  return async (req: Request): Promise<Response> => {
    if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS_HEADERS });

    const url = new URL(req.url);
    const path = routePath(url);
    try {
      const mine = await handleAccount(account, req, url, path);
      if (mine !== null) return respond(mine);
      const verified = await handleResidency(residency, req, path);
      if (verified !== null) return respond(verified);
      const posted = await handleCommunity(account, req, path);
      if (posted !== null) return respond(posted.data, posted.cache);
      if (req.method !== "GET") throw new ApiError("bad_request", "Only GET is supported.");

      const district = /^\/districts\/([^/]+)\/(profile|history|pledges|results|direction)$/.exec(
        path,
      );
      if (district) {
        const [, id, what] = district;
        if (!isDistrictId(id)) throw new ApiError("bad_request", "Malformed district id.");
        if (what === "profile") {
          return respond(await buildProfile(deps.store, id, now()), PROFILE_CACHE);
        }
        if (what === "history") return respond(await buildHistory(deps.store, id), PROFILE_CACHE);
        if (what === "direction") {
          return respond(await buildDirection(deps.store, id), PROFILE_CACHE);
        }
        // A final count, so the public cache is safe. A live count will need a
        // short max-age and must never be cached across pollsClose.
        if (what === "results") return respond(await buildResults(deps.store, id), PROFILE_CACHE);
        return respond(await buildPledges(deps.store, id), PROFILE_CACHE);
      }

      if (path === "/address/search") {
        const q = (url.searchParams.get("q") ?? "").trim();
        if (q.length < 2 || q.length > 80) {
          throw new ApiError("bad_request", "q must be 2-80 characters.");
        }
        const found = await searchJuso(deps.fetch, deps.jusoKey, q);
        return respond({ suggestions: await suggestionsFor(deps.store, found) });
      }

      if (path === "/location/district") {
        const lat = parseCoord(url.searchParams.get("lat"), 33, 39);
        const lng = parseCoord(url.searchParams.get("lng"), 124, 132);
        if (lat === null || lng === null) {
          throw new ApiError("bad_request", "lat/lng must be coordinates within Korea.");
        }
        const place = await lookupPlace(deps.fetch, deps.vworldKey, lat, lng, deps.vworldDomain);
        const d = place ? await districtForPlace(deps.store, place) : null;
        if (!d) throw new ApiError("no_match", "No district matches this location.");
        return respond({ district: d });
      }

      throw new ApiError("not_found", "No such route.");
    } catch (error) {
      if (error instanceof ApiError) return fail(error.code, error.message, now(), error.extra);
      if (error instanceof UpstreamError) {
        // Not error.message: it can carry the upstream URL, i.e. the query.
        deps.logError?.(`upstream ${path}: status ${error.status ?? "network"}`);
        return fail("upstream", "An upstream data service failed.", now());
      }
      deps.logError?.(`internal: ${(error as Error)?.name ?? "error"}`);
      return fail("internal", "Internal error.", now());
    }
  };
}
