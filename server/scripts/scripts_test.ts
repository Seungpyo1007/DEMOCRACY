import {
  assert,
  assertEquals,
  assertMatch,
  assertRejects,
  assertStringIncludes,
  assertThrows,
} from "@std/assert";
import { districtAreasToSql, parseDistrictAreas } from "./import_district_areas.ts";
import { bridgeToSql, parseBridge } from "./import_bjdong_hdong.ts";
import {
  bridgeCsv,
  buildDistrictAreas,
  lawTableFromJson,
  parseKikH,
  parseKikMix,
  parseLawTable,
} from "./build_district_areas.ts";
import { attendanceHeader, attendanceToSql, parseAttendance } from "./import_attendance.ts";
import {
  ATTENDANCE_SOURCE_URL,
  holdsEveryExactMatch,
  type MemberCandidate,
  parseAttendanceSheet,
  resolveMonaCodes,
  sessionCsv,
} from "./fetch_attendance.ts";
import { readFirstSheet } from "./lib/xlsx.ts";
import { resultsToSql } from "./import_historical_results.ts";
import { geojsonToSql } from "./import_geojson.ts";
import { pledgesToSql, regionToSql } from "./import_curated.ts";
import { parseCsv, parseCsvObjects } from "./lib/csv.ts";
import { lit, requireHttpUrl } from "./lib/sql.ts";
import { sample } from "../testdata/fake_upstream.ts";
import { MAPO_A, MAPO_B } from "../testdata/pipeline.ts";
import { districtIdFor, necSggCode } from "../supabase/functions/_shared/district_names.ts";

const opts = {
  sourceUrl: "https://www.law.go.kr/법령/공직선거법",
  fetchedAt: "2026-09-24T00:00:00.000Z",
};

Deno.test("csv parser handles quotes, CRLF, BOM and comments", () => {
  assertEquals(parseCsv('﻿# c\r\na,b\r\n"x, y","he said ""hi"""\r\n'), [["a", "b"], [
    "x, y",
    'he said "hi"',
  ]]);
});

Deno.test("sql literals escape quotes", () => {
  assertEquals(lit("O'Neil"), "'O''Neil'");
  assertEquals(lit(null), "null");
  assertEquals(lit(["a"]), "array['a']::text[]");
  assertThrows(() => requireHttpUrl("https://apis.data.go.kr/x?ServiceKey=1", "--source-url"));
});

Deno.test("district areas: sample → rows for 마포 갑/을 and 종로", () => {
  const { rows, districts } = parseDistrictAreas(sample("district_areas_sample.csv"), opts);
  assertEquals(rows.length, 17);
  assertEquals(
    [...districts.keys()].sort(),
    [MAPO_A, MAPO_B, [...districts.keys()].find((k) => k !== MAPO_A && k !== MAPO_B)].sort(),
  );
  assertEquals(rows.filter((r) => r.sgg_code === MAPO_B.slice(4)).length, 9);
  assertEquals(rows.find((r) => r.sigungu_code === "11110")!.hdong_code, "11110");
  const { sql } = districtAreasToSql(sample("district_areas_sample.csv"), opts);
  assertStringIncludes(sql, "on conflict (election_sg_id, hdong_code) do update set");
});

Deno.test("district areas: invalid input is rejected with line numbers", () => {
  const head = "election_sg_id,sd_name,sgg_name,sigungu_code,hdong_code,hdong_name\n";
  assertThrows(
    () => parseDistrictAreas(head + "20240410,서울특별시,마포구갑,11440,1111053000,x\n", opts),
    Error,
    "line 2",
  );
  assertThrows(
    () =>
      parseDistrictAreas(
        head +
          "20240410,서울특별시,마포구갑,11440,,\n20240410,서울특별시,마포구을,11440,1144066000,서교동\n",
        opts,
      ),
    Error,
    "mixes",
  );
});

