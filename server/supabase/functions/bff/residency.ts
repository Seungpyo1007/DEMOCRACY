// Resident verification (주민 인증). Signed-in users with a profile only.
//
//   POST   /residency/verify   {roadAddress} or {lat, lng}
//                              → {token, districtId, displayName, method, verifiedAt, expiresAt}
//   DELETE /residency          → {deleted: true}
//
// The server derives the district itself from juso (address) or Kakao (coordinates) and
// the 별표2 mapping; a district id from the client is never accepted. An address that is
// ambiguous or unmapped is no_match rather than a guess.
//
// The address and coordinates are used for that one lookup and dropped: they are not
// stored, not logged and not echoed back. What is stored is the district, the method and
// the SHA-256 of a fresh 32-byte token; the token itself goes only to the device.
//
// This is a self-declared address, not proof of residence. `method` names that so a
// stronger check can replace it later; the app must not call it 실거주 증명.

import { ApiError } from "../_shared/envelope.ts";
import { lookupHdong, searchJuso } from "../_shared/geo.ts";
import type { FetchLike } from "../_shared/http.ts";
import {
  type AccountContext,
  accountError,
  readBody,
  requireProfile,
  requireUser,
} from "./account.ts";
import { districtForHdong, districtForRoadAddress, type DistrictRef } from "./mapping.ts";

export const RESIDENCY_METHOD = "address_self_declared";
/** How long a verification lasts before the user confirms their address again. */
export const RESIDENCY_TTL_DAYS = 180;
const TOKEN_BYTES = 32;

export interface ResidencyContext extends AccountContext {
  fetch: FetchLike;
  jusoKey: string;
  kakaoKey: string;
}

type Place = { roadAddress: string } | { lat: number; lng: number };

function base64url(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export async function sha256Hex(text: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

const inRange = (v: unknown, min: number, max: number): v is number =>
  typeof v === "number" && Number.isFinite(v) && v >= min && v <= max;

function placeFrom(body: Record<string, unknown>): Place {
  const hasAddress = body.roadAddress !== undefined;
  const hasCoords = body.lat !== undefined || body.lng !== undefined;
  if (hasAddress === hasCoords) {
    throw new ApiError("bad_request", "Send either roadAddress or lat and lng.");
  }
  if (hasAddress) {
    const a = typeof body.roadAddress === "string" ? body.roadAddress.trim() : "";
    if (a.length < 5 || a.length > 200) {
      throw new ApiError("bad_request", "roadAddress must be 5-200 characters.");
    }
    return { roadAddress: a };
  }
  if (!inRange(body.lat, 33, 39) || !inRange(body.lng, 124, 132)) {
    throw new ApiError("bad_request", "lat/lng must be coordinates within Korea.");
  }
  return { lat: body.lat, lng: body.lng };
}

async function districtFor(ctx: ResidencyContext, place: Place): Promise<DistrictRef | null> {
  if ("roadAddress" in place) {
    const found = await searchJuso(ctx.fetch, ctx.jusoKey, place.roadAddress);
    return districtForRoadAddress(ctx.store, found, place.roadAddress);
  }
  const hdong = await lookupHdong(ctx.fetch, ctx.kakaoKey, place.lat, place.lng);
  return hdong ? districtForHdong(ctx.store, hdong) : null;
}

/** Handles residency paths; null when `path` is not one of them. */
export async function handleResidency(
  ctx: ResidencyContext,
  req: Request,
  path: string,
): Promise<unknown | null> {
  if (path !== "/residency" && path !== "/residency/verify") return null;
  const route = `${req.method} ${path}`;
  if (route !== "POST /residency/verify" && route !== "DELETE /residency") {
    throw new ApiError("bad_request", `${req.method} is not supported here.`);
  }
  const user = await requireUser(ctx, req);

  if (route === "DELETE /residency") {
    await ctx.accounts.deleteResidency(user.id);
    return { deleted: true };
  }

  // Parse first so a malformed body is a 400 even before consent; then check the profile
  // before spending an upstream lookup on someone who cannot be verified.
  const place = placeFrom(await readBody(req));
  await requireProfile(ctx, user.id);
  const district = await districtFor(ctx, place);
  if (!district) throw new ApiError("no_match", "This address does not map to one district.");

  const token = base64url(ctx.randomBytes(TOKEN_BYTES));
  const now = ctx.now();
  const expires = new Date(now.getTime() + RESIDENCY_TTL_DAYS * 86_400_000);
  try {
    const row = await ctx.accounts.issueResidency({
      userId: user.id,
      districtId: district.id,
      method: RESIDENCY_METHOD,
      tokenHash: await sha256Hex(token),
      verifiedAt: now.toISOString(),
      expiresAt: expires.toISOString(),
    });
    return {
      token,
      districtId: row.district_id,
      displayName: district.displayName,
      method: row.method,
      verifiedAt: new Date(row.verified_at).toISOString(),
      expiresAt: new Date(row.expires_at).toISOString(),
    };
  } catch (error) {
    throw accountError(error);
  }
}
