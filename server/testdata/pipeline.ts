// End-to-end offline pipeline for tests: sample upstream responses → ingest
// functions → in-memory tables → BFF MemoryStore. Everything the contract
// tests check was produced by the real normalizers, not hand-built rows.

import { MemoryPostgrest } from "../supabase/functions/_shared/memory_postgrest.ts";
import { districtIdFor, necSggCode } from "../supabase/functions/_shared/district_names.ts";
import {
  ingestBills,
  ingestBillsBackfill,
  ingestMembers,
  ingestVotes,
} from "../supabase/functions/ingest-assembly/ingest.ts";
import {
  DEFAULT_BACKFILL_SG_IDS,
  ingestCandidates,
  ingestCodes,
  ingestCounts,
  ingestWinners,
} from "../supabase/functions/ingest-nec/ingest.ts";
import { emptyTables, type MemoryTables } from "../supabase/functions/bff/store.ts";
import { parseDistrictAreas } from "../scripts/import_district_areas.ts";
import { parseBridge } from "../scripts/import_bjdong_hdong.ts";
import { parseAttendance } from "../scripts/import_attendance.ts";
import { fakeUpstream, sample } from "./fake_upstream.ts";

export const NOW = new Date("2026-09-24T03:00:00Z");
export const MAPO_B = districtIdFor(necSggCode("서울특별시", "마포구을"));
export const MAPO_A = districtIdFor(necSggCode("서울특별시", "마포구갑"));
export const JONGNO = districtIdFor(necSggCode("서울특별시", "종로구"));

/** Registers stand-ins for the SQL functions the ingest code calls. */
export function withRpcs(db: MemoryPostgrest): MemoryPostgrest {
  db.rpcs.set("bills_needing_votes", (args, self) => {
    const results = args.p_results as string[];
    const logged = new Map(self.rows("vote_fetch_log").map((l) => [l.bill_id, l]));
    return self.rows("bills")
      .filter((b) =>
        b.age === args.p_age && results.includes(b.proc_result as string) && b.proc_dt !== null
      )
      .filter((b) => {
        const l = logged.get(b.bill_id);
        return !l || (l.row_count === 0 && String(b.proc_dt) >= String(args.p_retry_since));
      })
      .slice(0, args.p_limit as number)
      .map((b) => ({ bill_id: b.bill_id }));
  });
  return db;
}