Deno.test("bridge: simple CSV and KIKmix headers; 말소 rows skipped", () => {
  assertEquals(parseBridge(sample("bjdong_hdong_sample.csv"), opts).length, 40);
  const kik = "행정동코드,시도명,시군구명,읍면동명,법정동코드,동리명,생성일자,말소일자\n" +
    "1144069000,서울특별시,마포구,망원1동,1144012300,망원동,20080101,\n" +
    "1144090800,서울특별시,마포구,망원1동,1144012300,망원동,19000101,20080101\n";
  const rows = parseBridge(kik, opts);
  assertEquals(rows.length, 1);
  assertEquals(rows[0].hdong_name, "망원1동");
  assertStringIncludes(bridgeToSql(kik, opts), "insert into public.bjdong_hdong");
});

const bytes = (name: string) => Deno.readFileSync(new URL(`../testdata/${name}`, import.meta.url));

Deno.test("build district areas: 구역표 text parses, wrapped lines and all", () => {
  const law = parseLawTable(sample("byeolpyo1_sample.txt"));
  assertEquals(law.map((d) => `${d.sido} ${d.name}`), [
    "서울특별시 종로구",
    "서울특별시 마포구갑",
    "서울특별시 마포구을",
    "광주광역시 서구갑",
    "광주광역시 서구을",
    "전라남도 여수시갑",
  ]);
  assertEquals(law[2].area, "서교동, 망원제1동");
  const json = {
    법령: { 별표: { 별표단위: [{ 별표제목: "국회의원지역선거구구역표", 별표내용: [["a"]] }] } },
  };
  assertEquals(lawTableFromJson(json), "a");
});

Deno.test("build district areas: carried to today's codes, then imported", () => {
  const codes = parseKikH(bytes("kikcd_h_sample.cp949"));
  const mix = parseKikMix(bytes("kikmix_sample.cp949"));
  assertEquals(codes[8].sido, "전남광주통합특별시");
  const { csv, problems, stats } = buildDistrictAreas({
    law: parseLawTable(sample("byeolpyo1_sample.txt")),
    codes,
    mix,
    election: "20240410",
  });
  assertEquals(problems, []);
  // 광주 re-coded by name; 새솔동 (2025) by the 합정동 it took from 서교동; 출장소 with 돌산읍.
  assertEquals(stats, {
    "same code": 5,
    "same name": 4,
    "법정동 overlap": 1,
    "whole-시군구 rows": 2,
    "행정동 rows": 7,
    "선거구": 6,
  });
  const lines = csv.trim().split("\n");
  assert(lines.includes("20240410,서울특별시,종로구,11110,,"));
  assert(lines.includes("20240410,서울특별시,마포구을,11440,1144071000,새솔동"));
  assert(lines.includes("20240410,광주광역시,서구갑,12240,1224074500,치평동"));
  assert(lines.includes("20240410,전라남도,여수시갑,12810,,"));
  assertEquals(parseDistrictAreas(csv, opts).districts.size, 6);
});

Deno.test("build district areas: a 행정동 straddling 선거구 fails the run", () => {
  const mix = parseKikMix(bytes("kikmix_sample.cp949"));
  const straddle = { ...mix[1], code: "1144055500", emd: "공덕동", bjd: "1144012100" };
  const { problems } = buildDistrictAreas({
    law: parseLawTable(sample("byeolpyo1_sample.txt")),
    codes: parseKikH(bytes("kikcd_h_sample.cp949")),
    mix: [...mix, { ...straddle, born: "19880423", dead: "" }],
    election: "20240410",
  });
  assertEquals(problems, [
    "1144071000 서울특별시 마포구 새솔동: spans 서울특별시|마포구갑, 서울특별시|마포구을",
  ]);
});

Deno.test("build district areas: bridge keeps today's pairs only", () => {
  const csv = bridgeCsv(parseKikMix(bytes("kikmix_sample.cp949")));
  assertEquals(parseBridge(csv, opts).map((r) => `${r.bjd_code}>${r.hdong_code}`), [
    "1144012000>1144066000",
    "1144012100>1144071000",
    "1224012000>1224074500",
  ]);
});

