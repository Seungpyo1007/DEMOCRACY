import { assert, assertEquals, assertMatch, assertRejects, assertThrows } from "@std/assert";
import {
  assemblyOrigKey,
  districtIdFor,
  districtNameKey,
  formatDistrictDisplayName,
  isDistrictId,
  necSggCode,
  normalizeHdongName,
  sidoShortName,
  spaceSplitSuffix,
} from "./district_names.ts";
import { assemblyVoteInstant, dayStamp, kstYearMonth, monthLabel } from "./dates.ts";
import { fetchJsonWithRetry, fetchTextWithRetry, redactUrl, UpstreamError } from "./http.ts";
import { fetchAssemblyAll, parseAssemblyPage } from "./assembly.ts";
import {
  billStage,
  normalizeBill,
  normalizeMember,
  normalizePortrait,
  normalizeVote,
  redactAssemblyPayload,
} from "./normalize_assembly.ts";
import { fetchNecAll, parseNecPage } from "./nec.ts";
import {
  generalElectionTerm,
  normalizeCandidate,
  normalizeDistrict,
  normalizeElection,
  normalizeWinner,
  redactNecPersonPayload,
} from "./normalize_nec.ts";
import { parseJuso, parseVworldPlace, vworldAddressUrl } from "./geo.ts";
import { findKeyedUrls, isPresentableSourceUrl, sourceMeta, SOURCES } from "./provenance.ts";
import { sample } from "../../../testdata/fake_upstream.ts";

const AT = "2026-09-24T03:00:00.000Z";
const noSleep = () => Promise.resolve();

// ------------------------------------------------------------ district names

Deno.test("display name: 시도 short name + spaced split suffix", () => {
  assertEquals(formatDistrictDisplayName("서울특별시", "마포구을"), "서울 마포구 을");
  assertEquals(formatDistrictDisplayName("서울특별시", "종로구"), "서울 종로구");
  assertEquals(formatDistrictDisplayName("대구광역시", "동구군위군을"), "대구 동구군위군 을");
  assertEquals(formatDistrictDisplayName("경기도", "용인시정"), "경기 용인시 정");
  assertEquals(
    formatDistrictDisplayName("강원특별자치도", "춘천시철원군화천군양구군갑"),
    "강원 춘천시철원군화천군양구군 갑",
  );
  assertEquals(formatDistrictDisplayName("세종특별자치시", "세종시을"), "세종 세종시 을");
  assertEquals(formatDistrictDisplayName("제주특별자치도", "서귀포시"), "제주 서귀포시");
  // Unknown 시도 passes through.
  assertEquals(sidoShortName("전남광주통합특별시"), "전남광주통합특별시");
  // Idempotent on already-spaced names.
  assertEquals(spaceSplitSuffix("마포구 을"), "마포구 을");
});

Deno.test("name keys join NEC names and Assembly ORIG_NM", () => {
  assertEquals(districtNameKey("서울특별시", "마포구을"), "서울마포구을");
  assertEquals(assemblyOrigKey("서울 마포구을"), "서울마포구을");
  assertEquals(assemblyOrigKey("대구 동구군위군을"), districtNameKey("대구광역시", "동구군위군을"));
  // 세종 is a single token in ORIG_NM; NEC keeps the 시도 name in the 선거구.
  assertEquals(
    assemblyOrigKey("세종특별자치시을"),
    districtNameKey("세종특별자치시", "세종특별자치시을"),
  );
  // The merged 시도 maps back to the 22대 선거구 it came from.
  assertEquals(
    assemblyOrigKey("전남광주통합특별시 광산구갑"),
    districtNameKey("광주광역시", "광산구갑"),
  );
  assertEquals(
    assemblyOrigKey("전남광주통합특별시 동구남구을"),
    districtNameKey("광주광역시", "동구남구을"),
  );
  assertEquals(
    assemblyOrigKey("전남광주통합특별시 순천시광양시곡성군구례군갑"),
    districtNameKey("전라남도", "순천시광양시곡성군구례군갑"),
  );
  assertEquals(
    assemblyOrigKey("전남광주통합특별시 목포시"),
    districtNameKey("전라남도", "목포시"),
  );
  assertEquals(assemblyOrigKey("비례대표"), null);
  assertEquals(assemblyOrigKey(null), null);
});

