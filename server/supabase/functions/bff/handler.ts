// BFF router. Paths (after /functions/v1/bff):
//   GET /districts/{id}/profile | /history | /pledges
//   GET /address/search?q=
//   GET /location/district?lat=&lng=
//
// Privacy: the address query and coordinates are never logged or stored.

import { ApiError, CORS_HEADERS, fail, ok } from "../_shared/envelope.ts";
import { isDistrictId } from "../_shared/district_names.ts";
import { lookupHdong, searchJuso } from "../_shared/geo.ts";
import type { FetchLike } from "../_shared/http.ts";
import { UpstreamError } from "../_shared/http.ts";
import { findKeyedUrls } from "../_shared/provenance.ts";
import { buildHistory, buildPledges, buildProfile } from "./builders.ts";
import { districtForHdong, suggestionsFor } from "./mapping.ts";
import type { ReadStore } from "./store.ts";

export interface BffDeps {
  store: ReadStore;
  fetch: FetchLike;
  jusoKey: string;
  kakaoKey: string;
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

  const respond = (data: unknown, cache?: string) => {
    // Last line of defence: a credential-bearing URL must never leave.
    if (findKeyedUrls(data).length > 0) {
      throw new ApiError("internal", "Refusing to serve a keyed URL.");
    }
    return ok(data, now(), cache);
  };

  return async (req: Request): Promise<Response> => {
    if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS_HEADERS });
    if (req.method !== "GET") return fail("bad_request", "Only GET is supported.", now());

    const url = new URL(req.url);
    const path = routePath(url);
    try {
      const district = /^\/districts\/([^/]+)\/(profile|history|pledges)$/.exec(path);
      if (district) {
        const [, id, what] = district;
        if (!isDistrictId(id)) throw new ApiError("bad_request", "Malformed district id.");
        if (what === "profile") {
          return respond(await buildProfile(deps.store, id, now()), PROFILE_CACHE);
        }
        if (what === "history") return respond(await buildHistory(deps.store, id), PROFILE_CACHE);
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
        const hdong = await lookupHdong(deps.fetch, deps.kakaoKey, lat, lng);
        const d = hdong ? await districtForHdong(deps.store, hdong) : null;
        if (!d) throw new ApiError("no_match", "No district matches this location.");
        return respond({ district: d });
      }

      throw new ApiError("not_found", "No such route.");
    } catch (error) {
      if (error instanceof ApiError) return fail(error.code, error.message, now());
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
