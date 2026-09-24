// Read access for the BFF. One interface, two implementations: PostgREST (prod)
// and in-memory (tests / contract checks). Aggregations that are SQL functions
// in prod (see migration: bff_* functions) are mirrored in MemoryStore.

import { inList, type Postgrest } from "../_shared/postgrest.ts";
import { kstYearMonth } from "../_shared/dates.ts";
import { latest } from "../_shared/provenance.ts";

interface Sourced {
  source_url: string | null;
  fetched_at: string | null;
}

export interface DistrictRec extends Sourced {
  id: string;
  sg_id: string;
  sgg_code: string;
  sd_name: string;
  sgg_name: string;
  display_name: string;
  name_key: string;
}

export interface MemberRec extends Sourced {
  mona_cd: string;
  name: string;
  party: string | null;
  reele_gbn: string | null;
  photo_url: string | null;
  district_id: string | null;
  is_current: boolean;
}

export interface BillRec extends Sourced {
  bill_id: string;
  bill_name: string;
  age: number;
  rst_mona_cd: string | null;
  propose_dt: string | null;
  committee_dt: string | null;
  cmt_proc_dt: string | null;
  proc_result: string | null;
}

export interface VoteRec extends Sourced {
  bill_id: string;
  mona_cd: string;
  result: string;
  vote_at: string;
}

export interface AttendanceRec extends Sourced {
  mona_cd: string;
  meeting_date: string;
  meeting_label: string;
  status: string;
}

/** One month of a rate: numerator/denominator plus the latest fetch time. */
export interface MonthlyRate {
  month: string; // YYYY-MM (KST)
  numerator: number;
  denominator: number;
  source_url: string | null;
  fetched_at: string | null;
}

export interface ElectionRec extends Sourced {
  sg_id: string;
  sg_typecode: number;
  sg_name: string;
  vote_date: string | null;
  term: number | null;
  count_status: "none" | "counting" | "final";
}

export interface ResultRec extends Sourced {
  sg_id: string;
  sg_typecode: number;
  huboid: string;
  name_key: string;
  name: string;
  party: string | null;
  share: number | null;
  is_winner: boolean;
}

export interface LineageRec {
  district_id: string;
  sg_id: string;
  name_key: string;
}

export interface CandidateRec extends Sourced {
  sg_id: string;
  sg_typecode: number;
  huboid: string;
  kind: "preliminary" | "final";
  name_key: string;
  name: string;
  party: string | null;
  status: string | null;
  career1: string | null;
}

export interface RegionTimelineRec extends Sourced {
  district_id: string;
}

export interface RegionEventRec extends Sourced {
  district_id: string;
  year: number | null;
  title: string;
  detail: string | null;
  sort: number;
}

export interface PledgeBoardRec extends Sourced {
  district_id: string;
}

export interface PledgeRec extends Sourced {
  id: string;
  district_id: string;
  title: string;
  category: string | null;
  status: string;
  evidence_url: string | null;
  judgement: unknown;
  sort: number;
}

export interface AreaRec {
  election_sg_id: string;
  sgg_code: string;
  /** 10-digit 행정동 code, or a 5-digit 시군구 code when the whole 시군구 is one district. */
  hdong_code: string;
  hdong_name: string | null;
  sigungu_code: string;
}

export interface BridgeRec {
  bjd_code: string;
  hdong_code: string;
}

export const ATTENDED_STATUSES = ["출석"];
export const NON_PARTICIPATION = "불참";

export interface ReadStore {
  district(id: string): Promise<DistrictRec | null>;
  districtsBySggCodes(sgId: string, codes: string[]): Promise<DistrictRec[]>;
  incumbent(districtId: string): Promise<MemberRec | null>;
  billCount(monaCd: string, age: number): Promise<{ count: number; fetched_at: string | null }>;
  recentBills(monaCd: string, age: number, limit: number): Promise<BillRec[]>;
  monthlyVoteParticipation(monaCd: string, months: number): Promise<MonthlyRate[]>;
  monthlyAttendance(monaCd: string, months: number): Promise<MonthlyRate[]>;
  attendanceSince(monaCd: string, sinceIsoDate: string): Promise<MonthlyRate | null>;
  generalElections(): Promise<ElectionRec[]>;
  resultsFor(district: DistrictRec): Promise<ResultRec[]>;
  upcomingCandidates(district: DistrictRec, todayIso: string): Promise<CandidateRec[]>;
  regionTimeline(
    districtId: string,
  ): Promise<{ timeline: RegionTimelineRec; events: RegionEventRec[] } | null>;
  pledgeBoard(districtId: string): Promise<{ board: PledgeBoardRec; pledges: PledgeRec[] } | null>;
  areasForSigungu(sgId: string, sigunguCodes: string[]): Promise<AreaRec[]>;
  bridgeFor(bjdCodes: string[]): Promise<BridgeRec[]>;
}

