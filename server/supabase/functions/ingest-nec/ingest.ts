// 선관위 ingest (data.go.kr):
//   codes      — election codes + 22대 선거구 codes (weekly)
//   candidates — 예비후보자/후보자 of upcoming 국회의원 elections (weekly; hourly in election periods)
//   backfill   — winners of past general elections (20·21·22대 by default, or ?sgIds=a,b)

import { kstToday } from "../_shared/dates.ts";
import {
  CURRENT_DISTRICT_SG_ID,
  SG_TYPE_ASSEMBLY_CONSTITUENCY,
} from "../_shared/district_names.ts";
import type { FetchLike, RetryOptions } from "../_shared/http.ts";
import { writeRaw } from "../_shared/ingest_common.ts";
import { fetchNecAll, NEC_OPERATIONS } from "../_shared/nec.ts";
import {
  type CandidateKind,
  generalElectionTerm,
  normalizeCandidate,
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

export async function runNecIngest(mode: string, deps: NecIngestDeps, url?: URL) {
  switch (mode) {
    case "codes":
      return await ingestCodes(deps);
    case "candidates":
      return await ingestCandidates(deps);
    case "backfill": {
      const list = url?.searchParams.get("sgIds");
      return await ingestWinners(
        deps,
        list ? list.split(",").map((s) => s.trim()) : DEFAULT_BACKFILL_SG_IDS,
      );
    }
    default:
      throw new RangeError(`unknown mode "${mode}" (codes | candidates | backfill)`);
  }
}
