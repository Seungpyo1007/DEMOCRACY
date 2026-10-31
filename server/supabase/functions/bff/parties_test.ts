// Party colour and 여/야: the book's rules at period boundaries, unknown parties, and the
// three routes that carry a party.

import { assert, assertEquals } from "@std/assert";
import {
  validateDistrictProfile,
  validateElectionResults,
  validateHistoryRecord,
} from "./contract.ts";
import { createHandler } from "./handler.ts";
import { loadPartyBook, PartyBook, type PartyRec, type RulingPeriodRec } from "./parties.ts";
import { MemoryStore } from "./store.ts";
import { signedOut } from "../../../testdata/fake_auth.ts";
import { fakeUpstream } from "../../../testdata/fake_upstream.ts";
import { MAPO_B, NOW, runPipeline, toTables } from "../../../testdata/pipeline.ts";

// The rows as kpa_apply writes them from KoreaPoliticsAPI v2026.10.26 (ruling_periods.json
// and the parties it names), trimmed to what these tests read.
const sourced = { color_source_url: "https://example.org/ci", color_checked_at: "2026-10-07" };
const unsourced = { color: null, color_source_url: null, color_checked_at: null };
const PARTIES: PartyRec[] = [
  { name: "새누리당", ...unsourced },
  { name: "자유한국당", ...unsourced },
  { name: "미래통합당", ...unsourced },
  { name: "국민의당", ...unsourced },
  { name: "더불어민주당", color: "#003B95", ...sourced },
  { name: "국민의힘", color: "#E61E2B", ...sourced },
];
const PERIODS: RulingPeriodRec[] = [
  { starts_on: "2013-02-25", ends_on: "2017-02-13", party_name: "새누리당" },
  { starts_on: "2017-02-13", ends_on: "2017-03-10", party_name: "자유한국당" },
  { starts_on: "2017-03-10", ends_on: "2017-05-10", party_name: null },
  { starts_on: "2017-05-10", ends_on: "2022-05-10", party_name: "더불어민주당" },
  { starts_on: "2022-05-10", ends_on: "2025-04-04", party_name: "국민의힘" },
  { starts_on: "2025-04-04", ends_on: "2025-06-04", party_name: null },
  { starts_on: "2025-06-04", ends_on: null, party_name: "더불어민주당" },
];

const book = () => new PartyBook(PARTIES, PERIODS);
const side = (name: string, date: string) => book().info(name, date).side;

Deno.test("side: every general election day reads against that day's government", () => {
  // 20대: 박근혜 정부, 새누리당.
  assertEquals(side("새누리당", "2016-04-13"), "ruling");
  assertEquals(side("더불어민주당", "2016-04-13"), "opposition");
  assertEquals(side("국민의당", "2016-04-13"), "opposition");
  // 21대: 문재인 정부.
  assertEquals(side("더불어민주당", "2020-04-15"), "ruling");
  assertEquals(side("미래통합당", "2020-04-15"), "opposition");
  // 22대: 윤석열 정부.
  assertEquals(side("국민의힘", "2024-04-10"), "ruling");
  assertEquals(side("더불어민주당", "2024-04-10"), "opposition");
  // Today (2026-10-07): 이재명 정부.
  assertEquals(side("더불어민주당", "2026-10-07"), "ruling");
  assertEquals(side("국민의힘", "2026-10-07"), "opposition");
});

Deno.test("side: boundaries are half-open, the new period owns its first day", () => {
  // The rename: 02-12 is still 새누리당's, 02-13 is 자유한국당's.
  assertEquals(side("새누리당", "2017-02-12"), "ruling");
  assertEquals(side("새누리당", "2017-02-13"), "opposition");
  assertEquals(side("자유한국당", "2017-02-13"), "ruling");
  // Suspended, not removed: 2016-12-09 ~ 2017-03-09 stays with the president's party.
  assertEquals(side("새누리당", "2016-12-09"), "ruling");
  assertEquals(side("자유한국당", "2017-03-09"), "ruling");
  // Removal day opens the acting presidency: nobody is 여 or 야.
  assertEquals(side("자유한국당", "2017-03-10"), null);
  assertEquals(side("더불어민주당", "2017-05-09"), null);
  assertEquals(side("더불어민주당", "2017-05-10"), "ruling");
  assertEquals(side("더불어민주당", "2022-05-09"), "ruling");
  assertEquals(side("더불어민주당", "2022-05-10"), "opposition");
  assertEquals(side("국민의힘", "2022-05-10"), "ruling");
  assertEquals(side("국민의힘", "2024-12-14"), "ruling");
  assertEquals(side("국민의힘", "2025-04-03"), "ruling");
  assertEquals(side("국민의힘", "2025-04-04"), null);
  assertEquals(side("더불어민주당", "2025-06-03"), null);
  assertEquals(side("더불어민주당", "2025-06-04"), "ruling");
  assertEquals(side("국민의힘", "2025-06-04"), "opposition");
  // Before the first period: not covered, not guessed.
  assertEquals(side("새누리당", "2013-02-24"), null);
});

Deno.test("unknown parties, 무소속 and bad dates get no colour and no side", () => {
  const b = book();
  assertEquals(b.info("가상당", "2024-04-10"), { name: "가상당", color: null, side: null });
  assertEquals(b.info("무소속", "2024-04-10"), { name: "무소속", color: null, side: null });
  assertEquals(b.info(null, "2024-04-10"), { name: "무소속", color: null, side: null });
  assertEquals(b.info("", "2024-04-10"), { name: "무소속", color: null, side: null });
  assertEquals(b.info("국민의힘", "20240410").side, null);
  assertEquals(b.info("국민의힘", null).side, null);
  // On record without a colour: a side, but neutral.
  assertEquals(b.info("새누리당", "2016-04-13"), { name: "새누리당", color: null, side: "ruling" });
  assertEquals(b.info("국민의힘", "2024-04-10"), {
    name: "국민의힘",
    color: "#E61E2B",
    side: "ruling",
  });
});

