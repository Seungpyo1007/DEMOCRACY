// Contract tests: responses built from rows the real ingest pipeline produced,
// checked against a TS mirror of the app's Dart parsers.

import { assert, assertEquals } from "@std/assert";
import { findKeyedUrls } from "../_shared/provenance.ts";
import {
  validateAddressSuggestions,
  validateDistrictProfile,
  validateEnvelope,
  validateHistoryRecord,
  validatePledgeBoard,
} from "./contract.ts";
import { createHandler } from "./handler.ts";
import { MemoryStore } from "./store.ts";
import { signedOut } from "../../../testdata/fake_auth.ts";
import { fakeUpstream } from "../../../testdata/fake_upstream.ts";
import { JONGNO, MAPO_A, MAPO_B, NOW, runPipeline, toTables } from "../../../testdata/pipeline.ts";

async function setup(overrides: Record<string, () => Response> = {}) {
  const { db, requests } = await runPipeline();
  const up = fakeUpstream(overrides);
  const handler = createHandler({
    store: new MemoryStore(toTables(db)),
    fetch: up.fetch,
    jusoKey: "JUSO-SECRET",
    vworldKey: "VWORLD-SECRET",
    now: () => NOW,
    ...signedOut(),
  });
  const get = async (path: string) => {
    const res = await handler(new Request(`https://ref.supabase.co/functions/v1/bff${path}`));
    return { res, body: await res.json() };
  };
  return { get, ingestRequests: requests, up };
}

function assertClean(body: unknown) {
  assertEquals(findKeyedUrls(body), [], "no keyed URL may reach the client");
  const text = JSON.stringify(body);
  for (
    const secret of [
      "SECRET",
      "TEST-NEC-KEY",
      "TEST-ASSEMBLY-KEY",
      "KEY=",
      "ServiceKey=",
      "confmKey=",
    ]
  ) {
    assert(!text.includes(secret), secret);
  }
}

Deno.test("profile: matches the DistrictProfile contract", async () => {
  const { get, ingestRequests } = await setup();
  // Sanity: the pipeline did send keys upstream…
  assert(ingestRequests.some((u) => u.includes("KEY=TEST-ASSEMBLY-KEY")));
  const { res, body } = await get(`/districts/${MAPO_B}/profile`);
  assertEquals(res.status, 200);
  assertEquals(res.headers.get("Cache-Control"), "public, max-age=300");
  assertEquals(validateEnvelope(body, false), []);
  assertEquals(body.servedAt, NOW.toISOString());
  assertEquals(validateDistrictProfile(body.data), []);
  assertClean(body); // …and none of them come back out.

  const d = body.data;
  assertEquals(d.district, { id: MAPO_B, displayName: "서울 마포구 을" });
  assertEquals(d.incumbent.name, "가상 의원");
  assertEquals(d.incumbent.summary, "재선");
  assert(d.incumbent.portraitUrl.startsWith("https://www.assembly.go.kr/"));
  const stats = Object.fromEntries(
    d.incumbent.stats.map((
      s: { label: string; value: { value: number } },
    ) => [s.label, s.value.value]),
  );
  // 24 meetings, 21 출석 → 87.5 %; 3 sponsored bills; 1 of 2 valid curated pledges fulfilled.
  assertEquals(stats, { "출석률": 87.5, "발의 법안": 3, "공약 이행": 50 });
  assertEquals(d.incumbent.record.bills.items.map((b: { stage: string }) => b.stage), [
    "접수",
    "위원회 심사",
    "원안가결",
  ]);
  assertEquals(d.incumbent.record.bills.items[2].stamp, "3월 2일");
  assertEquals(d.incumbent.record.attendance.points.map((p: { label: string }) => p.label), [
    "2월",
    "3월",
    "4월",
    "5월",
    "6월",
    "7월",
  ]);
  assertEquals(d.incumbent.record.votes.points, [{ label: "5월", value: 100 }]);
  assertEquals(d.candidates.map((c: { name: string }) => c.name), ["가상 후보 가"]);
  assertEquals(d.candidates[0].stats, []);
  for (const url of [d.source.sourceUrl, d.incumbent.record.bills.source.sourceUrl]) {
    assert(url.startsWith("https://open.assembly.go.kr/portal/data/service/"));
  }
});

Deno.test("profile: attendance/votes omitted when there is no data; bills kept", async () => {
  const { get } = await setup();
  const { res, body } = await get(`/districts/${MAPO_A}/profile`);
  assertEquals(res.status, 200);
  assertEquals(validateDistrictProfile(body.data), []);
  const record = body.data.incumbent.record;
  assert(!("attendance" in record));
  assertEquals(record.votes.points, [{ label: "5월", value: 100 }]); // 기권 is participation
  assertEquals(record.bills.items, []);
  const labels = body.data.incumbent.stats.map((s: { label: string }) => s.label);
  // No attendance; the pledge board lists only 「판정 전」 pledges, so no 공약 이행.
  assertEquals(labels, ["발의 법안"]);
  assertClean(body);
});

