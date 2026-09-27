// 선관위 ingest (data.go.kr):
//   codes      — election codes + 22대 선거구 codes (weekly)
//   candidates — 예비후보자/후보자 of upcoming 국회의원 elections (weekly; hourly in election periods)
//   backfill   — winners of past general elections (20·21·22대 by default, or ?sgIds=a,b)
//   counts     — final 개표 per 선거구 of past general elections (same default, or ?sgIds=a,b)

import { compactToIsoDate, kstToday } from "../_shared/dates.ts";
import {
  CURRENT_DISTRICT_SG_ID,
  districtNameKey,
  SG_TYPE_ASSEMBLY_CONSTITUENCY,
} from "../_shared/district_names.ts";
import { type FetchLike, type RetryOptions, UpstreamError } from "../_shared/http.ts";
import { writeRaw } from "../_shared/ingest_common.ts";
import { fetchNecAll, NEC_OPERATIONS } from "../_shared/nec.ts";
import {
  type CandidateKind,
  type DistrictCountRow,
  generalElectionTerm,
  normalizeCandidate,
  normalizeCount,
  normalizeDistrict,
  normalizeElection,
  normalizeWinner,
  redactNecPersonPayload,
} from "../_shared/normalize_nec.ts";
import type { Postgrest } from "../_shared/postgrest.ts";
import { SOURCES } from "../_shared/provenance.ts";

export interface NecIngestDeps {
  db: Postgrest;
  fetch: FetchLike;
  serviceKey: string;
  now?: () => Date;
  retry?: RetryOptions;
  numOfRows?: number;
  /** Refuse to apply a district list shorter than this (partial response guard). */
  minDistricts?: number;
  /** Refuse to apply counts for fewer 선거구 than this (a general election has 253-254). */
  minCountDistricts?: number;
}

export const DEFAULT_BACKFILL_SG_IDS = ["20160413", "20200415", "20240410"];
const TYPE = String(SG_TYPE_ASSEMBLY_CONSTITUENCY);

function fetchOpts(
  deps: NecIngestDeps,
  operation: string,
  params: Record<string, string>,
  sourceUrl: string,
  fetchedAt: string,
  redact: boolean,
) {
  return {
    fetch: deps.fetch,
    serviceKey: deps.serviceKey,
    retry: deps.retry,
    numOfRows: deps.numOfRows,
    onPage: async ({ pageNo, json }: { pageNo: number; json: unknown }) => {
      await writeRaw(deps.db, {
        table: "raw_nec",
        service: operation,
        params,
        page: pageNo,
        payload: redact ? redactNecPersonPayload(json) : json,
        sourceUrl,
        fetchedAt,
      });
    },
  };
}

export async function ingestCodes(deps: NecIngestDeps) {
  const fetchedAt = (deps.now?.() ?? new Date()).toISOString();

  const elections = (await fetchNecAll(
    NEC_OPERATIONS.electionCodes,
    {},
    fetchOpts(deps, NEC_OPERATIONS.electionCodes, {}, SOURCES.necCodes.url, fetchedAt, false),
  )).map((i) => normalizeElection(i, fetchedAt)).filter((e) => e !== null);
  // count_status is not in the payload, so a manual 'counting' flag survives.
  await deps.db.upsert("elections", elections, "sg_id,sg_typecode");

  const params = { sgId: CURRENT_DISTRICT_SG_ID, sgTypecode: TYPE };
  const districts = (await fetchNecAll(
    NEC_OPERATIONS.districtCodes,
    params,
    fetchOpts(deps, NEC_OPERATIONS.districtCodes, params, SOURCES.necCodes.url, fetchedAt, false),
  )).map((i) => normalizeDistrict(i, fetchedAt)).filter((d) => d !== null);
  const min = deps.minDistricts ?? 250;
  if (districts.length < min) {
    throw new Error(`districts: only ${districts.length} rows (expected >= ${min}); not applied`);
  }
  const ids = new Set(districts.map((d) => d.id));
  if (ids.size !== districts.length) throw new Error("districts: derived ids collide; not applied");
  await deps.db.upsert("districts", districts, "id");
  return { elections: elections.length, districts: districts.length };
}