// ---------------------------------------------------------------- memory

export interface MemoryTables {
  districts: DistrictRec[];
  members: MemberRec[];
  bills: BillRec[];
  votes: VoteRec[];
  attendance: AttendanceRec[];
  elections: ElectionRec[];
  results: ResultRec[];
  lineage: LineageRec[];
  candidates: CandidateRec[];
  regionTimelines: RegionTimelineRec[];
  regionEvents: RegionEventRec[];
  pledgeBoards: PledgeBoardRec[];
  pledges: PledgeRec[];
  areas: AreaRec[];
  bridge: BridgeRec[];
}

export function emptyTables(): MemoryTables {
  return {
    districts: [],
    members: [],
    bills: [],
    votes: [],
    attendance: [],
    elections: [],
    results: [],
    lineage: [],
    candidates: [],
    regionTimelines: [],
    regionEvents: [],
    pledgeBoards: [],
    pledges: [],
    areas: [],
    bridge: [],
  };
}

function lastMonths(rates: Map<string, MonthlyRate>, months: number): MonthlyRate[] {
  return [...rates.values()].sort((a, b) => a.month.localeCompare(b.month)).slice(-months);
}

export class MemoryStore implements ReadStore {
  constructor(readonly t: MemoryTables) {}

  district(id: string) {
    return Promise.resolve(this.t.districts.find((d) => d.id === id) ?? null);
  }
  districtsBySggCodes(sgId: string, codes: string[]) {
    return Promise.resolve(
      this.t.districts.filter((d) => d.sg_id === sgId && codes.includes(d.sgg_code)),
    );
  }
  incumbent(districtId: string) {
    return Promise.resolve(
      this.t.members.find((m) => m.is_current && m.district_id === districtId) ?? null,
    );
  }
  billCount(monaCd: string, age: number) {
    // fetched_at falls back to the latest bills ingest for the term, so a
    // member with no sponsored bills still gets a sourced zero.
    const all = this.t.bills.filter((b) => b.age === age);
    const rows = all.filter((b) => b.rst_mona_cd === monaCd);
    return Promise.resolve({
      count: rows.length,
      fetched_at: latest(...rows.map((r) => r.fetched_at)) ??
        latest(...all.map((r) => r.fetched_at)),
    });
  }
  recentBills(monaCd: string, age: number, limit: number) {
    return Promise.resolve(
      this.t.bills
        .filter((b) => b.rst_mona_cd === monaCd && b.age === age)
        .sort((a, b) =>
          (b.propose_dt ?? "").localeCompare(a.propose_dt ?? "") ||
          b.bill_id.localeCompare(a.bill_id)
        )
        .slice(0, limit),
    );
  }
  monthlyVoteParticipation(monaCd: string, months: number) {
    const map = new Map<string, MonthlyRate>();
    for (const v of this.t.votes.filter((v) => v.mona_cd === monaCd)) {
      const month = kstYearMonth(new Date(v.vote_at));
      const r = map.get(month) ??
        { month, numerator: 0, denominator: 0, source_url: v.source_url, fetched_at: null };
      r.denominator += 1;
      if (v.result !== NON_PARTICIPATION) r.numerator += 1;
      r.fetched_at = latest(r.fetched_at, v.fetched_at);
      map.set(month, r);
    }
    return Promise.resolve(lastMonths(map, months));
  }
  monthlyAttendance(monaCd: string, months: number) {
    const map = new Map<string, MonthlyRate>();
    for (const a of this.t.attendance.filter((a) => a.mona_cd === monaCd)) {
      const month = a.meeting_date.slice(0, 7);
      const r = map.get(month) ??
        { month, numerator: 0, denominator: 0, source_url: a.source_url, fetched_at: null };
      r.denominator += 1;
      if (ATTENDED_STATUSES.includes(a.status)) r.numerator += 1;
      r.fetched_at = latest(r.fetched_at, a.fetched_at);
      map.set(month, r);
    }
    return Promise.resolve(lastMonths(map, months));
  }
  attendanceSince(monaCd: string, since: string) {
    const rows = this.t.attendance.filter((a) => a.mona_cd === monaCd && a.meeting_date >= since);
    if (rows.length === 0) return Promise.resolve(null);
    return Promise.resolve({
      month: since.slice(0, 7),
      numerator: rows.filter((a) => ATTENDED_STATUSES.includes(a.status)).length,
      denominator: rows.length,
      source_url: rows[0].source_url,
      fetched_at: latest(...rows.map((r) => r.fetched_at)),
    });
  }
  generalElections() {
    return Promise.resolve(this.t.elections.filter((e) => e.sg_typecode === 2 && e.term !== null));
  }
  resultsFor(district: DistrictRec) {
    const overrides = this.t.lineage.filter((l) => l.district_id === district.id);
    return Promise.resolve(
      this.t.results.filter((r) => {
        if (r.sg_typecode !== 2) return false;
        const o = overrides.filter((l) => l.sg_id === r.sg_id);
        return o.length > 0
          ? o.some((l) => l.name_key === r.name_key)
          : r.name_key === district.name_key;
      }),
    );
  }
  upcomingCandidates(district: DistrictRec, todayIso: string) {
    const upcoming = new Set(
      this.t.elections
        .filter((e) => e.sg_typecode === 2 && e.vote_date !== null && e.vote_date >= todayIso)
        .map((e) => e.sg_id),
    );
    return Promise.resolve(
      this.t.candidates.filter((c) =>
        upcoming.has(c.sg_id) && c.sg_typecode === 2 && c.name_key === district.name_key
      ),
    );
  }
  regionTimeline(districtId: string) {
    const timeline = this.t.regionTimelines.find((r) => r.district_id === districtId);
    if (!timeline) return Promise.resolve(null);
    return Promise.resolve({
      timeline,
      events: this.t.regionEvents
        .filter((e) => e.district_id === districtId)
        .sort((a, b) => a.sort - b.sort),
    });
  }
  pledgeBoard(districtId: string) {
    const board = this.t.pledgeBoards.find((b) => b.district_id === districtId);
    if (!board) return Promise.resolve(null);
    return Promise.resolve({
      board,
      pledges: this.t.pledges
        .filter((p) => p.district_id === districtId)
        .sort((a, b) => a.sort - b.sort),
    });
  }
  areasForSigungu(sgId: string, codes: string[]) {
    return Promise.resolve(
      this.t.areas.filter((a) => a.election_sg_id === sgId && codes.includes(a.sigungu_code)),
    );
  }
  bridgeFor(bjdCodes: string[]) {
    return Promise.resolve(this.t.bridge.filter((b) => bjdCodes.includes(b.bjd_code)));
  }
}

