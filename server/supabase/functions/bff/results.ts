// Assembles the app's election results payload (RawElectionResults.fromJson)
// from district_counts. Same rule as builders.ts: a count without usable
// provenance is dropped, never shown unsourced.
//
// Off election, this is the last general election's final count. Past results
// are not restricted by 공직선거법 (docs/ELECTION_LAW.md, 「역대 결과는 제한하지
// 않는다」), so nothing here is withheld.

import { ApiError } from "../_shared/envelope.ts";
import { CURRENT_DISTRICT_SG_ID } from "../_shared/district_names.ts";
import { generalElectionTerm } from "../_shared/normalize_nec.ts";
import { sourceMeta } from "../_shared/provenance.ts";
import type { CountRec, DistrictRec, ReadStore } from "./store.ts";

const round1 = (x: number) => Math.round(x * 10) / 10;

interface Tally {
  name: string;
  party: string;
  share: number;
}

/** Candidates as stored, each with its share of the valid votes; highest first. */
function tallies(count: CountRec): Tally[] {
  if (!Array.isArray(count.candidates) || !(count.valid_votes > 0)) return [];
  return (count.candidates as { name?: unknown; party?: unknown; votes?: unknown }[])
    .filter((c): c is { name: string; party: unknown; votes: number } =>
      !!c && typeof c === "object" && typeof c.name === "string" && c.name.trim() !== "" &&
      typeof c.votes === "number" && Number.isFinite(c.votes) && c.votes >= 0
    )
    .sort((a, b) => b.votes - a.votes)
    .map((c) => ({
      name: c.name,
      party: typeof c.party === "string" && c.party.trim() !== "" ? c.party : "무소속",
      share: round1((c.votes / count.valid_votes) * 100),
    }));
}

function districtCountJson(district: DistrictRec, count: CountRec | undefined) {
  const source = count ? sourceMeta(count.source_url, count.fetched_at) : null;
  const rows = count ? tallies(count) : [];
  if (!count || !source || rows.length === 0) return null;
  return {
    districtId: district.id,
    districtName: district.display_name,
    countedShare: count.counted_share,
    tallies: rows,
    source,
  };
}

/**
 * The line on 「역대 결과」: the winner's share of the valid votes in each
 * election this district's 선거구 took part in, from the stored counts. An
 * election whose 선거구 cannot be matched to this district by name or curated
 * lineage (or matches more than one) is left out, not estimated.
 */
function historical(rows: CountRec[]) {
  const bySgId = new Map<string, CountRec[]>();
  for (const r of rows) bySgId.set(r.sg_id, [...(bySgId.get(r.sg_id) ?? []), r]);
  const points: { year: number; share: number }[] = [];
  for (const [sgId, found] of bySgId) {
    if (found.length !== 1 || !sourceMeta(found[0].source_url, found[0].fetched_at)) continue;
    const top = tallies(found[0])[0];
    const year = Number(sgId.slice(0, 4));
    if (top && Number.isInteger(year)) points.push({ year, share: top.share });
  }
  return points.sort((a, b) => a.year - b.year);
}

export async function buildResults(store: ReadStore, id: string) {
  const sgId = CURRENT_DISTRICT_SG_ID;
  const district = await store.district(id);
  if (!district) throw new ApiError("not_found", "Unknown district.");

  const [districts, counts, history, elections] = await Promise.all([
    store.districtsOf(sgId),
    store.countsOf(sgId),
    store.countHistory(district),
    store.generalElections(),
  ]);

  // Every district the map can draw. 22대 rows carry district_id; name_key
  // covers a count ingested before the district list.
  const byId = new Map(counts.filter((c) => c.district_id).map((c) => [c.district_id, c]));
  const byKey = new Map(counts.map((c) => [c.name_key, c]));
  const served = districts
    .map((d) => districtCountJson(d, byId.get(d.id) ?? byKey.get(d.name_key)))
    .filter((d) => d !== null);
  if (!served.some((d) => d.districtId === id)) {
    throw new ApiError("not_found", "No sourced count is on record for this district.");
  }

  const election = elections.find((e) => e.sg_id === sgId && e.sg_typecode === 2);
  const term = election?.term ?? generalElectionTerm(sgId, "");
  const electionName = election?.sg_name ?? `제${term}대 국회의원선거`;

  return {
    electionName,
    // null is how the app is told no election is pending; a missing key would
    // fail to parse. While a future election is pending this must instead be
    // the authoritative schedule (pollsClose including any NEC extension, with
    // its source), and the server must send no count for that election before
    // pollsClose -- the server-side block in docs/ELECTION_LAW.md 「BFF 책임」 3.
    // The client gate is defence in depth, not the legal guarantee.
    electionSchedule: null,
    overallCountedShare: round1(
      served.reduce((sum, d) => sum + d.countedShare, 0) / served.length,
    ),
    live: false,
    districts: served,
    historical: historical(history),
    // No polls. 제108조제5항 needs a 심의위 registration behind every published
    // series, and nothing here can verify one yet (「BFF 책임」 1).
    polls: [],
  };
}