Deno.test("district id is deterministic nec-<8 hex> and distinct per district", () => {
  const b = necSggCode("서울특별시", "마포구을");
  assertMatch(b, /^[0-9a-f]{8}$/);
  assertEquals(necSggCode("서울특별시", "마포구 을"), b);
  assert(necSggCode("서울특별시", "마포구갑") !== b);
  assert(necSggCode("부산광역시", "중구영도구") !== necSggCode("서울특별시", "중구성동구갑"));
  assert(isDistrictId(districtIdFor(b)));
  assert(!isDistrictId("fixture-seoul-mapo-b"));
  assert(!isDistrictId("nec-../../etc"));
});

Deno.test("행정동 names normalise 제N동", () => {
  assertEquals(normalizeHdongName("망원제1동"), normalizeHdongName("망원1동"));
});

Deno.test("dates", () => {
  assertEquals(dayStamp("2026-05-12"), "5월 12일");
  assertEquals(monthLabel("2026-03"), "3월");
  assertEquals(assemblyVoteInstant("20260917 155315"), "2026-09-17T06:53:15.000Z");
  assertEquals(kstYearMonth(new Date("2026-05-31T16:00:00Z")), "2026-06"); // KST midnight rollover
});

// ------------------------------------------------------------ http

Deno.test("retries 5xx with backoff then succeeds", async () => {
  let calls = 0;
  const delays: number[] = [];
  const body = await fetchTextWithRetry(
    () => {
      calls++;
      return Promise.resolve(calls < 3 ? new Response("x", { status: 503 }) : new Response("ok"));
    },
    "https://example.com/?KEY=secret",
    { retries: 3, baseDelayMs: 100, sleep: (ms) => (delays.push(ms), Promise.resolve()) },
  );
  assertEquals(body, "ok");
  assertEquals(delays, [100, 200]);
});

Deno.test("retries network errors, not 4xx; errors never carry the key", async () => {
  let calls = 0;
  const err = await assertRejects(
    () =>
      fetchTextWithRetry(
        () => {
          calls++;
          return Promise.resolve(new Response("no", { status: 401 }));
        },
        "https://example.com/x?ServiceKey=SECRET",
        { sleep: noSleep },
      ),
    UpstreamError,
  );
  assertEquals(calls, 1);
  assert(!err.message.includes("SECRET"));

  calls = 0;
  await assertRejects(
    () =>
      fetchTextWithRetry(
        () => {
          calls++;
          return Promise.reject(new TypeError("connection reset"));
        },
        "https://example.com/",
        { retries: 2, sleep: noSleep },
      ),
    UpstreamError,
  );
  assertEquals(calls, 3);
  assert(!redactUrl("https://x.kr/a?confmKey=abc&q=1").includes("abc"));
});

Deno.test("data.go.kr XML gateway errors surface their reason code", async () => {
  const err = await assertRejects(
    () =>
      fetchJsonWithRetry(
        () => Promise.resolve(new Response(sample("nec_gateway_error.xml"))),
        "https://apis.data.go.kr/x",
        { sleep: noSleep },
      ),
    UpstreamError,
  );
  assertMatch(err.message, /30 SERVICE_KEY_IS_NOT_REGISTERED_ERROR/);
});

// ------------------------------------------------------------ assembly

Deno.test("assembly page parsing: rows, INFO-200 and errors", () => {
  const page = parseAssemblyPage("nwvrqwxyaytdsfvhu", JSON.parse(sample("assembly_members.json")));
  assertEquals(page.total, 3);
  assertEquals(page.rows.length, 3);
  assertEquals(parseAssemblyPage("x", JSON.parse(sample("assembly_info200.json"))), {
    rows: [],
    total: 0,
  });
  assertThrows(
    () => parseAssemblyPage("x", JSON.parse(sample("assembly_error300.json"))),
    UpstreamError,
    "ERROR-300",
  );
});

Deno.test("assembly pagination follows list_total_count", async () => {
  const pages: number[] = [];
  const rows = await fetchAssemblyAll("svc", { AGE: "22" }, {
    key: "K",
    pageSize: 2,
    fetch: (input) => {
      const p = Number(new URL(String(input)).searchParams.get("pIndex"));
      pages.push(p);
      const row = (i: number) => ({ BILL_ID: `B${i}` });
      const data = p === 1 ? [row(1), row(2)] : p === 2 ? [row(3), row(4)] : [row(5)];
      return Promise.resolve(
        Response.json({
          svc: [{ head: [{ list_total_count: 5 }, { RESULT: { CODE: "INFO-000" } }] }, {
            row: data,
          }],
        }),
      );
    },
  });
  assertEquals(rows.length, 5);
  assertEquals(pages, [1, 2, 3]);
});