// ---------------------------------------------------------------- postgrest

const SRC = "source_url,fetched_at";

export class PostgrestStore implements ReadStore {
  constructor(private readonly db: Postgrest) {}

  async district(id: string) {
    const rows = await this.db.select<DistrictRec>("districts", {
      select: `id,sg_id,sgg_code,sd_name,sgg_name,display_name,name_key,${SRC}`,
      id: `eq.${id}`,
    });
    return rows[0] ?? null;
  }
  districtsBySggCodes(sgId: string, codes: string[]) {
    if (codes.length === 0) return Promise.resolve([]);
    return this.db.select<DistrictRec>("districts", {
      select: `id,sg_id,sgg_code,sd_name,sgg_name,display_name,name_key,${SRC}`,
      sg_id: `eq.${sgId}`,
      sgg_code: inList(codes),
    });
  }
  async incumbent(districtId: string) {
    const rows = await this.db.select<MemberRec>("members", {
      select: `mona_cd,name,party,reele_gbn,photo_url,district_id,is_current,${SRC}`,
      district_id: `eq.${districtId}`,
      is_current: "eq.true",
      limit: "1",
    });
    return rows[0] ?? null;
  }
  async billCount(monaCd: string, age: number) {
    const rows = await this.db.rpc<{ count: number; fetched_at: string | null }[]>(
      "bff_bill_count",
      { p_mona_cd: monaCd, p_age: age },
    );
    return rows[0] ?? { count: 0, fetched_at: null };
  }
  recentBills(monaCd: string, age: number, limit: number) {
    return this.db.select<BillRec>("bills", {
      select:
        `bill_id,bill_name,age,rst_mona_cd,propose_dt,committee_dt,cmt_proc_dt,proc_result,${SRC}`,
      rst_mona_cd: `eq.${monaCd}`,
      age: `eq.${age}`,
      order: "propose_dt.desc.nullslast,bill_id.desc",
      limit: String(limit),
    });
  }
  monthlyVoteParticipation(monaCd: string, months: number) {
    return this.db.rpc<MonthlyRate[]>("bff_monthly_vote_participation", {
      p_mona_cd: monaCd,
      p_months: months,
    });
  }
  monthlyAttendance(monaCd: string, months: number) {
    return this.db.rpc<MonthlyRate[]>("bff_monthly_attendance", {
      p_mona_cd: monaCd,
      p_months: months,
    });
  }
  async attendanceSince(monaCd: string, since: string) {
    const rows = await this.db.rpc<MonthlyRate[]>("bff_attendance_since", {
      p_mona_cd: monaCd,
      p_since: since,
    });
    const r = rows[0];
    return r && r.denominator > 0 ? r : null;
  }
  generalElections() {
    return this.db.select<ElectionRec>("elections", {
      select: `sg_id,sg_typecode,sg_name,vote_date,term,count_status,${SRC}`,
      sg_typecode: "eq.2",
      term: "not.is.null",
    });
  }
  async resultsFor(district: DistrictRec) {
    const lineage = await this.db.select<LineageRec>("district_lineage", {
      select: "district_id,sg_id,name_key",
      district_id: `eq.${district.id}`,
    });
    const keys = [...new Set([district.name_key, ...lineage.map((l) => l.name_key)])];
    const rows = await this.db.select<ResultRec>("election_results", {
      select: `sg_id,sg_typecode,huboid,name_key,name,party,share,is_winner,${SRC}`,
      sg_typecode: "eq.2",
      name_key: inList(keys),
    });
    return rows.filter((r) => {
      const o = lineage.filter((l) => l.sg_id === r.sg_id);
      return o.length > 0
        ? o.some((l) => l.name_key === r.name_key)
        : r.name_key === district.name_key;
    });
  }
  async upcomingCandidates(district: DistrictRec, todayIso: string) {
    const elections = await this.db.select<{ sg_id: string }>("elections", {
      select: "sg_id",
      sg_typecode: "eq.2",
      vote_date: `gte.${todayIso}`,
    });
    if (elections.length === 0) return [];
    return this.db.select<CandidateRec>("candidates", {
      select: `sg_id,sg_typecode,huboid,kind,name_key,name,party,status,career1,${SRC}`,
      sg_typecode: "eq.2",
      sg_id: inList(elections.map((e) => e.sg_id)),
      name_key: `eq.${district.name_key}`,
    });
  }
  async regionTimeline(districtId: string) {
    const [timeline] = await this.db.select<RegionTimelineRec>("region_timelines", {
      select: `district_id,${SRC}`,
      district_id: `eq.${districtId}`,
    });
    if (!timeline) return null;
    const events = await this.db.select<RegionEventRec>("region_events", {
      select: `district_id,year,title,detail,sort,${SRC}`,
      district_id: `eq.${districtId}`,
      order: "sort.asc",
    });
    return { timeline, events };
  }
  async pledgeBoard(districtId: string) {
    const [board] = await this.db.select<PledgeBoardRec>("pledge_boards", {
      select: `district_id,${SRC}`,
      district_id: `eq.${districtId}`,
    });
    if (!board) return null;
    const pledges = await this.db.select<PledgeRec>("pledges", {
      select: `id,district_id,title,category,status,evidence_url,judgement,sort,${SRC}`,
      district_id: `eq.${districtId}`,
      order: "sort.asc",
    });
    return { board, pledges };
  }
  areasForSigungu(sgId: string, codes: string[]) {
    if (codes.length === 0) return Promise.resolve([]);
    return this.db.select<AreaRec>("district_areas", {
      select: "election_sg_id,sgg_code,hdong_code,hdong_name,sigungu_code",
      election_sg_id: `eq.${sgId}`,
      sigungu_code: inList(codes),
    });
  }
  bridgeFor(bjdCodes: string[]) {
    if (bjdCodes.length === 0) return Promise.resolve([]);
    return this.db.select<BridgeRec>("bjdong_hdong", {
      select: "bjd_code,hdong_code",
      bjd_code: inList(bjdCodes),
    });
  }
}
