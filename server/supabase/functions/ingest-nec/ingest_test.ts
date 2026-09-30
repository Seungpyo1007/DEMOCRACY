import { assert, assertEquals, assertRejects } from "@std/assert";
import { MemoryPostgrest } from "../_shared/memory_postgrest.ts";
import {
  DEFAULT_BACKFILL_SG_IDS,
  ingestCandidates,
  ingestCodes,
  ingestCounts,
  ingestWinners,
  runNecIngest,
} from "./ingest.ts";
import { normalizeCount } from "../_shared/normalize_nec.ts";
import { fakeUpstream } from "../../../testdata/fake_upstream.ts";
import { MAPO_B, NOW } from "../../../testdata/pipeline.ts";

const now = () => NOW;
function deps() {
  const db = new MemoryPostgrest();
  const up = fakeUpstream();
  return {
    up,
    d: {
      db,
      fetch: up.fetch,
      serviceKey: "NEC+KEY/==",
      now,
      retry: { retries: 0 },
      minDistricts: 1,
    },
  };
}

Deno.test("codes: elections + 22대 districts with fixed-contract ids", async () => {
  const { d, up } = deps();
  assertEquals(await ingestCodes(d), { elections: 5, districts: 4 });
  const mapo = d.db.rows("districts").find((r) => r.id === MAPO_B)!;
  assertEquals(mapo.display_name, "서울 마포구 을");
  // The decoded key is URL-encoded exactly once.
  assert(up.requests.every((u) => u.includes("ServiceKey=NEC%2BKEY%2F%3D%3D")));
  assert(!JSON.stringify(d.db.rows("raw_nec")).includes("NEC+KEY"));
});

Deno.test("codes: a manual count_status survives re-ingest", async () => {
  const { d } = deps();
  await ingestCodes(d);
  await d.db.update("elections", { sg_id: "eq.20280412", sg_typecode: "eq.2" }, {
    count_status: "counting",
  });
  await ingestCodes(d);
  assertEquals(
    d.db.rows("elections").find((e) => e.sg_id === "20280412" && e.sg_typecode === 2)!.count_status,
    "counting",
  );
});

Deno.test("codes: a short district list is not applied", async () => {
  const { d } = deps();
  await assertRejects(() => ingestCodes({ ...d, minDistricts: 250 }), Error, "not applied");
  assertEquals(d.db.rows("districts").length, 0);
});

Deno.test("backfill: winners for 20·21·22대, single-object responses handled, idempotent", async () => {
  const { d } = deps();
  const r = await ingestWinners(d, DEFAULT_BACKFILL_SG_IDS);
  assertEquals(r.winners, { "20160413": 1, "20200415": 1, "20240410": 2 });
  await ingestWinners(d, DEFAULT_BACKFILL_SG_IDS);
  assertEquals(d.db.rows("election_results").length, 4);
  assertEquals(d.db.rows("elections").map((e) => e.term).sort(), [20, 21, 22]);
  const raw = JSON.stringify(d.db.rows("raw_nec"));
  assert(!raw.includes("birthday") && !raw.includes("addr"));
  await assertRejects(
    () => runNecIngest("backfill", d, new URL("https://x/?sgIds=2024")),
    RangeError,
  );
});