Deno.test("attendance / historical results importers", () => {
  assertStringIncludes(attendanceToSql(sample("attendance_sample.csv"), opts), "'FAKE0001'");
  assertThrows(
    () => attendanceToSql("mona_cd,meeting_date,meeting_label,status\nX,2026/01/01,a,출석\n", opts),
    Error,
    "meeting_date",
  );
  const sql = resultsToSql(
    'sg_id,sd_name,sgg_name,huboid,name,party,votes,share,is_winner\n20160413,서울특별시,마포구을,,가상 인물,다라당,"52,011",44.1,당선\n',
    opts,
  );
  assertStringIncludes(sql, "'서울마포구을'");
  assertStringIncludes(sql, "52011");
  assertStringIncludes(sql, "'file-20160413-서울특별시-마포구을-가상 인물'");
});

Deno.test("geojson importer requires a license and matches by name key", () => {
  const fc = {
    type: "FeatureCollection",
    features: [
      {
        type: "Feature",
        properties: { SIDO: "서울", SGG: "마포구을" },
        geometry: { type: "Point", coordinates: [126.9, 37.55] },
      },
      {
        type: "Feature",
        properties: { SIDO: "서울", SGG: "없는구" },
        geometry: { type: "Point", coordinates: [0, 0] },
      },
    ],
  };
  const base = {
    sdProp: "SIDO",
    sggProp: "SGG",
    idByKey: new Map([["서울마포구을", MAPO_B]]),
    sourceUrl: "https://github.com/OhmyNews/2024_22_elec_map",
    fetchedAt: opts.fetchedAt,
  };
  assertThrows(() => geojsonToSql(fc, { ...base, license: "" }), Error, "license");
  const { sql, unmatched } = geojsonToSql(fc, { ...base, license: "TBD" });
  assertEquals(unmatched, ["서울 없는구"]);
  assertStringIncludes(sql, MAPO_B);
});

Deno.test("curated pledges / region importers enforce sources and evidence", () => {
  const src = { sourceUrl: "https://policy.nec.go.kr/x", fetchedAt: "2026-09-24T00:00:00Z" };
  const sql = pledgesToSql({
    districtId: MAPO_B,
    source: src,
    pledges: [{
      id: "p1",
      title: "t",
      category: "교통",
      status: "fulfilled",
      source: src,
      billIds: ["PRC_1"],
    }],
  });
  assertMatch(sql, /^begin;/);
  assertStringIncludes(sql, "array['PRC_1']::text[]");
  assertThrows(
    () =>
      pledgesToSql({
        districtId: MAPO_B,
        source: src,
        pledges: [{ id: "p", title: "t", status: "reversed", source: src }],
      }),
    Error,
    "evidenceUrl",
  );
  assertThrows(
    () =>
      pledgesToSql({
        districtId: MAPO_B,
        source: src,
        pledges: [{ id: "p", title: "t", status: "fulfilled" }],
      }),
    Error,
    "source",
  );
  // 「판정 전」: accepted plain, with the publisher named rather than the host…
  const listed = pledgesToSql({
    districtId: MAPO_B,
    source: { ...src, publisher: "중앙선거관리위원회" },
    pledges: [{ id: "n1", title: "t", category: "", status: "notJudged", source: src }],
  });
  assertStringIncludes(listed, "'notJudged'");
  assertStringIncludes(listed, "'중앙선거관리위원회'");
  // …and refused with any part of a verdict attached.
  for (
    const extra of [
      { evidenceUrl: "https://policy.nec.go.kr/e" },
      {
        judgement: {
          steps: [{ actor: "큐레이터", detail: "", stamp: "" }],
          source: src,
        },
      },
      { billIds: ["PRC_1"] },
    ]
  ) {
    assertThrows(
      () =>
        pledgesToSql({
          districtId: MAPO_B,
          source: src,
          pledges: [{ id: "n", title: "t", status: "notJudged", source: src, ...extra }],
        }),
      Error,
      "notJudged",
    );
  }
  assertThrows(
    () =>
      pledgesToSql({
        districtId: MAPO_B,
        source: { ...src, publisher: " " },
        pledges: [{ id: "n", title: "t", status: "notJudged", source: src }],
      }),
    Error,
    "publisher",
  );
  assertThrows(
    () => pledgesToSql({ districtId: "fixture-x", source: src, pledges: [] }),
    Error,
    "districtId",
  );
  const r = regionToSql({
    districtId: MAPO_B,
    source: src,
    events: [{ year: null, title: "a" }, { year: 1944, title: "b" }],
  });
  assertStringIncludes(r, "insert into public.region_events");
  assert(!r.includes("on conflict ()"));
  assertThrows(
    () => regionToSql({ districtId: MAPO_B, source: src, events: [{ year: "1944", title: "x" }] }),
    Error,
    "year",
  );
});