export async function runPipeline(): Promise<{ db: MemoryPostgrest; requests: string[] }> {
  const db = withRpcs(new MemoryPostgrest());
  const up = fakeUpstream();
  const now = () => NOW;
  const retry = { retries: 0 };
  const nec = {
    db,
    fetch: up.fetch,
    serviceKey: "TEST-NEC-KEY",
    now,
    retry,
    minDistricts: 1,
    minCountDistricts: 1,
  };
  const asm = { db, fetch: up.fetch, key: "TEST-ASSEMBLY-KEY", now, retry, minMembers: 1 };

  await ingestCodes(nec);
  await ingestWinners(nec, DEFAULT_BACKFILL_SG_IDS);
  await ingestCounts(nec, DEFAULT_BACKFILL_SG_IDS);
  await ingestCandidates(nec);
  await ingestMembers(asm);
  await ingestBills(asm);
  await ingestBillsBackfill(asm, { age: 21 });
  await ingestVotes(asm);

  const opts = { sourceUrl: "https://www.law.go.kr/법령/공직선거법", fetchedAt: NOW.toISOString() };
  await db.upsert(
    "district_areas",
    parseDistrictAreas(sample("district_areas_sample.csv"), opts).rows,
    "election_sg_id,hdong_code",
  );
  await db.upsert(
    "bjdong_hdong",
    parseBridge(sample("bjdong_hdong_sample.csv"), {
      sourceUrl: "https://www.mapo.go.kr/site/main/content/mapo04010104",
      fetchedAt: NOW.toISOString(),
    }),
    "bjd_code,hdong_code",
  );
  await db.upsert(
    "plenary_attendance",
    parseAttendance(sample("attendance_sample.csv"), {
      sourceUrl: "https://open.assembly.go.kr/portal/data/sample-attendance-dataset",
      fetchedAt: NOW.toISOString(),
    }),
    "mona_cd,meeting_date,meeting_label",
  );

  // Curated pilot content for 마포구 을 (fictional).
  const at = NOW.toISOString();
  await db.upsert("region_timelines", [{
    district_id: MAPO_B,
    source_url: "https://www.mapo.go.kr/site/main/content/mapo04010104",
    fetched_at: at,
  }], "district_id");
  await db.upsert("region_events", [
    {
      district_id: MAPO_B,
      year: 1944,
      title: "마포구 설치",
      detail: "서대문구·용산구 일부를 나누어 출범",
      sort: 0,
      source_url: "https://www.mapo.go.kr/",
      fetched_at: at,
    },
    {
      district_id: MAPO_B,
      year: null,
      title: "선거구 획정으로 갑·을 분리",
      detail: null,
      sort: 1,
      source_url: "https://www.mapo.go.kr/",
      fetched_at: at,
    },
  ], "district_id,sort");
  await db.upsert("pledge_boards", [{
    district_id: MAPO_B,
    source_url: "https://policy.nec.go.kr/",
    fetched_at: at,
  }, {
    // A list-only board: every pledge 「판정 전」.
    district_id: MAPO_A,
    source_url: "https://policy.nec.go.kr/policy_pdf/mapo-a.pdf",
    fetched_at: at,
  }], "district_id");
  await db.upsert("pledges", [
    {
      id: "p1",
      district_id: MAPO_B,
      title: "환승 개선",
      category: "교통",
      status: "fulfilled",
      evidence_url: null,
      judgement: null,
      sort: 0,
      source_url: "https://policy.nec.go.kr/p1",
      fetched_at: at,
    },
    {
      id: "p2",
      district_id: MAPO_B,
      title: "숲길 확장",
      category: "환경",
      status: "reversed",
      evidence_url: "https://policy.nec.go.kr/p2-diff",
      judgement: {
        steps: [{ actor: "큐레이터 검토", detail: "공보 원문 대조", stamp: "5월 10일" }],
        source: { sourceUrl: "https://policy.nec.go.kr/p2", fetchedAt: at },
      },
      sort: 1,
      source_url: "https://policy.nec.go.kr/p2",
      fetched_at: at,
    },
    // Not judged: listed, but left out of 공약 이행 (still 1 of 2 judged).
    {
      id: "p5",
      district_id: MAPO_B,
      title: "판정 전 공약",
      category: "",
      status: "notJudged",
      evidence_url: null,
      judgement: null,
      sort: 4,
      source_url: "https://policy.nec.go.kr/p5",
      fetched_at: at,
    },
    {
      id: "j1",
      district_id: MAPO_A,
      title: "마포 갑 공약 하나",
      category: null,
      status: "notJudged",
      evidence_url: null,
      judgement: null,
      sort: 0,
      source_url: "https://policy.nec.go.kr/policy_pdf/mapo-a.pdf",
      fetched_at: at,
    },
    {
      id: "j2",
      district_id: MAPO_A,
      title: "마포 갑 공약 둘",
      category: null,
      status: "notJudged",
      // Forbidden by the migration; the BFF must still not pass it on.
      evidence_url: "https://policy.nec.go.kr/j2-evidence",
      judgement: {
        steps: [{ actor: "누군가", detail: "", stamp: "" }],
        source: { sourceUrl: "https://policy.nec.go.kr/j2", fetchedAt: at },
      },
      sort: 1,
      source_url: "https://policy.nec.go.kr/policy_pdf/mapo-a.pdf",
      fetched_at: at,
    },
    // Dropped by the BFF: reversed without evidence, and one without a source.
    {
      id: "p3",
      district_id: MAPO_B,
      title: "근거 없는 번복",
      category: "환경",
      status: "reversed",
      evidence_url: null,
      judgement: null,
      sort: 2,
      source_url: "https://policy.nec.go.kr/p3",
      fetched_at: at,
    },
    {
      id: "p4",
      district_id: MAPO_B,
      title: "출처 없음",
      category: "교통",
      status: "inProgress",
      evidence_url: null,
      judgement: null,
      sort: 3,
      source_url: null,
      fetched_at: at,
    },
  ], "id");

  return { db, requests: up.requests };
}

/** Table rows → the BFF's MemoryStore shape (column names are identical). */
export function toTables(db: MemoryPostgrest): MemoryTables {
  const t = emptyTables();
  const r = (name: string) => db.rows(name) as never[];
  t.districts = r("districts");
  t.members = r("members");
  t.bills = r("bills");
  t.votes = r("bill_votes");
  t.attendance = r("plenary_attendance");
  t.elections = db.rows("elections").map((e) => ({ count_status: "none", ...e })) as never[];
  t.results = r("election_results");
  t.counts = r("district_counts");
  t.candidates = r("candidates");
  t.regionTimelines = r("region_timelines");
  t.regionEvents = r("region_events");
  t.pledgeBoards = r("pledge_boards");
  t.pledges = r("pledges");
  t.areas = r("district_areas");
  t.bridge = r("bjdong_hdong");
  return t;
}
