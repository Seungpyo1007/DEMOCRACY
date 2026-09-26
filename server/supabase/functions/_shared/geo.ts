// juso.go.kr (address search) and Kakao Local (coordinate → 행정동) clients.
// Neither the query nor the coordinates are ever logged or stored.

import { fetchJsonWithRetry, type FetchLike, type RetryOptions, UpstreamError } from "./http.ts";

export const JUSO_URL = "https://business.juso.go.kr/addrlink/addrLinkApi.do";
export const KAKAO_REGION_URL = "https://dapi.kakao.com/v2/local/geo/coord2regioncode.json";

export interface JusoAddress {
  roadAddr: string;
  /** 법정동 code, 10 digits. */
  admCd: string;
  siNm: string | null;
  sggNm: string | null;
  emdNm: string | null;
  /** 행정동 name; present when addInfoYn=Y. */
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
      hemdNm: s(r.hemdNm),
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

export function kakaoRegionUrl(lat: number, lng: number): string {
  const url = new URL(KAKAO_REGION_URL);
  url.searchParams.set("x", String(lng));
  url.searchParams.set("y", String(lat));
  return url.toString();
}

/** documents[] with region_type "H" = 행정동; its `code` is the 10-digit 행정동 code. */
export function parseKakaoHdong(json: unknown): { code: string; name: string | null } | null {
  const docs = (json as { documents?: unknown[] } | null)?.documents;
  if (!Array.isArray(docs)) throw new UpstreamError("kakao: missing documents");
  for (const d of docs) {
    const doc = d as Record<string, unknown>;
    if (doc.region_type === "H" && typeof doc.code === "string" && /^\d{10}$/.test(doc.code)) {
      return { code: doc.code, name: s(doc.region_3depth_name) };
    }
  }
  return null;
}

export async function lookupHdong(
  fetchFn: FetchLike,
  kakaoKey: string,
  lat: number,
  lng: number,
  retry?: RetryOptions,
): Promise<{ code: string; name: string | null } | null> {
  const json = await fetchJsonWithRetry(fetchFn, kakaoRegionUrl(lat, lng), {
    retries: 1,
    ...retry,
    init: { headers: { Authorization: `KakaoAK ${kakaoKey}` } },
  });
  return parseKakaoHdong(json);
}