Deno.test("history: matches the HistoryRecord contract", async () => {
  const { get } = await setup();
  const { res, body } = await get(`/districts/${MAPO_B}/history`);
  assertEquals(res.status, 200);
  assertEquals(res.headers.get("Cache-Control"), "public, max-age=300");
  assertEquals(validateHistoryRecord(body.data), []);
  assertClean(body);
  const h = body.data;
  assertEquals(h.elections.rows.map((r: { term: number; share: number }) => [r.term, r.share]), [
    [20, 44.1],
    [21, 46.8],
    [22, 45.2],
  ]);
  assertEquals(
    h.elections.rows[1].winner.id,
    h.legislator.incumbent.id,
    "firstWinYear can find the incumbent",
  );
  assertEquals(h.elections.rows[0].winner.id.startsWith("nec-20160413-"), true);
  assert(!h.elections.rows.some((r: { ongoing?: boolean }) => r.ongoing));
  assertEquals(h.elections.source.sourceUrl, "https://www.data.go.kr/data/15000864/openapi.do");
  assertEquals(h.region.events.map((e: { year: number | null }) => e.year), [1944, null]);
  assertEquals(h.legislator.events.slice(0, 2).map((e: { mark: string }) => e.mark), [
    "2020",
    "2024",
  ]);
  assertEquals(h.legislator.events.at(-1), {
    mark: "7월",
    title: "도시공원 보전 및 이용에 관한 법률 일부개정법률안",
    detail: "7월 9일 · 접수",
  });
});

Deno.test("history: ongoing row only while counting; empty region still sourced", async () => {
  const { db } = await runPipeline();
  const tables = toTables(db);
  tables.elections = tables.elections.map((e) =>
    e.sg_id === "20280412" ? { ...e, count_status: "counting" } : e
  );
  const handler = createHandler({
    store: new MemoryStore(tables),
    fetch: fakeUpstream().fetch,
    jusoKey: "",
    vworldKey: "",
    now: () => NOW,
    ...signedOut(),
  });
  const body =
    await (await handler(new Request(`https://r/functions/v1/bff/districts/${MAPO_A}/history`)))
      .json();
  assertEquals(validateHistoryRecord(body.data), []);
  assertEquals(body.data.elections.rows.at(-1), { term: 23, year: 2028, ongoing: true });
  assertEquals(body.data.region.events, []);
  assert(body.data.region.source.sourceUrl.startsWith("https://www.data.go.kr/"));
});

Deno.test("pledges: curated board with unsourced / unevidenced items dropped", async () => {
  const { get } = await setup();
  const { res, body } = await get(`/districts/${MAPO_B}/pledges`);
  assertEquals(res.status, 200);
  assertEquals(validatePledgeBoard(body.data), []);
  assertEquals(body.data.pledges.map((p: { id: string }) => p.id), ["p1", "p2", "p5"]);
  assertEquals(body.data.pledges[2].status, "notJudged");
  assertEquals(body.data.pledges[1].judgement.steps[0].actor, "큐레이터 검토");
  assertClean(body);

  const other = await get(`/districts/${JONGNO}/pledges`);
  assertEquals(other.res.status, 404);
  assertEquals(other.body.error.code, "not_curated");
  assertEquals(validateEnvelope(other.body, true), []);
});

Deno.test("pledges: a list-only board carries no part of a verdict", async () => {
  const { get } = await setup();
  const { res, body } = await get(`/districts/${MAPO_A}/pledges`);
  assertEquals(res.status, 200);
  assertEquals(validatePledgeBoard(body.data), []);
  assertEquals(body.data.pledges.map((p: { id: string }) => p.id), ["j1", "j2"]);
  for (const p of body.data.pledges) {
    assertEquals(p.status, "notJudged");
    assert(!("judgement" in p), "no judgement on a 판정 전 pledge");
    assert(!("evidenceUrl" in p), "no evidence on a 판정 전 pledge");
  }
  assertClean(body);
});

Deno.test("profile: no 공약 이행 when nothing on the board is judged", async () => {
  const { get } = await setup();
  // MAPO_A has a curated board, but every pledge on it is 「판정 전」.
  assertEquals((await get(`/districts/${MAPO_A}/pledges`)).res.status, 200);
  const { body } = await get(`/districts/${MAPO_A}/profile`);
  assertEquals(validateDistrictProfile(body.data), []);
  const labels = body.data.incumbent.stats.map((s: { label: string }) => s.label);
  assert(!labels.includes("공약 이행"), `got ${labels}`);
});

