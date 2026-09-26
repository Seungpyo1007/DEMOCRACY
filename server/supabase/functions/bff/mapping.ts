// Address / coordinate → 22대 국회의원 선거구.
//
// There is no API for this. district_areas (from 공직선거법 [별표2]) maps
// 행정동 → 선거구, with a 5-digit 시군구 row when the whole 시군구 is one
// 선거구. juso gives a 법정동 code (admCd) and, with addInfoYn=Y, the 행정동
// name (hemdNm). A 법정동 can straddle 행정동s — and 선거구s (e.g. 마포구
// 노고산동 is split between 대흥동/갑 and 서교동/을) — so the bridge table is
// only trusted when every 행정동 it yields lands in the same 선거구.

import { CURRENT_DISTRICT_SG_ID, normalizeHdongName } from "../_shared/district_names.ts";
import type { JusoAddress } from "../_shared/geo.ts";
import type { AreaRec, BridgeRec, DistrictRec, ReadStore } from "./store.ts";

export interface DistrictRef {
  id: string;
  displayName: string;
}

/** The sgg_code for one 시군구's worth of area rows, given what we know of a place. */
export function resolveSggCode(
  local: AreaRec[],
  sigungu: string,
  hint: { hdongCode?: string | null; hdongName?: string | null; bjdCode?: string | null },
  bridge: BridgeRec[] = [],
): string | null {
  if (local.length === 0) return null;
  const whole = local.find((a) => a.hdong_code === sigungu);
  const codes = new Set(local.map((a) => a.sgg_code));
  if (whole && codes.size === 1) return whole.sgg_code;

  const perHdong = local.filter((a) => a.hdong_code.length === 10);
  if (hint.hdongCode) {
    const exact = perHdong.find((a) => a.hdong_code === hint.hdongCode);
    if (exact) return exact.sgg_code;
  }
  if (hint.hdongName) {
    const wanted = normalizeHdongName(hint.hdongName);
    const byName = perHdong.filter((a) =>
      a.hdong_name && normalizeHdongName(a.hdong_name) === wanted
    );
    if (byName.length === 1) return byName[0].sgg_code;
  }
  if (hint.bjdCode) {
    const hdongs = new Set(
      bridge.filter((b) => b.bjd_code === hint.bjdCode).map((b) => b.hdong_code),
    );
    const sggs = new Set(perHdong.filter((a) => hdongs.has(a.hdong_code)).map((a) => a.sgg_code));
    if (sggs.size === 1) return [...sggs][0];
  }
  return null;
}

export async function suggestionsFor(
  store: ReadStore,
  addresses: JusoAddress[],
): Promise<{ address: string; district: DistrictRef }[]> {
  if (addresses.length === 0) return [];
  const sigungus = [...new Set(addresses.map((a) => a.admCd.slice(0, 5)))];
  const areas = await store.areasForSigungu(CURRENT_DISTRICT_SG_ID, sigungus);
  const needBridge = addresses.map((a) => a.admCd);
  const bridge = await store.bridgeFor([...new Set(needBridge)]);

  const resolved = addresses.map((a) => {
    const sigungu = a.admCd.slice(0, 5);
    const local = areas.filter((x) => x.sigungu_code === sigungu);
    return {
      address: a.roadAddr,
      code: resolveSggCode(local, sigungu, { hdongName: a.hemdNm, bjdCode: a.admCd }, bridge),
    };
  });

  const codes = [...new Set(resolved.map((r) => r.code).filter((c): c is string => c !== null))];
  const districts = await store.districtsBySggCodes(CURRENT_DISTRICT_SG_ID, codes);
  const byCode = new Map<string, DistrictRec>(districts.map((d) => [d.sgg_code, d]));

  const seen = new Set<string>();
  const out: { address: string; district: DistrictRef }[] = [];
  for (const r of resolved) {
    const d = r.code ? byCode.get(r.code) : undefined;
    if (!d || seen.has(r.address)) continue; // unmapped addresses are dropped
    seen.add(r.address);
    out.push({ address: r.address, district: { id: d.id, displayName: d.display_name } });
  }
  return out;
}

export async function districtForHdong(
  store: ReadStore,
  hdong: { code: string; name: string | null },
): Promise<DistrictRef | null> {
  const sigungu = hdong.code.slice(0, 5);
  const local = await store.areasForSigungu(CURRENT_DISTRICT_SG_ID, [sigungu]);
  const code = resolveSggCode(local, sigungu, { hdongCode: hdong.code, hdongName: hdong.name });
  if (!code) return null;
  const [d] = await store.districtsBySggCodes(CURRENT_DISTRICT_SG_ID, [code]);
  return d ? { id: d.id, displayName: d.display_name } : null;
}

/**
 * The district of one address the user picked, for resident verification. Stricter than
 * suggestionsFor: juso is searched with the full road address, and only results whose
 * roadAddr is that address count (or the sole result, when juso returns one). Every
 * such result must map, and all to the same district; otherwise null. The client's own
 * idea of the district is never asked for.
 */
export async function districtForRoadAddress(
  store: ReadStore,
  found: JusoAddress[],
  roadAddress: string,
): Promise<DistrictRef | null> {
  const norm = (s: string) => s.replace(/\s+/g, " ").trim();
  const wanted = norm(roadAddress);
  const exact = found.filter((a) => norm(a.roadAddr) === wanted);
  const candidates = exact.length > 0 ? exact : found.length === 1 ? found : [];
  if (candidates.length === 0) return null;
  // One at a time: suggestionsFor merges equal addresses, which could hide a split.
  const each = await Promise.all(candidates.map((a) => suggestionsFor(store, [a])));
  if (each.some((s) => s.length === 0)) return null;
  const ids = new Set(each.map((s) => s[0].district.id));
  if (ids.size !== 1) return null;
  return each[0][0].district;
}