Deno.test("22대 pilot pledge lists: 선거공보 only, nothing judged, importable", async () => {
  const dir = new URL("../data/pledges_22/", import.meta.url);
  const expected: Record<string, [string, string]> = {
    "seoul-mapo-b.json": ["서울특별시", "마포구을"],
    "seoul-yeongdeungpo-a.json": ["서울특별시", "영등포구갑"],
    "seoul-jongno.json": ["서울특별시", "종로구"],
    "gwangju-seo-a.json": ["광주광역시", "서구갑"],
    "gyeonggi-hwaseong-d.json": ["경기도", "화성시정"],
  };
  const seen = new Set<string>();
  const ids = new Set<string>();
  for await (const entry of Deno.readDir(dir)) {
    if (!entry.name.endsWith(".json")) continue;
    seen.add(entry.name);
    const doc = JSON.parse(await Deno.readTextFile(new URL(entry.name, dir)));
    const [sd, sgg] = expected[entry.name] ?? [];
    assert(sd, `unexpected file ${entry.name}`);
    assertEquals(doc.districtId, districtIdFor(necSggCode(sd, sgg)), entry.name);
    const pdf = doc.source.sourceUrl as string;
    assertMatch(pdf, /^https:\/\/policy\.nec\.go\.kr\/policy_pdf\/20240410\/.+\.pdf$/);
    assertEquals(doc.source.publisher, "중앙선거관리위원회");
    for (const p of doc.pledges) {
      assert(!ids.has(p.id), `duplicate id ${p.id}`);
      ids.add(p.id);
      assertEquals(p.status, "notJudged", p.id);
      assertEquals(p.source.sourceUrl, pdf, p.id);
      for (const k of ["judgement", "evidenceUrl", "billIds"]) assert(!(k in p), `${p.id}.${k}`);
      assertEquals(p.title, p.title.trim(), p.id);
    }
    const sql = pledgesToSql(doc);
    assert(!/'(fulfilled|inProgress|unfulfilled|reversed)'/.test(sql), entry.name);
  }
  assertEquals([...seen].sort(), Object.keys(expected).sort());
});

// ------------------------------------------------------------------ 본회의 출결 xlsx

/** A zip with one stored entry per file, or deflated ones when `deflate` is set. */
async function zipOf(files: Record<string, string>, deflate = false): Promise<Uint8Array> {
  const enc = new TextEncoder();
  const locals: Uint8Array[] = [];
  const centrals: Uint8Array[] = [];
  let offset = 0;
  for (const [name, text] of Object.entries(files)) {
    const raw = enc.encode(text);
    const data = deflate
      ? new Uint8Array(
        await new Response(
          new Blob([raw]).stream().pipeThrough(new CompressionStream("deflate-raw")),
        ).arrayBuffer(),
      )
      : raw;
    const n = enc.encode(name);
    const local = new Uint8Array(30 + n.length + data.length);
    const lv = new DataView(local.buffer);
    lv.setUint32(0, 0x04034b50, true);
    lv.setUint16(8, deflate ? 8 : 0, true);
    lv.setUint32(18, data.length, true);
    lv.setUint32(22, raw.length, true);
    lv.setUint16(26, n.length, true);
    local.set(n, 30);
    local.set(data, 30 + n.length);
    const central = new Uint8Array(46 + n.length);
    const cv = new DataView(central.buffer);
    cv.setUint32(0, 0x02014b50, true);
    cv.setUint16(10, deflate ? 8 : 0, true);
    cv.setUint32(20, data.length, true);
    cv.setUint32(24, raw.length, true);
    cv.setUint16(28, n.length, true);
    cv.setUint32(42, offset, true);
    central.set(n, 46);
    locals.push(local);
    centrals.push(central);
    offset += local.length;
  }
  const cdSize = centrals.reduce((s, c) => s + c.length, 0);
  const eocd = new Uint8Array(22);
  const ev = new DataView(eocd.buffer);
  ev.setUint32(0, 0x06054b50, true);
  ev.setUint16(8, centrals.length, true);
  ev.setUint16(10, centrals.length, true);
  ev.setUint32(12, cdSize, true);
  ev.setUint32(16, offset, true);
  const out = new Uint8Array(offset + cdSize + 22);
  let p = 0;
  for (const part of [...locals, ...centrals, eocd]) {
    out.set(part, p);
    p += part.length;
  }
  return out;
}