export async function ingestCandidates(deps: NecIngestDeps) {
  const now = deps.now?.() ?? new Date();
  const fetchedAt = now.toISOString();
  const upcoming = await deps.db.select<{ sg_id: string }>("elections", {
    select: "sg_id",
    sg_typecode: `eq.${TYPE}`,
    vote_date: `gte.${kstToday(now)}`,
  });

  const counts: Record<string, number> = {};
  for (const { sg_id } of upcoming) {
    const params = { sgId: sg_id, sgTypecode: TYPE };
    for (
      const [kind, op] of [
        ["preliminary", NEC_OPERATIONS.preliminaryCandidates],
        ["final", NEC_OPERATIONS.candidates],
      ] as [CandidateKind, string][]
    ) {
      const rows = (await fetchNecAll(
        op,
        params,
        fetchOpts(deps, op, params, SOURCES.necCandidates.url, fetchedAt, true),
      )).map((i) => normalizeCandidate(i, kind, fetchedAt)).filter((c) => c !== null);
      await deps.db.upsert("candidates", rows, "sg_id,sg_typecode,huboid,kind");
      counts[`${sg_id}:${kind}`] = rows.length;
    }
  }
  return { elections: upcoming.length, counts };
}

export async function ingestWinners(deps: NecIngestDeps, sgIds: string[]) {
  const fetchedAt = (deps.now?.() ?? new Date()).toISOString();
  const counts: Record<string, number> = {};
  for (const sgId of sgIds) {
    if (!/^\d{8}$/.test(sgId)) throw new RangeError(`bad sgId ${sgId}`);
    const term = generalElectionTerm(sgId, "");
    // Make sure the election row exists even if the code list omits it
    // (without overwriting what the code list said).
    const existing = await deps.db.select("elections", {
      select: "sg_id",
      sg_id: `eq.${sgId}`,
      sg_typecode: `eq.${TYPE}`,
    });
    if (existing.length === 0) {
      await deps.db.upsert("elections", [{
        sg_id: sgId,
        sg_typecode: SG_TYPE_ASSEMBLY_CONSTITUENCY,
        sg_name: term ? `제${term}대 국회의원선거` : `국회의원선거 ${sgId}`,
        vote_date: `${sgId.slice(0, 4)}-${sgId.slice(4, 6)}-${sgId.slice(6, 8)}`,
        term,
        source_url: SOURCES.necCodes.url,
        publisher: SOURCES.necCodes.publisher,
        fetched_at: fetchedAt,
      }], "sg_id,sg_typecode");
    }

    const params = { sgId, sgTypecode: TYPE };
    const rows = (await fetchNecAll(
      NEC_OPERATIONS.winners,
      params,
      fetchOpts(deps, NEC_OPERATIONS.winners, params, SOURCES.necWinners.url, fetchedAt, true),
    )).map((i) => normalizeWinner(i, fetchedAt)).filter((w) => w !== null);
    await deps.db.upsert("election_results", rows, "sg_id,sg_typecode,huboid");
    counts[sgId] = rows.length;
  }
  return { winners: counts };
}

/**
 * Final counts per 선거구 (the "합계" row only) of past general elections.
 *
 * NEC's 선거구 list for the same election says which 시도 to ask and what a
 * complete answer is. Each 시도 is asked once, without sggName; any 선거구 the
 * answer leaves out (all of them, if the API turns out to require sggName) is
 * then asked for by name. About 17 calls per election when the 시도 call
 * works, about 254 when it does not.
 *
 * Only the 22대 rows get a district_id: the districts table is the 22대 선거구.
 * Older rows are kept by name_key and joined the way winners are.
 */
