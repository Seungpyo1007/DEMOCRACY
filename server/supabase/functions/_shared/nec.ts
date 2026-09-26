// 중앙선거관리위원회 Open API on data.go.kr.
//
// GET https://apis.data.go.kr/9760000/{Service}/{operation}?ServiceKey=..&pageNo=1&numOfRows=100&resultType=json
// { response: { header: { resultCode, resultMsg }, body: { items: { item: [...] | {...} }, totalCount } } }
// resultCode "INFO-00" = OK; "INFO-03" = no data. Gateway auth/quota errors come back as XML.

import { fetchJsonWithRetry, type FetchLike, type RetryOptions, UpstreamError } from "./http.ts";

export const NEC_BASE = "https://apis.data.go.kr/9760000";

export const NEC_OPERATIONS = {
  electionCodes: "CommonCodeService/getCommonSgCodeList",
  districtCodes: "CommonCodeService/getCommonSggCodeList",
  winners: "WinnerInfoInqireService2/getWinnerInfoInqire",
  /** 후보자 (registered, after 후보자 등록) */
  candidates: "PofelcddInfoInqireService/getPofelcddRegistSttusInfoInqire",
  /** 예비후보자 */
  preliminaryCandidates: "PofelcddInfoInqireService/getPoelpcddRegistSttusInfoInqire",
} as const;

export type NecItem = Record<string, unknown>;

export interface NecPage {
  items: NecItem[];
  total: number;
}

const NO_DATA_CODES = new Set(["INFO-03", "INFO-200", "03"]);
const OK_CODES = new Set(["INFO-00", "00", "INFO-000"]);

export function necUrl(
  operation: string,
  serviceKey: string,
  params: Record<string, string>,
  pageNo: number,
  numOfRows: number,
): string {
  const url = new URL(`${NEC_BASE}/${operation}`);
  // Pass the *decoded* key from data.go.kr; URLSearchParams encodes it once.
  url.searchParams.set("ServiceKey", serviceKey);
  url.searchParams.set("pageNo", String(pageNo));
  url.searchParams.set("numOfRows", String(numOfRows));
  url.searchParams.set("resultType", "json");
  for (const [k, v] of Object.entries(params)) url.searchParams.set(k, v);
  return url.toString();
}

export function parseNecPage(operation: string, json: unknown): NecPage {
  const response = (json as { response?: Record<string, unknown> } | null)?.response;
  if (!response || typeof response !== "object") {
    throw new UpstreamError(`${operation}: missing response`);
  }
  const header = response.header as { resultCode?: string; resultMsg?: string } | undefined;
  const code = header?.resultCode ?? "";
  if (NO_DATA_CODES.has(code)) return { items: [], total: 0 };
  if (!OK_CODES.has(code)) {
    throw new UpstreamError(`${operation}: ${code} ${header?.resultMsg ?? ""}`.trim());
  }
  const body = (response.body ?? {}) as Record<string, unknown>;
  const total = Number(body.totalCount ?? 0) || 0;
  const itemsBlock = body.items;
  let raw: unknown = undefined;
  if (itemsBlock && typeof itemsBlock === "object" && !Array.isArray(itemsBlock)) {
    raw = (itemsBlock as { item?: unknown }).item;
  } else if (Array.isArray(itemsBlock)) {
    raw = itemsBlock;
  }
  // A single result arrives as an object, not a one-element array.
  const items = raw === undefined || raw === null || raw === ""
    ? []
    : Array.isArray(raw)
    ? (raw as NecItem[])
    : [raw as NecItem];
  return { items, total };
}

export interface NecFetchOptions {
  fetch: FetchLike;
  serviceKey: string;
  numOfRows?: number;
  maxPages?: number;
  retry?: RetryOptions;
  onPage?: (page: { pageNo: number; json: unknown }) => Promise<void> | void;
}

export async function fetchNecAll(
  operation: string,
  params: Record<string, string>,
  opts: NecFetchOptions,
): Promise<NecItem[]> {
  const numOfRows = opts.numOfRows ?? 100;
  const maxPages = opts.maxPages ?? 200;
  const all: NecItem[] = [];
  for (let pageNo = 1; pageNo <= maxPages; pageNo++) {
    const url = necUrl(operation, opts.serviceKey, params, pageNo, numOfRows);
    const json = await fetchJsonWithRetry(opts.fetch, url, opts.retry);
    const page = parseNecPage(operation, json);
    await opts.onPage?.({ pageNo, json });
    all.push(...page.items);
    if (page.items.length < numOfRows || all.length >= page.total) break;
  }
  return all;
}
