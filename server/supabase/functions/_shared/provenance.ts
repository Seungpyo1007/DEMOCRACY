// Where every figure comes from.
//
// `url` is always a page a person can open in a browser (the dataset's own
// page), never the keyed API endpoint the ingest job called. The app derives
// the publisher badge from the URL host, so the host matters.

export interface SourceRef {
  url: string;
  publisher: string;
  attribution: string;
  license: string;
}

const ASSEMBLY_ATTRIBUTION = "출처: 열린국회정보";
const ASSEMBLY_LICENSE = "공공누리 제1유형 (출처표시)";
const NEC_ATTRIBUTION = "출처: 중앙선거관리위원회, 공공데이터포털";
const NEC_LICENSE = "공공데이터포털 이용허락범위 제한 없음";

const assemblyPage = (infId: string) =>
  `https://open.assembly.go.kr/portal/data/service/selectAPIServicePage.do/${infId}`;

export const SOURCES = {
  /** 국회의원 인적사항 (nwvrqwxyaytdsfvhu) */
  assemblyMembers: {
    url: assemblyPage("OWSSC6001134T516707"),
    publisher: "국회사무처",
    attribution: ASSEMBLY_ATTRIBUTION,
    license: ASSEMBLY_LICENSE,
  },
  /** 국회의원 정보 통합 API (ALLNAMEMBER) — portrait URLs */
  assemblyAllMembers: {
    url: assemblyPage("OOWY4R001216HX11439"),
    publisher: "국회사무처",
    attribution: ASSEMBLY_ATTRIBUTION,
    license: ASSEMBLY_LICENSE,
  },
  /** 국회의원 발의법률안 (nzmimeepazxkubdpn) */
  assemblyBills: {
    url: assemblyPage("OK7XM1000938DS17215"),
    publisher: "국회사무처",
    attribution: ASSEMBLY_ATTRIBUTION,
    license: ASSEMBLY_LICENSE,
  },
  /** 국회의원 본회의 표결정보 (nojepdqqaweusdfbi) */
  assemblyVotes: {
    url: assemblyPage("OPR1MQ000998LC12535"),
    publisher: "국회사무처",
    attribution: ASSEMBLY_ATTRIBUTION,
    license: ASSEMBLY_LICENSE,
  },
  /** 중앙선거관리위원회_코드정보 */
  necCodes: {
    url: "https://www.data.go.kr/data/15000897/openapi.do",
    publisher: "중앙선거관리위원회",
    attribution: NEC_ATTRIBUTION,
    license: NEC_LICENSE,
  },
  /** 중앙선거관리위원회_당선인 정보 */
  necWinners: {
    url: "https://www.data.go.kr/data/15000864/openapi.do",
    publisher: "중앙선거관리위원회",
    attribution: NEC_ATTRIBUTION,
    license: NEC_LICENSE,
  },
  /** 중앙선거관리위원회_후보자 정보 */
  necCandidates: {
    url: "https://www.data.go.kr/data/15000908/openapi.do",
    publisher: "중앙선거관리위원회",
    attribution: NEC_ATTRIBUTION,
    license: NEC_LICENSE,
  },
  /** 중앙선거관리위원회_투·개표 정보 */
  necCounts: {
    url: "https://www.data.go.kr/data/15000900/openapi.do",
    publisher: "중앙선거관리위원회",
    attribution: NEC_ATTRIBUTION,
    license: NEC_LICENSE,
  },
} as const satisfies Record<string, SourceRef>;

/** Query parameters that carry an API credential. None may reach a client. */
const KEYED_PARAM = /[?&](KEY|ServiceKey|serviceKey|confmKey|apikey|api_key)=/i;

export function isKeyedUrl(url: string): boolean {
  return KEYED_PARAM.test(url);
}

/** True when `url` may be shown to a person as a source link. */
export function isPresentableSourceUrl(url: unknown): url is string {
  if (typeof url !== "string" || url.trim() === "") return false;
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    return false;
  }
  return (parsed.protocol === "https:" || parsed.protocol === "http:") &&
    parsed.host !== "" && !isKeyedUrl(url);
}

export function isTimestamp(value: unknown): value is string {
  return typeof value === "string" && value.trim() !== "" && !Number.isNaN(Date.parse(value));
}

/** `{sourceUrl, fetchedAt}`, the app's SourceMetadata. */
export interface SourceMeta {
  sourceUrl: string;
  fetchedAt: string;
}

/** `{value, sourceUrl, fetchedAt}`, the app's SourcedValue. */
export interface SourcedNumber extends SourceMeta {
  value: number;
}

/**
 * Builds a SourceMeta or returns null when provenance is missing/unusable.
 * Callers drop whatever a null source was going to be attached to.
 */
export function sourceMeta(sourceUrl: unknown, fetchedAt: unknown): SourceMeta | null {
  if (!isPresentableSourceUrl(sourceUrl) || !isTimestamp(fetchedAt)) return null;
  return { sourceUrl, fetchedAt: new Date(fetchedAt).toISOString() };
}

export function sourcedNumber(
  value: unknown,
  sourceUrl: unknown,
  fetchedAt: unknown,
): SourcedNumber | null {
  const meta = sourceMeta(sourceUrl, fetchedAt);
  if (meta === null || typeof value !== "number" || !Number.isFinite(value)) return null;
  return { value, ...meta };
}

/** Walks any JSON value and returns every string that is a keyed URL. */
export function findKeyedUrls(value: unknown, found: string[] = []): string[] {
  if (typeof value === "string") {
    if (isKeyedUrl(value)) found.push(value);
  } else if (Array.isArray(value)) {
    for (const item of value) findKeyedUrls(item, found);
  } else if (value !== null && typeof value === "object") {
    for (const item of Object.values(value)) findKeyedUrls(item, found);
  }
  return found;
}

/** The latest of several timestamps (ISO strings), or null if none. */
export function latest(...stamps: (string | null | undefined)[]): string | null {
  let best: number | null = null;
  for (const stamp of stamps) {
    if (!stamp) continue;
    const t = Date.parse(stamp);
    if (!Number.isNaN(t) && (best === null || t > best)) best = t;
  }
  return best === null ? null : new Date(best).toISOString();
}