Deno.test("xlsx reader: shared, inline and numeric cells, stored or deflated", async () => {
  const files = {
    "xl/sharedStrings.xml":
      '<sst><si><t>의원명</t></si><si><r><t>A&amp;</t></r><r><t xml:space="preserve">B</t></r></si></sst>',
    "xl/worksheets/sheet1.xml": '<worksheet><sheetData><row r="1"><c r="A1" t="s"><v>0</v></c>' +
      '<c r="C1" t="inlineStr"><is><t>&#51649;</t></is></c></row><row r="2"/>' +
      '<row r="3"><c r="B3" t="s"><v>1</v></c><c r="C3"><v>2</v></c><c r="D3"/></row>' +
      "</sheetData></worksheet>",
  };
  for (const deflate of [false, true]) {
    assertEquals(await readFirstSheet(await zipOf(files, deflate)), [
      ["의원명", "", "직"],
      [],
      ["", "A&B", "2"],
    ]);
  }
  await assertRejects(() => readFirstSheet(new Uint8Array(40)), Error, "not a zip");
});

/** A 회기 file as the Assembly lays it out (see fetch_attendance.ts). */
function attendanceRows(members: string[][]): string[][] {
  return [
    ["구분", "구분", "438회(임시)", "438회(임시)", "438회(임시)", "", "", "", "", "", "총 계"],
    [
      "의원명",
      "소속정당",
      "1차(본회의)",
      "2차(본회의)",
      "회의일수",
      "출석",
      "결석",
      "청가",
      "출장",
      "결석신고서",
    ],
    ["의원명", "소속정당", "(2026년08월20일)", "(2026년08월26일)", "회의일수"],
    ...members,
    ["", "", "", "", "", "", "", "", "", "", "0"],
  ];
}

Deno.test("attendance sheet: sittings, 차수 labels, '-' as not seated, self-check", () => {
  const sheet = parseAttendanceSheet(attendanceRows([
    ["가나다", "가당", "출석", "결석신고서", "2", "1", "0", "0", "0", "1", "119", "비고"],
    ["라마바", "나당", "-", "청가", "1", "0", "0", "1", "0", "0"],
  ]));
  assertEquals(sheet.session, 438);
  assertEquals(sheet.sittings, [
    { label: "제438회 제1차", date: "2026-08-20" },
    { label: "제438회 제2차", date: "2026-08-26" },
  ]);
  assertEquals(sheet.members[1], { name: "라마바", statuses: [null, "청가"] });

  assertThrows(
    () =>
      parseAttendanceSheet(attendanceRows([
        ["가나다", "가당", "출석", "출장", "2", "2", "0", "0", "0", "0"],
      ])),
    Error,
    "cells give 2/1/0/0/1/0 but the file says 2/2/0/0/0/0",
  );
  assertThrows(
    () =>
      parseAttendanceSheet(attendanceRows([
        ["가나다", "가당", "출석", "지각", "2", "1", "0", "0", "0", "0"],
      ])),
    Error,
    "unknown status 지각",
  );
  const moved = attendanceRows([]);
  moved[1][6] = "청가";
  assertThrows(() => parseAttendanceSheet(moved), Error, "count columns changed");
});