Deno.test("assembly normalizers", () => {
  const m = normalizeMember(
    parseAssemblyPage("nwvrqwxyaytdsfvhu", JSON.parse(sample("assembly_members.json"))).rows[0],
    AT,
  )!;
  assertEquals(m.mona_cd, "FAKE0001");
  assertEquals(m.district_key, "서울마포구을");
  assertEquals(m.reele_gbn, "재선");
  assertEquals(m.source_url, SOURCES.assemblyMembers.url);
  assert(!("BTH_DATE" in m) && !JSON.stringify(m).includes("1970-01-01"));

  const pics =
    parseAssemblyPage("ALLNAMEMBER", JSON.parse(sample("assembly_allmembers.json"))).rows;
  assertEquals(
    normalizePortrait(pics[0])?.photo_url,
    "https://www.assembly.go.kr/static/portal/img/openassm/new/fake0001.jpg",
  );
  assertEquals(normalizePortrait(pics[1]), null, "non-assembly hosts are not linked");

  const bills = parseAssemblyPage("nzmimeepazxkubdpn", JSON.parse(sample("assembly_bills.json")))
    .rows.map((r) => normalizeBill(r, AT)!);
  assertEquals(bills[0].rst_mona_cd, "FAKE0001");
  assertEquals(billStage(bills[0]), "원안가결");
  assertEquals(billStage(bills[1]), "위원회 심사");
  assertEquals(billStage(bills[2]), "접수");

  const v = normalizeVote(
    parseAssemblyPage("nojepdqqaweusdfbi", JSON.parse(sample("assembly_votes.json"))).rows[1],
    AT,
  )!;
  assertEquals(v.result, "불참");
  assertEquals(
    normalizeVote(
      { BILL_ID: "b", MONA_CD: "m", RESULT_VOTE_MOD: "모름", VOTE_DATE: "20260101" },
      AT,
    ),
    null,
  );
});

Deno.test("raw member payloads drop staff names and birth dates", () => {
  const redacted = JSON.stringify(
    redactAssemblyPayload("nwvrqwxyaytdsfvhu", JSON.parse(sample("assembly_members.json"))),
  );
  for (const f of ["BTH_DATE", "STAFF", "SECRETARY", "가상 보좌관"]) {
    assert(!redacted.includes(f), f);
  }
  assert(redacted.includes("가상 의원"));
});

// ------------------------------------------------------------ NEC

Deno.test("nec parsing: list, single object, no data", () => {
  assertEquals(parseNecPage("op", JSON.parse(sample("nec_sgg_codes.json"))).items.length, 4);
  const single = parseNecPage("op", JSON.parse(sample("nec_winners_20200415.json")));
  assertEquals(single.items.length, 1);
  assertEquals(parseNecPage("op", JSON.parse(sample("nec_nodata.json"))), { items: [], total: 0 });
  assertThrows(
    () => parseNecPage("op", { response: { header: { resultCode: "INFO-99", resultMsg: "bad" } } }),
    UpstreamError,
  );
});

Deno.test("nec pagination stops at totalCount", async () => {
  let calls = 0;
  const items = await fetchNecAll("op", {}, {
    serviceKey: "K",
    numOfRows: 2,
    fetch: () => {
      calls++;
      const item = calls === 1 ? [{ a: 1 }, { a: 2 }] : { a: 3 };
      return Promise.resolve(
        Response.json({
          response: { header: { resultCode: "INFO-00" }, body: { items: { item }, totalCount: 3 } },
        }),
      );
    },
  });
  assertEquals(items.length, 3);
  assertEquals(calls, 2);
});