Deno.test("address search: juso proxy mapped to districts, unmapped dropped", async () => {
  const { get, up } = await setup();
  const { res, body } = await get(`/address/search?q=${encodeURIComponent("마포구 월드컵북로")}`);
  assertEquals(res.status, 200);
  assertEquals(validateAddressSuggestions(body.data), []);
  assertClean(body);
  const got = body.data.suggestions.map((
    s: { address: string; district: { id: string } },
  ) => [s.address.split(" ").slice(1, 3).join(" "), s.district.id]);
  assertEquals(got, [
    ["마포구 월드컵북로", MAPO_B], // hemdNm 상암동
    ["마포구 신촌로", MAPO_B], // 법정동 노고산동 straddles 갑/을; hemdNm 서교동 decides
    // 신정동 without hemdNm: bridge yields 신수동(갑) and 서강동(을) → dropped
    ["마포구 성미산로", MAPO_B], // 성산동 → 성산1·2동, both 을
    ["종로구 사직로", JONGNO], // whole-시군구 district
    // 부산: no district_areas → dropped
  ]);
  assertEquals(body.data.suggestions[0].district.displayName, "서울 마포구 을");
  assert(up.requests.some((u) => u.includes("addInfoYn=Y")));
});

Deno.test("location: V-World 행정동 → district", async () => {
  const { get } = await setup();
  const { body } = await get("/location/district?lat=37.556&lng=126.901");
  assertEquals(body.data, { district: { id: MAPO_B, displayName: "서울 마포구 을" } });
  assertClean(body);
});

Deno.test("location: off any road, the 법정동 decides through the bridge", async () => {
  const parcel = (bjd: string) => () =>
    Response.json({
      response: { status: "OK", result: [{ type: "parcel", structure: { level4LC: bjd } }] },
    });
  // 망원동 → 망원1동·망원2동, both 을.
  let { get } = await setup({ "api.vworld.kr": parcel("1144012300") });
  let { body } = await get("/location/district?lat=37.556&lng=126.901");
  assertEquals(body.data, { district: { id: MAPO_B, displayName: "서울 마포구 을" } });
  // 노고산동 straddles 갑/을: no guess.
  ({ get } = await setup({ "api.vworld.kr": parcel("1144011000") }));
  ({ body } = await get("/location/district?lat=37.556&lng=126.935"));
  assertEquals(body.error.code, "no_match");
});

Deno.test("the app's own fixtures pass the validator (validator is not too strict)", async () => {
  const dir = new URL("../../../../app/assets/fixtures/", import.meta.url);
  let text: (n: string) => Promise<string>;
  try {
    await Deno.stat(dir);
    text = (n) => Deno.readTextFile(new URL(n, dir));
  } catch {
    return; // app/ not present next to server/
  }
  assertEquals(
    validateDistrictProfile(JSON.parse(await text("district_fixture-seoul-mapo-b.json"))),
    [],
  );
  assertEquals(
    validateHistoryRecord(JSON.parse(await text("history_fixture-seoul-mapo-b.json"))),
    [],
  );
  assertEquals(
    validatePledgeBoard(JSON.parse(await text("pledges_fixture-seoul-mapo-b.json"))),
    [],
  );
  assertEquals(validateAddressSuggestions(JSON.parse(await text("address_suggestions.json"))), []);
});

Deno.test("validator catches what the Dart parsers reject", () => {
  const bad = {
    district: { id: "x", displayName: "y" },
    source: { sourceUrl: "/relative", fetchedAt: "2026-01-01T00:00:00Z" },
    incumbent: {
      id: "a",
      name: "b",
      stats: [{ label: "출석률", value: { value: "92" } }],
      record: { attendance: { points: [] } },
    },
  };
  const errs = validateDistrictProfile(bad);
  assert(errs.some((e) => e.includes("sourceUrl not a URL") || e.includes("not absolute")));
  assert(errs.some((e) => e.includes("value not a number")));
  assert(errs.some((e) => e.includes("record.bills")));
  assert(errs.some((e) => e.includes("at least one point")));
  assert(
    validateHistoryRecord({
      district: {},
      region: {},
      elections: { rows: [{ term: 22, year: 2024 }] },
      legislator: {},
    }).length > 0,
  );
  assert(
    validatePledgeBoard({
      pledges: [{
        id: "1",
        title: "t",
        status: "reversed",
        source: { sourceUrl: "https://a.kr", fetchedAt: "2026-01-01" },
      }],
      source: { sourceUrl: "https://a.kr", fetchedAt: "2026-01-01" },
    }).some((e) => e.includes("evidenceUrl")),
  );
  const src = { sourceUrl: "https://a.kr", fetchedAt: "2026-01-01" };
  assert(
    validatePledgeBoard({
      pledges: [{
        id: "1",
        title: "t",
        status: "notJudged",
        evidenceUrl: "https://a.kr/e",
        source: src,
      }],
      source: src,
    }).some((e) => e.includes("notJudged")),
  );
  assert(
    validatePledgeBoard({
      pledges: [{ id: "1", title: "t", status: "kept", source: src }],
      source: src,
    }).some((e) => e.includes("unknown status")),
  );
});
