// juso.go.kr (address search) and V-World (coordinate → 행정동) clients.
// Neither the query nor the coordinates are ever logged or stored.

import { fetchJsonWithRetry, type FetchLike, type RetryOptions, UpstreamError } from "./http.ts";

export const JUSO_URL = "https://business.juso.go.kr/addrlink/addrLinkApi.do";
export const VWORLD_ADDRESS_URL = "https://api.vworld.kr/req/address";

export interface JusoAddress {
  roadAddr: string;
  /** 법정동 code, 10 digits. */
  admCd: string;
  siNm: string | null;
  sggNm: string | null;
  emdNm: string | null;
  /** 행정동 name ("치평동"); present when addInfoYn=Y. */
  hemdNm: string | null;
}

export function jusoUrl(key: string, keyword: string, count = 10): string {
  const url = new URL(JUSO_URL);
  url.searchParams.set("confmKey", key);
  url.searchParams.set("currentPage", "1");
  url.searchParams.set("countPerPage", String(count));
  url.searchParams.set("keyword", keyword);
  url.searchParams.set("resultType", "json");
  url.searchParams.set("addInfoYn", "Y");
  return url.toString();
}

const s = (v: unknown) => (typeof v === "string" && v.trim() !== "" ? v.trim() : null);

/** juso sends hemdNm whole, "전남광주통합특별시 서구 치평동"; the 행정동 is the last word. */
const lastWord = (v: string | null) => v?.split(/\s+/).pop() ?? null;

/** results.common.errorCode "0" = OK. Keyword errors (E0005..E0015) = no results. */
export function parseJuso(json: unknown): JusoAddress[] {
  const results = (json as { results?: Record<string, unknown> } | null)?.results;
  if (!results) throw new UpstreamError("juso: missing results");
  const common = results.common as { errorCode?: string; errorMessage?: string } | undefined;
  const code = common?.errorCode ?? "0";
  if (code !== "0") {
    // E0005..E0015 are about the keyword itself; treat as "nothing found".
    if (/^E00(0[5-9]|1[0-5])$/.test(code)) return [];
    throw new UpstreamError(`juso: ${code}`);
  }
  const list = results.juso;
  if (!Array.isArray(list)) return [];
  const out: JusoAddress[] = [];
  for (const raw of list) {
    const r = raw as Record<string, unknown>;
    const roadAddr = s(r.roadAddr);
    const admCd = s(r.admCd);
    if (!roadAddr || !admCd || !/^\d{10}$/.test(admCd)) continue;
    out.push({
      roadAddr,
      admCd,
      siNm: s(r.siNm),
      sggNm: s(r.sggNm),
      emdNm: s(r.emdNm),
      hemdNm: lastWord(s(r.hemdNm)),
    });
  }
  return out;
}

export async function searchJuso(
  fetchFn: FetchLike,
  key: string,
  keyword: string,
  retry?: RetryOptions,
): Promise<JusoAddress[]> {
  const json = await fetchJsonWithRetry(fetchFn, jusoUrl(key, keyword), retry ?? { retries: 1 });
  return parseJuso(json);
}

/** Where a coordinate is, as far as the district mapping needs to know. */
export interface PlaceCodes {
  /** 10-digit 행정동 code; V-World gives it with road addresses only. */
  hdongCode: string | null;
  hdongName: string | null;
  /** 10-digit 법정동 code, from the parcel result; the fallback through the bridge. */
  bjdCode: string | null;
}

/** V-World reverse geocoding (Geocoder API 2.0, getAddress). */
export function vworldAddressUrl(key: string, lat: number, lng: number, domain?: string): string {
  const url = new URL(VWORLD_ADDRESS_URL);
  url.searchParams.set("service", "address");
  url.searchParams.set("request", "getAddress");
  url.searchParams.set("version", "2.0");
  url.searchParams.set("crs", "epsg:4326");
  url.searchParams.set("point", `${lng},${lat}`);
  url.searchParams.set("type", "both");
  url.searchParams.set("zipcode", "false");
  url.searchParams.set("simple", "false");
  url.searchParams.set("format", "json");
  url.searchParams.set("key", key);
  if (domain) url.searchParams.set("domain", domain);
  return url.toString();
}

/**
 * response.status "OK" | "NOT_FOUND" | "ERROR". result[] holds a "parcel" and/or a "road"
 * entry. Checked live 2026-09-27: both carry the 행정동 (level4A, level4AC) although the
 * reference says parcel entries do not; level4LC is the 법정동 code on a parcel entry and a
 * 7-digit road code on a road entry, so only 10 digits count.
 */
export function parseVworldPlace(json: unknown): PlaceCodes | null {
  const res = (json as { response?: Record<string, unknown> } | null)?.response;
  if (!res) throw new UpstreamError("vworld: missing response");
  if (res.status === "NOT_FOUND") return null;
  if (res.status !== "OK") {
    const code = (res.error as { code?: unknown } | undefined)?.code;
    throw new UpstreamError(`vworld: ${typeof code === "string" ? code : "error"}`);
  }
  const list = Array.isArray(res.result) ? res.result : [];
  let hdongCode: string | null = null;
  let hdongName: string | null = null;
  let bjdCode: string | null = null;
  for (const raw of list) {
    const st = ((raw as Record<string, unknown>)?.structure ?? {}) as Record<string, unknown>;
    const hc = s(st.level4AC);
    if (!hdongCode && hc && /^\d{10}$/.test(hc)) {
      hdongCode = hc;
      hdongName = s(st.level4A);
    }
    const bc = s(st.level4LC);
    if (!bjdCode && bc && /^\d{10}$/.test(bc)) bjdCode = bc;
  }
  return hdongCode || bjdCode ? { hdongCode, hdongName, bjdCode } : null;
}

export async function lookupPlace(
  fetchFn: FetchLike,
  key: string,
  lat: number,
  lng: number,
  domain?: string,
  retry?: RetryOptions,
): Promise<PlaceCodes | null> {
  const json = await fetchJsonWithRetry(fetchFn, vworldAddressUrl(key, lat, lng, domain), {
    retries: 1,
    ...retry,
  });
  return parseVworldPlace(json);
}