Deno.test("counts: 합계 rows only, per 시도 with a by-name fallback, 22대 mapped to districts", async () => {
  const { d, up } = deps();
  await ingestCodes(d);
  const r = await ingestCounts({ ...d, minCountDistricts: 1 }, DEFAULT_BACKFILL_SG_IDS);
  assertEquals(r.counts, {
    // 20160413 answers no 시도-wide call, so each 선거구 is asked by name.
    "20160413": { districts: 1, askedByName: 4, unmatchedDistricts: [] },
    // The 21대 서울 sample holds 마포구을 alone, and 대구 has none: the three
    // 선거구 left out are asked by name and have no data.
    "20200415": { districts: 1, askedByName: 3, unmatchedDistricts: [] },
    "20240410": { districts: 4, askedByName: 0, unmatchedDistricts: [] },
  });
  assert(up.requests.some((u) => u.includes("sggName=")));
  const rows = d.db.rows("district_counts");
  assertEquals(rows.length, 6);
  const mapo = rows.find((c) => c.sg_id === "20240410" && c.name_key === "서울마포구을")!;
  assertEquals(mapo.district_id, MAPO_B);
  assertEquals(
    [mapo.electorate, mapo.turnout, mapo.valid_votes, mapo.invalid_votes, mapo.abstentions],
    [199000, 137300, 135474, 1826, 61700],
  );
  assertEquals(mapo.candidates, [
    { name: "가상 의원", party: "가나당", votes: 61234 },
    { name: "가상 후보 나", party: "나다당", votes: 55000 },
    { name: "가상 후보 다", party: "무소속", votes: 19240 },
  ]);
  assertEquals(mapo.counted_share, 100);
  assertEquals(mapo.source_url, "https://www.data.go.kr/data/15000900/openapi.do");
  // Older elections are kept by name only.
  assert(rows.filter((c) => c.sg_id !== "20240410").every((c) => c.district_id === null));
  // Idempotent.
  await ingestCounts({ ...d, minCountDistricts: 1 }, DEFAULT_BACKFILL_SG_IDS);
  assertEquals(d.db.rows("district_counts").length, 6);
});

Deno.test("counts: a short answer is not applied; an unfinished election is refused", async () => {
  const { d } = deps();
  await assertRejects(
    () => ingestCounts({ ...d, minCountDistricts: 250 }, ["20240410"]),
    Error,
    "not applied",
  );
  assertEquals(d.db.rows("district_counts").length, 0);
  await assertRejects(() => ingestCounts(d, ["20280412"]), RangeError, "not in the past");
  await assertRejects(
    () => runNecIngest("counts", d, new URL("https://x/?mode=counts&sgIds=2024")),
    RangeError,
  );
});

Deno.test("normalizeCount: keeps the 합계 row, skips empty slots and 구시군 rows", () => {
  const fetchedAt = NOW.toISOString();
  const request = { sgId: "20240410", sgTypecode: 2 };
  const row = {
    sdName: "세종특별자치시",
    sggName: "세종특별자치시갑",
    wiwName: "합계",
    sunsu: "1,000",
    tusu: "700",
    yutusu: "690",
    mutusu: "10",
    gigwonsu: "300",
    jd01: "가나당",
    hbj01: "가상 가",
    dugsu01: "400",
    jd02: "",
    hbj02: "가상 나",
    dugsu02: "290",
    jd03: "",
    hbj03: "",
    dugsu03: "",
  };
  const c = normalizeCount(row, request, fetchedAt)!;
  assertEquals(c.name_key, "세종세종특별자치시갑");
  assertEquals(c.electorate, 1000);
  assertEquals(c.candidates, [
    { name: "가상 가", party: "가나당", votes: 400 },
    { name: "가상 나", party: null, votes: 290 },
  ]);
  assertEquals(normalizeCount({ ...row, wiwName: "세종특별자치시" }, request, fetchedAt), null);
  assertEquals(normalizeCount({ ...row, sggName: "합계" }, request, fetchedAt), null);
  assertEquals(normalizeCount({ ...row, yutusu: "0" }, request, fetchedAt), null);
  assertEquals(normalizeCount({ ...row, hbj01: "", hbj02: "" }, request, fetchedAt), null);
});

Deno.test("candidates: only for upcoming elections, minimal personal data", async () => {
  const { d } = deps();
  await ingestCodes(d);
  const r = await ingestCandidates(d);
  assertEquals(r.elections, 1); // 20280412 only
  const [c] = d.db.rows("candidates");
  assertEquals([c.kind, c.name, c.status], ["final", "가상 후보 가", "등록"]);
  for (const banned of ["addr", "birthday", "age", "gender", "edu", "job"]) {
    assert(!(banned in c), banned);
  }
});
