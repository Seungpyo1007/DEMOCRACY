// Field mapping for 선관위 items. The only file that knows NEC field names.
// Field names taken from the NEC open-data portal docs (data.nec.go.kr) and
// data.go.kr dataset pages, 2026-09-24. Not yet checked against a keyed call,
// except the 개표 fields read by normalizeCount (see testdata/README.md).

import {
  districtIdFor,
  districtNameKey,
  formatDistrictDisplayName,
  necSggCode,
} from "./district_names.ts";
import { compactToIsoDate } from "./dates.ts";
import type { NecItem } from "./nec.ts";
import { SOURCES } from "./provenance.ts";

const str = (v: unknown): string | null => {
  if (typeof v === "number") return String(v);
  if (typeof v !== "string") return null;
  const t = v.trim();
  return t === "" ? null : t;
};

const num = (v: unknown): number | null => {
  const s = str(v)?.replace(/,/g, "");
  if (s === undefined || s === null) return null;
  const n = Number(s);
  return Number.isFinite(n) ? n : null;
};

export interface ElectionRow {
  sg_id: string;
  sg_typecode: number;
  sg_name: string;
  vote_date: string | null;
  term: number | null;
  source_url: string;
  publisher: string;
  fetched_at: string;
}

/** Known general elections, for rows whose name lacks "제N대". */
const KNOWN_TERMS: Record<string, number> = {
  "20160413": 20,
  "20200415": 21,
  "20240410": 22,
  "20280412": 23,
};

/** 제N대 for a 국회의원선거 (general election); null for by-elections etc. */
export function generalElectionTerm(sgId: string, sgName: string): number | null {
  const m = /제\s*(\d+)\s*대\s*국회의원\s*선거/.exec(sgName);
  if (m) return Number(m[1]);
  return KNOWN_TERMS[sgId] ?? null;
}

/** getCommonSgCodeList: sgId, sgTypecode, sgName, sgVotedate. */
export function normalizeElection(item: NecItem, fetchedAt: string): ElectionRow | null {
  const sgId = str(item.sgId);
  const type = num(item.sgTypecode);
  const name = str(item.sgName);
  if (!sgId || type === null || !name) return null;
  return {
    sg_id: sgId,
    sg_typecode: type,
    sg_name: name,
    vote_date: compactToIsoDate(str(item.sgVotedate) ?? sgId),
    term: type === 2 ? generalElectionTerm(sgId, name) : null,
    source_url: SOURCES.necCodes.url,
    publisher: SOURCES.necCodes.publisher,
    fetched_at: fetchedAt,
  };
}

export interface DistrictRow {
  id: string;
  sg_id: string;
  sg_typecode: number;
  sgg_code: string;
  sd_name: string;
  wiw_name: string | null;
  sgg_name: string;
  display_name: string;
  name_key: string;
  sgg_jungsu: number | null;
  s_order: number | null;
  source_url: string;
  publisher: string;
  fetched_at: string;
}

/** getCommonSggCodeList: sgId, sgTypecode, sggName, sdName, wiwName, sggJungsu, sOrder. */
export function normalizeDistrict(item: NecItem, fetchedAt: string): DistrictRow | null {
  const sgId = str(item.sgId);
  const type = num(item.sgTypecode);
  const sdName = str(item.sdName);
  const sggName = str(item.sggName);
  if (!sgId || type === null || !sdName || !sggName) return null;
  // A future API version might add a real code; prefer it if present.
  const code = str(item.sggCode) ?? necSggCode(sdName, sggName);
  return {
    id: districtIdFor(code),
    sg_id: sgId,
    sg_typecode: type,
    sgg_code: code,
    sd_name: sdName,
    wiw_name: str(item.wiwName),
    sgg_name: sggName.replace(/\s+/g, ""),
    display_name: formatDistrictDisplayName(sdName, sggName),
    name_key: districtNameKey(sdName, sggName),
    sgg_jungsu: num(item.sggJungsu),
    s_order: num(item.sOrder),
    source_url: SOURCES.necCodes.url,
    publisher: SOURCES.necCodes.publisher,
    fetched_at: fetchedAt,
  };
}

export interface ElectionResultRow {
  sg_id: string;
  sg_typecode: number;
  huboid: string;
  sd_name: string;
  sgg_name: string;
  name_key: string;
  name: string;
  party: string | null;
  votes: number | null;
  share: number | null;
  is_winner: boolean;
  source_url: string;
  publisher: string;
  fetched_at: string;
}

/** getWinnerInfoInqire: huboid, sdName, sggName, name, jdName, dugsu, dugyul. */
export function normalizeWinner(item: NecItem, fetchedAt: string): ElectionResultRow | null {
  const sgId = str(item.sgId);
  const type = num(item.sgTypecode);
  const huboid = str(item.huboid);
  const sdName = str(item.sdName);
  const sggName = str(item.sggName);
  const name = str(item.name);
  if (!sgId || type === null || !huboid || !sdName || !sggName || !name) return null;
  return {
    sg_id: sgId,
    sg_typecode: type,
    huboid,
    sd_name: sdName,
    sgg_name: sggName.replace(/\s+/g, ""),
    name_key: districtNameKey(sdName, sggName),
    name,
    party: str(item.jdName),
    votes: num(item.dugsu),
    share: num(item.dugyul),
    is_winner: true,
    source_url: SOURCES.necWinners.url,
    publisher: SOURCES.necWinners.publisher,
    fetched_at: fetchedAt,
  };
}

export type CandidateKind = "preliminary" | "final";

export interface CandidateRow {
  sg_id: string;
  sg_typecode: number;
  huboid: string;
  kind: CandidateKind;
  sd_name: string;
  sgg_name: string;
  name_key: string;
  name: string;
  party: string | null;
  status: string | null;
  career1: string | null;
  career2: string | null;
  source_url: string;
  publisher: string;
  fetched_at: string;
}