Deno.test("nec normalizers", () => {
  const [sg20, , sg22, sg22prop, sg23] = parseNecPage("op", JSON.parse(sample("nec_sg_codes.json")))
    .items.map((i) => normalizeElection(i, AT)!);
  assertEquals([sg20.term, sg22.term, sg23.term, sg22prop.term], [20, 22, 23, null]);
  assertEquals(sg22.vote_date, "2024-04-10");
  assertEquals(generalElectionTerm("20200415", ""), 21);

  const d = parseNecPage("op", JSON.parse(sample("nec_sgg_codes.json"))).items.map((i) =>
    normalizeDistrict(i, AT)!
  );
  const mapoB = d.find((x) => x.sgg_name === "마포구을")!;
  assertEquals(mapoB.display_name, "서울 마포구 을");
  assertEquals(mapoB.id, districtIdFor(necSggCode("서울특별시", "마포구을")));
  assertEquals(mapoB.name_key, "서울마포구을");

  const w = normalizeWinner(
    parseNecPage("op", JSON.parse(sample("nec_winners_20240410.json"))).items[0],
    AT,
  )!;
  assertEquals([w.share, w.votes, w.party], [45.2, 61234, "가나당"]);

  const c = normalizeCandidate(
    parseNecPage("op", JSON.parse(sample("nec_candidates_single.json"))).items[0],
    "final",
    AT,
  )!;
  const keys = Object.keys(c);
  for (const banned of ["addr", "birthday", "age", "gender", "edu", "job", "hanjaName"]) {
    assert(!keys.includes(banned), banned);
  }
  assertEquals(c.status, "등록");
});

Deno.test("raw NEC person payloads keep no address or birth date", () => {
  const red = JSON.stringify(
    redactNecPersonPayload(JSON.parse(sample("nec_winners_20240410.json"))),
  );
  for (const f of ["addr", "birthday", '"age"', "가상대학교", "19700101"]) {
    assert(!red.includes(f), f);
  }
  assert(red.includes("dugyul"));
  const single = redactNecPersonPayload(JSON.parse(sample("nec_candidates_single.json")));
  assert(!JSON.stringify(single).includes("addr"));
});

// ------------------------------------------------------------ geo

Deno.test("juso parsing", () => {
  const list = parseJuso(JSON.parse(sample("juso_search.json")));
  assertEquals(list.length, 6);
  assertEquals(list[0].admCd, "1144012700");
  assertEquals(list[1].hemdNm, "서교동");
  assertEquals(list[2].hemdNm, null);
  assertEquals(parseJuso({ results: { common: { errorCode: "E0006" }, juso: null } }), []);
  assertThrows(() => parseJuso({ results: { common: { errorCode: "E0001" } } }), UpstreamError);
});

Deno.test("V-World parsing takes the road entry's 행정동 and the parcel's 법정동", () => {
  assertEquals(parseVworldPlace(JSON.parse(sample("vworld_address.json"))), {
    hdongCode: "1144069000",
    hdongName: "망원제1동",
    bjdCode: "1144012300",
  });
  // Off any road: 법정동 only, left to the bridge.
  assertEquals(
    parseVworldPlace({
      response: {
        status: "OK",
        result: [{ type: "parcel", structure: { level4LC: "1144012300" } }],
      },
    }),
    { hdongCode: null, hdongName: null, bjdCode: "1144012300" },
  );
  assertEquals(parseVworldPlace({ response: { status: "NOT_FOUND" } }), null);
  assertThrows(
    () => parseVworldPlace({ response: { status: "ERROR", error: { code: "INVALID_KEY" } } }),
    UpstreamError,
    "INVALID_KEY",
  );
  const url = new URL(vworldAddressUrl("K", 37.5, 126.9, "https://example.org"));
  assertEquals(url.searchParams.get("point"), "126.9,37.5"); // x = lng first
  assertEquals(url.searchParams.get("domain"), "https://example.org");
});

// ------------------------------------------------------------ provenance

Deno.test("provenance helpers reject keyed or relative URLs", () => {
  assert(isPresentableSourceUrl(SOURCES.necWinners.url));
  assert(!isPresentableSourceUrl("https://apis.data.go.kr/x?ServiceKey=abc"));
  assert(!isPresentableSourceUrl("/relative"));
  assertEquals(sourceMeta("https://a.kr", "not a date"), null);
  assertEquals(findKeyedUrls({ a: ["https://x?KEY=1", { b: "https://y?confmKey=2" }] }).length, 2);
  for (const s of Object.values(SOURCES)) assert(isPresentableSourceUrl(s.url));
});