Deno.test("a colour without its source is not sent", () => {
  const b = new PartyBook(
    [
      { name: "가나당", color: "#112233", color_source_url: null, color_checked_at: null },
      {
        name: "다라당",
        color: "red",
        color_source_url: "https://x.org",
        color_checked_at: "2026-01-01",
      },
      {
        name: "나다당",
        color: "#445566",
        color_source_url: "https://x.org",
        color_checked_at: "2026-01-01",
        aliases: ["나다"],
      },
    ],
    [{ starts_on: "2020-01-01", ends_on: null, party_name: "나다당" }],
  );
  assertEquals(b.info("가나당", "2024-01-01").color, null);
  assertEquals(b.info("다라당", "2024-01-01").color, null);
  assertEquals(b.info("나다당", "2024-01-01").color, "#445566");
  // An alias is the same party, under the name the record used.
  assertEquals(b.info("나다", "2024-01-01"), { name: "나다", color: "#445566", side: "ruling" });
});

Deno.test("a failed party read falls back to names only", async () => {
  const b = await loadPartyBook({ partyBook: () => Promise.reject(new Error("no table")) });
  assertEquals(b.info("국민의힘", "2024-04-10"), { name: "국민의힘", color: null, side: null });
});

// ------------------------------------------------------------------ routes

/** The pipeline fixture uses invented parties; give them colours and a government. */
async function routes() {
  const { db } = await runPipeline();
  const tables = toTables(db);
  const src = { color_source_url: "https://example.org/ci", color_checked_at: "2026-10-07" };
  tables.parties = [
    { name: "가나당", color: "#1A4B8C", ...src },
    { name: "나다당", color: "#F2C230", ...src },
    { name: "다라당", color: null, color_source_url: null, color_checked_at: null },
  ];
  // 다라당 governs up to the 22대 election, 가나당 from it on.
  tables.rulingPeriods = [
    { starts_on: "2013-01-01", ends_on: "2024-01-01", party_name: "다라당" },
    { starts_on: "2024-01-01", ends_on: null, party_name: "가나당" },
  ];
  const handler = createHandler({
    store: new MemoryStore(tables),
    fetch: fakeUpstream().fetch,
    jusoKey: "JUSO-SECRET",
    vworldKey: "VWORLD-SECRET",
    now: () => NOW,
    ...signedOut(),
  });
  return async (path: string) => {
    const res = await handler(new Request(`https://ref.supabase.co/functions/v1/bff${path}`));
    return (await res.json()).data;
  };
}

Deno.test("profile: the sitting member and candidates carry partyInfo beside party", async () => {
  const get = await routes();
  const d = await get(`/districts/${MAPO_B}/profile`);
  assertEquals(validateDistrictProfile(d), []);
  assertEquals(d.incumbent.party, "가나당");
  assertEquals(d.incumbent.partyInfo, { name: "가나당", color: "#1A4B8C", side: "ruling" });
  for (const c of d.candidates) {
    assertEquals(c.partyInfo.name, c.party);
  }
});

Deno.test("history: each winner is placed as of their own election day", async () => {
  const get = await routes();
  const h = await get(`/districts/${MAPO_B}/history`);
  assertEquals(validateHistoryRecord(h), []);
  const byYear = Object.fromEntries(
    h.elections.rows.map((r: { year: number; winner: { partyInfo: unknown } }) => [
      r.year,
      r.winner.partyInfo,
    ]),
  );
  assertEquals(byYear[2016], { name: "다라당", color: null, side: "ruling" });
  assertEquals(byYear[2020], { name: "가나당", color: "#1A4B8C", side: "opposition" });
  assertEquals(byYear[2024], { name: "가나당", color: "#1A4B8C", side: "ruling" });
  assertEquals(h.legislator.incumbent.partyInfo.side, "ruling");
});

Deno.test("results: tallies carry partyInfo as of the election day", async () => {
  const get = await routes();
  const r = await get(`/districts/${MAPO_B}/results`);
  assertEquals(validateElectionResults(r), []);
  const mapo = r.districts.find((d: { districtId: string }) => d.districtId === MAPO_B);
  assertEquals(
    mapo.tallies.map((t: { partyInfo: unknown }) => t.partyInfo),
    [
      { name: "가나당", color: "#1A4B8C", side: "ruling" },
      { name: "나다당", color: "#F2C230", side: "opposition" },
      { name: "무소속", color: null, side: null },
    ],
  );
});

Deno.test("contract: a malformed partyInfo is caught", () => {
  const base = {
    district: { id: "nec-1", displayName: "x" },
    source: { sourceUrl: "https://example.org", fetchedAt: "2026-01-01T00:00:00Z" },
    candidates: [],
  };
  const withInfo = (partyInfo: unknown) => ({
    ...base,
    incumbent: { id: "a", name: "b", party: "가나당", partyInfo },
  });
  assertEquals(validateDistrictProfile(withInfo(undefined)), []);
  assertEquals(validateDistrictProfile(withInfo({ name: "가나당", color: null, side: null })), []);
  assert(validateDistrictProfile(withInfo({ name: "다라당", color: null, side: null })).length > 0);
  assert(
    validateDistrictProfile(withInfo({ name: "가나당", color: "blue", side: null })).length > 0,
  );
  assert(validateDistrictProfile(withInfo({ name: "가나당", color: null, side: "여" })).length > 0);
});