export async function ingestCounts(deps: NecIngestDeps, sgIds: string[]) {
  const now = deps.now?.() ?? new Date();
  const fetchedAt = now.toISOString();
  const today = kstToday(now);
  const summary: Record<string, unknown> = {};
  for (const sgId of sgIds) {
    if (!/^\d{8}$/.test(sgId)) throw new RangeError(`bad sgId ${sgId}`);
    // A count in progress must never be stored as a final one, and before the
    // polls close it may not be published at all (공직선거법 제167조제2항).
    if ((compactToIsoDate(sgId) ?? "") >= today) {
      throw new RangeError(`counts: ${sgId} is not in the past; only finished counts are ingested`);
    }
    const request = { sgId, sgTypecode: SG_TYPE_ASSEMBLY_CONSTITUENCY };

    const codeParams = { sgId, sgTypecode: TYPE };
    const sggs = (await fetchNecAll(
      NEC_OPERATIONS.districtCodes,
      codeParams,
      fetchOpts(
        deps,
        NEC_OPERATIONS.districtCodes,
        codeParams,
        SOURCES.necCodes.url,
        fetchedAt,
        false,
      ),
    )).map((i) => ({
      sdName: String(i.sdName ?? "").trim(),
      sggName: String(i.sggName ?? "").trim(),
    })).filter((s) => s.sdName !== "" && s.sggName !== "");

    const rows = new Map<string, DistrictCountRow>();
    const fetchCounts = async (params: Record<string, string>) => {
      const items = await fetchNecAll(
        NEC_OPERATIONS.counts,
        params,
        fetchOpts(deps, NEC_OPERATIONS.counts, params, SOURCES.necCounts.url, fetchedAt, false),
      );
      for (const item of items) {
        const row = normalizeCount(item, request, fetchedAt);
        if (row) rows.set(row.name_key, row);
      }
    };

    let askedByName = 0;
    for (const sdName of new Set(sggs.map((s) => s.sdName))) {
      try {
        await fetchCounts({ sgId, sgTypecode: TYPE, sdName });
      } catch (error) {
        // A 시도-wide call the API refuses is answered 선거구 by 선거구 below.
        if (!(error instanceof UpstreamError)) throw error;
      }
      for (const sgg of sggs.filter((s) => s.sdName === sdName)) {
        if (rows.has(districtNameKey(sgg.sdName, sgg.sggName))) continue;
        askedByName++;
        await fetchCounts({ sgId, sgTypecode: TYPE, sdName, sggName: sgg.sggName });
      }
    }

    const counted = [...rows.values()];
    const min = deps.minCountDistricts ?? 250;
    if (counted.length < min) {
      throw new Error(
        `counts ${sgId}: only ${counted.length} districts (expected >= ${min}); not applied`,
      );
    }

    const unmatched: string[] = [];
    if (sgId === CURRENT_DISTRICT_SG_ID) {
      const districts = await deps.db.select<{ id: string; name_key: string }>("districts", {
        select: "id,name_key",
        sg_id: `eq.${sgId}`,
      });
      const ids = new Map(districts.map((d) => [d.name_key, d.id]));
      for (const row of counted) {
        row.district_id = ids.get(row.name_key) ?? null;
        if (row.district_id === null) unmatched.push(row.name_key);
      }
    }
    await deps.db.upsert("district_counts", counted, "sg_id,sg_typecode,name_key");
    summary[sgId] = { districts: counted.length, askedByName, unmatchedDistricts: unmatched };
  }
  return { counts: summary };
}

function sgIdsParam(url: URL | undefined): string[] {
  const list = url?.searchParams.get("sgIds") ?? url?.searchParams.get("sgId");
  return list ? list.split(",").map((s) => s.trim()) : DEFAULT_BACKFILL_SG_IDS;
}

export async function runNecIngest(mode: string, deps: NecIngestDeps, url?: URL) {
  switch (mode) {
    case "codes":
      return await ingestCodes(deps);
    case "candidates":
      return await ingestCandidates(deps);
    case "backfill":
      return await ingestWinners(deps, sgIdsParam(url));
    case "counts":
      return await ingestCounts(deps, sgIdsParam(url));
    default:
      throw new RangeError(`unknown mode "${mode}" (codes | candidates | backfill | counts)`);
  }
}