const MAX_CAREER = 60;
const short = (s: string | null) =>
  s === null ? null : s.length > MAX_CAREER ? `${s.slice(0, MAX_CAREER - 1)}…` : s;

/**
 * Candidates keep only name, party, huboid and short 경력 strings. Address,
 * birth date, age, gender, education and job are never stored.
 */
export function normalizeCandidate(
  item: NecItem,
  kind: CandidateKind,
  fetchedAt: string,
): CandidateRow | null {
  const sgId = str(item.sgId);
  const type = num(item.sgTypecode);
  const huboid = str(item.huboid);
  const sdName = str(item.sdName);
  const sggName = str(item.sggName);
  const name = str(item.name);
  if (!sgId || type === null || !huboid || !sdName || !sggName || !name) return null;
  return {
    sg_id: sgId,
    sg_typecode: type,
    huboid,
    kind,
    sd_name: sdName,
    sgg_name: sggName.replace(/\s+/g, ""),
    name_key: districtNameKey(sdName, sggName),
    name,
    party: str(item.jdName),
    status: str(item.status),
    career1: short(str(item.career1)),
    career2: short(str(item.career2)),
    source_url: SOURCES.necCandidates.url,
    publisher: SOURCES.necCandidates.publisher,
    fetched_at: fetchedAt,
  };
}

export interface CountCandidate {
  name: string;
  party: string | null;
  votes: number;
}

export interface DistrictCountRow {
  sg_id: string;
  sg_typecode: number;
  sd_name: string;
  sgg_name: string;
  name_key: string;
  /** Set by the ingest for the 22대 only, whose 선거구 are the districts table. */
  district_id: string | null;
  electorate: number | null;
  turnout: number | null;
  valid_votes: number;
  invalid_votes: number | null;
  abstentions: number | null;
  candidates: CountCandidate[];
  counted_share: number;
  source_url: string;
  publisher: string;
  fetched_at: string;
}

/** 후보자 slots on a 개표 row: hbj01..hbj50, jd01..jd50, dugsu01..dugsu50. */
const COUNT_SLOTS = 50;
/** wiwName of the row that totals a 선거구 across its 구시군. */
export const COUNT_TOTAL_ROW = "합계";

/**
 * getXmntckSttusInfoInqire (투·개표 정보, 개표현황): one row per 선거구 and
 * 구시군, plus the 선거구's own total, whose wiwName is "합계". Only that total
 * is kept: sunsu (선거인수), tusu (투표수), yutusu (유효투표수), mutusu
 * (무효투표수), gigwonsu (기권수), and per slot NN the 후보자 hbjNN, the party
 * jdNN and the votes dugsuNN. Unused slots are empty strings.
 *
 * `counted_share` is 100: the ingest refuses an election whose day has not
 * passed, so every row it stores is a finished count.
 */
export function normalizeCount(
  item: NecItem,
  request: { sgId: string; sgTypecode: number },
  fetchedAt: string,
): DistrictCountRow | null {
  if (str(item.wiwName) !== COUNT_TOTAL_ROW) return null;
  const sgId = str(item.sgId) ?? request.sgId;
  const type = num(item.sgTypecode) ?? request.sgTypecode;
  const sdName = str(item.sdName);
  const sggName = str(item.sggName);
  const valid = num(item.yutusu);
  if (!sdName || !sggName || sggName === COUNT_TOTAL_ROW || valid === null || valid <= 0) {
    return null;
  }
  const candidates: CountCandidate[] = [];
  for (let i = 1; i <= COUNT_SLOTS; i++) {
    const nn = String(i).padStart(2, "0");
    const name = str(item[`hbj${nn}`]);
    const votes = num(item[`dugsu${nn}`]);
    if (!name || votes === null) continue;
    candidates.push({ name, party: str(item[`jd${nn}`]), votes });
  }
  if (candidates.length === 0) return null;
  return {
    sg_id: sgId,
    sg_typecode: type,
    sd_name: sdName,
    sgg_name: sggName.replace(/\s+/g, ""),
    name_key: districtNameKey(sdName, sggName),
    district_id: null,
    electorate: num(item.sunsu),
    turnout: num(item.tusu),
    valid_votes: valid,
    invalid_votes: num(item.mutusu),
    abstentions: num(item.gigwonsu),
    candidates,
    counted_share: 100,
    source_url: SOURCES.necCounts.url,
    publisher: SOURCES.necCounts.publisher,
    fetched_at: fetchedAt,
  };
}

/** Fields of a person-level NEC item that may be written to raw_nec. */
const PERSON_FIELDS_KEPT = new Set([
  "num",
  "sgId",
  "sgTypecode",
  "huboid",
  "sggName",
  "sdName",
  "wiwName",
  "giho",
  "gihoSangse",
  "jdName",
  "name",
  "career1",
  "career2",
  "status",
  "regdate",
  "dugsu",
  "dugyul",
]);

/** Removes addr/birthday/age/gender/edu/job from winner/candidate payloads. */
export function redactNecPersonPayload(json: unknown): unknown {
  const body = (json as { response?: { body?: { items?: { item?: unknown } } } })?.response?.body;
  const item = body?.items?.item;
  if (item === undefined) return json;
  const scrub = (it: unknown) => {
    if (!it || typeof it !== "object") return it;
    return Object.fromEntries(
      Object.entries(it as Record<string, unknown>).filter(([k]) => PERSON_FIELDS_KEPT.has(k)),
    );
  };
  const clone = structuredClone(json) as { response: { body: { items: { item: unknown } } } };
  clone.response.body.items.item = Array.isArray(item) ? item.map(scrub) : scrub(item);
  return clone;
}