Deno.test("attendance names: 22대 only, 한자 twin told apart as the source does", async () => {
  const rows: Record<string, MemberCandidate[]> = {
    박지원: [
      { code: "H7X3372O", name: "박지원", hanja: "朴芝源", terms: "제22대" },
      { code: "KFX3165F", name: "박지원", hanja: "朴志遠", terms: "제13대" },
      { code: "8BF5855P", name: "박지원", hanja: "朴智元", terms: "제20대, 제22대" },
    ],
    김윤: [
      { code: "5N65159P", name: "김윤", hanja: "金輪", terms: "제22대" },
      { code: "JZY9937U", name: "김윤덕", hanja: "金潤德", terms: "제21대, 제22대" },
    ],
    동명: [
      { code: "A", name: "동명", hanja: "同名", terms: "제22대" },
      { code: "B", name: "동명", hanja: "洞明", terms: "제22대" },
    ],
  };
  const lookup = (n: string) => Promise.resolve(rows[n] ?? []);
  const codes = await resolveMonaCodes(["박지원", "朴芝源", "김윤", "박지원"], lookup);
  assertEquals(Object.fromEntries(codes), {
    박지원: "8BF5855P",
    朴芝源: "H7X3372O",
    김윤: "5N65159P",
  });
  await assertRejects(() => resolveMonaCodes(["동명"], lookup), Error, "동명: ambiguous A/B");
  await assertRejects(() => resolveMonaCodes(["없음"], lookup), Error, "없음: no 22대 member");

  // The keyless sample key stops at 5 rows; that is still complete once a longer name shows.
  assert(holdsEveryExactMatch("김윤", rows.김윤));
  assert(!holdsEveryExactMatch("동명", rows.동명));
});

Deno.test("attendance CSV: written per 회기, read back by the importer with its header", () => {
  const sheet = parseAttendanceSheet(attendanceRows([
    ["라마바", "나당", "-", "청가", "1", "0", "0", "1", "0", "0"],
    ["가나다", "가당", "출석", "결석신고서", "2", "1", "0", "0", "0", "1"],
  ]));
  const csv = sessionCsv(sheet, new Map([["가나다", "AAA111"], ["라마바", "BBB222"]]), {
    fileName: "제438회국회(임시회) 본회의 출결현황",
    fileSeq: 10001952,
    postedAt: "2026-08-31",
    fetchedAt: "2026-09-28",
  });
  assertEquals(csv.split("\n").filter((l) => l && !l.startsWith("#")), [
    "mona_cd,member_name,meeting_date,meeting_label,status",
    "AAA111,가나다,2026-08-20,제438회 제1차,출석",
    "AAA111,가나다,2026-08-26,제438회 제2차,결석신고서",
    "BBB222,라마바,2026-08-26,제438회 제2차,청가",
  ]);
  const header = attendanceHeader(csv);
  assertEquals(header, { sourceUrl: ATTENDANCE_SOURCE_URL, fetchedAt: "2026-09-28" });
  const rows = parseAttendance(csv, { sourceUrl: header.sourceUrl!, fetchedAt: "2026-09-28" });
  assertEquals(rows.length, 3);
  assertEquals(rows[1].status, "결석신고서");
  assertThrows(
    () => parseAttendance("mona_cd,meeting_date,meeting_label,status\nX,2026-01-01,a,지각\n", opts),
    Error,
    "status 지각",
  );
});

Deno.test("committed 22대 attendance files load and keep one code per name", async () => {
  const byCode = new Map<string, string>();
  let rows = 0;
  for await (const e of Deno.readDir(new URL("../data/attendance_22", import.meta.url))) {
    const csv = await Deno.readTextFile(
      new URL(`../data/attendance_22/${e.name}`, import.meta.url),
    );
    const h = attendanceHeader(csv);
    assertEquals(h.sourceUrl, ATTENDANCE_SOURCE_URL, e.name);
    assertMatch(h.fetchedAt ?? "", /^\d{4}-\d{2}-\d{2}$/);
    rows += parseAttendance(csv, { sourceUrl: h.sourceUrl!, fetchedAt: h.fetchedAt! }).length;
    for (const r of parseCsvObjects(csv)) {
      assertEquals(byCode.get(r.mona_cd) ?? r.member_name, r.member_name, r.mona_cd);
      byCode.set(r.mona_cd, r.member_name);
    }
  }
  assert(rows > 0);
  assertEquals(new Set(byCode.values()).size, byCode.size);
});
