// 열린국회정보 Open API client.
//
// GET https://open.assembly.go.kr/portal/openapi/{SERVICE}?KEY=..&Type=json&pIndex=1&pSize=100
// Success: { "<SERVICE>": [ {head:[{list_total_count:N},{RESULT:{CODE:"INFO-000"}}]}, {row:[...]} ] }
// No data: { "RESULT": { "CODE": "INFO-200", ... } }
// Error:   { "RESULT": { "CODE": "ERROR-xxx", ... } }

import { fetchJsonWithRetry, type FetchLike, type RetryOptions, UpstreamError } from "./http.ts";

export const ASSEMBLY_BASE = "https://open.assembly.go.kr/portal/openapi";

export const ASSEMBLY_SERVICES = {
  members: "nwvrqwxyaytdsfvhu",
  allMembers: "ALLNAMEMBER",
  bills: "nzmimeepazxkubdpn",
  votes: "nojepdqqaweusdfbi",
} as const;

export type AssemblyRow = Record<string, unknown>;

export interface AssemblyPage {
  rows: AssemblyRow[];
  total: number;
}

export function assemblyUrl(
  service: string,
  key: string,
  params: Record<string, string>,
  pIndex: number,
  pSize: number,
): string {
  const url = new URL(`${ASSEMBLY_BASE}/${service}`);
  url.searchParams.set("KEY", key);
  url.searchParams.set("Type", "json");
  url.searchParams.set("pIndex", String(pIndex));
  url.searchParams.set("pSize", String(pSize));
  for (const [k, v] of Object.entries(params)) url.searchParams.set(k, v);
  return url.toString();
}

export function parseAssemblyPage(service: string, json: unknown): AssemblyPage {
  if (json === null || typeof json !== "object") {
    throw new UpstreamError(`${service}: body is not an object`);
  }
  const obj = json as Record<string, unknown>;

  const bare = obj["RESULT"] as { CODE?: string; MESSAGE?: string } | undefined;
  if (bare) {
    if (bare.CODE === "INFO-200") return { rows: [], total: 0 };
    if (bare.CODE === "INFO-000") return { rows: [], total: 0 };
    throw new UpstreamError(`${service}: ${bare.CODE} ${bare.MESSAGE ?? ""}`.trim());
  }

  const parts = obj[service];
  if (!Array.isArray(parts)) throw new UpstreamError(`${service}: missing service block`);

  let total = 0;
  let rows: AssemblyRow[] = [];
  for (const part of parts) {
    if (part && typeof part === "object" && "head" in part) {
      const head = (part as { head: unknown[] }).head ?? [];
      for (const h of head) {
        const entry = h as Record<string, unknown>;
        if (typeof entry.list_total_count === "number") total = entry.list_total_count;
        const result = entry.RESULT as { CODE?: string; MESSAGE?: string } | undefined;
        if (result?.CODE === "INFO-200") return { rows: [], total: 0 };
        if (result?.CODE && result.CODE !== "INFO-000") {
          throw new UpstreamError(`${service}: ${result.CODE} ${result.MESSAGE ?? ""}`.trim());
        }
      }
    }
    if (part && typeof part === "object" && "row" in part) {
      const r = (part as { row: unknown }).row;
      if (Array.isArray(r)) rows = r as AssemblyRow[];
    }
  }
  return { rows, total };
}

export interface AssemblyFetchOptions {
  fetch: FetchLike;
  key: string;
  pageSize?: number;
  maxPages?: number;
  retry?: RetryOptions;
  /** Called with each page's raw JSON (for raw_* storage). */
  onPage?: (page: { pIndex: number; json: unknown }) => Promise<void> | void;
}

export interface AssemblyPageRun {
  rows: AssemblyRow[];
  /** list_total_count as the last page reported it. */
  total: number;
  /** The last page index fetched. */
  lastPage: number;
  /** True when the service has no pages after `lastPage`. */
  done: boolean;
}

/**
 * Fetches up to `maxPages` pages starting at `firstPage` (1-based). A long
 * backfill runs in windows so each call stays under the function time limit;
 * `done` says whether another window is needed.
 */
export async function fetchAssemblyPages(
  service: string,
  params: Record<string, string>,
  opts: AssemblyFetchOptions & { firstPage?: number },
): Promise<AssemblyPageRun> {
  const pageSize = opts.pageSize ?? 1000;
  const maxPages = opts.maxPages ?? 100;
  const firstPage = opts.firstPage ?? 1;
  const all: AssemblyRow[] = [];
  let total = 0;
  let lastPage = firstPage - 1;
  let done = false;
  for (let pIndex = firstPage; pIndex < firstPage + maxPages; pIndex++) {
    const url = assemblyUrl(service, opts.key, params, pIndex, pageSize);
    const json = await fetchJsonWithRetry(opts.fetch, url, opts.retry);
    const page = parseAssemblyPage(service, json);
    await opts.onPage?.({ pIndex, json });
    all.push(...page.rows);
    total = page.total;
    lastPage = pIndex;
    if (page.rows.length < pageSize || pIndex * pageSize >= page.total) {
      done = true;
      break;
    }
  }
  return { rows: all, total, lastPage, done };
}

/** Fetches every page of a service. INFO-200 yields []. */
export async function fetchAssemblyAll(
  service: string,
  params: Record<string, string>,
  opts: AssemblyFetchOptions,
): Promise<AssemblyRow[]> {
  return (await fetchAssemblyPages(service, params, opts)).rows;
}
