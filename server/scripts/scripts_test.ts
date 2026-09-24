import { assert, assertEquals, assertMatch, assertStringIncludes, assertThrows } from "@std/assert";
import { districtAreasToSql, parseDistrictAreas } from "./import_district_areas.ts";
import { bridgeToSql, parseBridge } from "./import_bjdong_hdong.ts";
import { attendanceToSql } from "./import_attendance.ts";
import { resultsToSql } from "./import_historical_results.ts";
import { geojsonToSql } from "./import_geojson.ts";
import { pledgesToSql, regionToSql } from "./import_curated.ts";
import { parseCsv } from "./lib/csv.ts";
import { lit, requireHttpUrl } from "./lib/sql.ts";
import { sample } from "../testdata/fake_upstream.ts";
import { MAPO_A, MAPO_B } from "../testdata/pipeline.ts";

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
