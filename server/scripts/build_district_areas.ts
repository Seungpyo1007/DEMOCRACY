// 공직선거법 [별표 1] + 행안부 행정동 codes → the district_areas CSV that
// import_district_areas.ts reads, and the 법정동→행정동 bridge CSV that
// import_bjdong_hdong.ts reads.
//
// The 구역표 names the 행정동 of its election day. juso and V-World answer with today's codes, so
// the table is read against the 행정동 alive on that day and then carried to today's codes:
//   1. same code, same name;
//   2. same 동 name in the 시군구 it came from (renamed 시도/시군구, new 일반구);
//   3. 법정동 overlap, when every 행정동 of that day sharing a 법정동 lies in one 선거구.
// Anything else is reported and the run fails, so nothing is guessed.
//
// Inputs:
//   --law    law.go.kr lawService JSON for the 공직선거법 version in force on the election
//            (22대: MST 261101), e.g.
//            https://www.law.go.kr/DRF/lawService.do?OC=test&target=law&MST=261101&type=JSON
//   --codes  KIKcd_H from 행안부 jscode "(말소코드포함)", fixed width, CP949
//   --mix    KIKmix from the same archive
//   --election 20240410 (default)
//
// Usage:
//   deno run --allow-read scripts/build_district_areas.ts --law law.json \
//     --codes KIKcd_H.20260720 --mix KIKmix.20260720 > district_areas.csv
//   deno run --allow-read scripts/build_district_areas.ts --emit bridge --mix KIKmix.20260720 > bridge.csv

import { sidoShortName } from "../supabase/functions/_shared/district_names.ts";
import { parseFlags } from "./lib/sql.ts";

export interface LawDistrict {
  sido: string;
  /** "마포구갑", without "선거구". */
  name: string;
  /** "공덕동, 아현동, ..." / "성동구 왕십리제2동, ..., 중구 일원" */
  area: string;
}

export interface HdongRow {
  code: string;
  sido: string;
  sgg: string;
  emd: string;
  born: string;
  dead: string;
}

export interface MixRow extends HdongRow {
  bjd: string;
  bjdName: string;
}

// ------------------------------------------------------------------ inputs

/** The 구역표 as law.go.kr draws it: box characters, one 선거구 per block, wrapped lines. */
export function parseLawTable(text: string): LawDistrict[] {
  const out: LawDistrict[] = [];
  let sido: string | null = null;
  let cur: { name: string; area: string } | null = null;
  const flush = () => {
    if (cur && sido) {
      out.push({
        sido,
        name: tidy(cur.name).replace(/선거구$/u, ""),
        area: tidy(cur.area.replace(/\s+/g, " ")).trim(),
      });
    }
    cur = null;
  };
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.trim();
    if (!line.startsWith("│")) {
      if (/^[├└┌]/u.test(line)) flush();
      continue;
    }
    const cells = line.replace(/^│|│$/gu, "").split("│");
    if (cells.length === 1) {
      const m = cells[0].trim().match(/^(\S+)\(지역구\s*:\s*\d+\)$/u);
      if (m) {
        flush();
        sido = m[1];
      }
      continue;
    }
    const name = cells[0].trim();
    const area = cells[1].trim();
    if (name === "선 거 구 명") continue;
    if (name) cur ??= { name: "", area: "" };
    if (!cur) continue;
    cur.name += name;
    // A wrapped line either starts a new item (previous ended with ",") or finishes a word.
    cur.area += cur.area && !cur.area.endsWith(",") ? area : ` ${area}`;
  }
  flush();
  return out;
}

/** law.go.kr drops the middle dot of "금호2·3가동" to "?". */
function tidy(s: string): string {
  return s.replace(/\?/g, "·");
}

/** The 국회의원 구역표 out of a lawService JSON response. */
export function lawTableFromJson(json: unknown): string {
  const units = (json as { 법령?: { 별표?: { 별표단위?: unknown } } })?.법령?.별표?.별표단위;
  const list = (Array.isArray(units) ? units : [units]) as {
    별표제목?: string;
    별표내용?: string[] | string[][];
  }[];
  const table = list.find((u) => u?.별표제목?.includes("국회의원지역선거구구역표"));
  if (!table?.별표내용) throw new Error("law JSON: no 국회의원지역선거구구역표");
  return (table.별표내용 as unknown[]).flat().join("\n");
}

/** 행안부 KIKcd_H / KIKmix: fixed-width columns in CP949 bytes, header on line 1. */
function fixedWidth(bytes: Uint8Array, widths: number[]): string[][] {
  const dec = new TextDecoder("euc-kr");
  const rows: string[][] = [];
  let start = 0;
  let first = true;
  for (let i = 0; i <= bytes.length; i++) {
    if (i < bytes.length && bytes[i] !== 0x0a) continue;
    const line = bytes.subarray(start, i);
    start = i + 1;
    if (first) {
      first = false;
      continue;
    }
    if (line.every((b) => b === 0x20 || b === 0x0d)) continue;
    const row: string[] = [];
    let pos = 0;
    for (const w of widths) {
      row.push(dec.decode(line.subarray(pos, pos + w)).trim());
      pos += w + 1;
    }
    rows.push(row);
  }
  return rows;
}

export function parseKikH(bytes: Uint8Array): HdongRow[] {
  return fixedWidth(bytes, [10, 30, 30, 30, 8, 8]).map(([code, sido, sgg, emd, born, dead]) => ({
    code,
    sido,
    sgg,
    emd,
    born,
    dead,
  }));
}

export function parseKikMix(bytes: Uint8Array): MixRow[] {
  return fixedWidth(bytes, [10, 30, 30, 30, 10, 30, 8, 8]).map((
    [code, sido, sgg, emd, bjd, bjdName, born, dead],
  ) => ({ code, sido, sgg, emd, bjd, bjdName, born, dead }));
}

// ------------------------------------------------------------------ build

/**
 * Where today's units came from, for the units renamed or re-coded after an election.
 * Keyed by today's names; values are the names on the election day. 일반구 created later
 * (화성시 동탄구 → 화성시) need no entry.
 */
export const SIDO_BEFORE: Record<string, string[]> = {
  "전남광주통합특별시": ["광주광역시", "전라남도"],
};
export const SGG_BEFORE: Record<string, string[]> = {
  "인천광역시|제물포구": ["중구", "동구"],
  "인천광역시|영종구": ["중구"],
  "인천광역시|검단구": ["서구"],
  "인천광역시|서해구": ["서구"],
};

const compact = (s: string) => s.replace(/[\s·ㆍ.]/gu, "");
/** "홍제제1동" = "홍제1동", "금호2·3가동" = "금호2.3가동". */
const dongKey = (s: string) => compact(s).replace(/제(\d)/gu, "$1");
const alive = (r: { born: string; dead: string }, day: string) =>
  r.born <= day && (r.dead === "" || r.dead > day);

export interface BuildResult {
  /** CSV text for import_district_areas.ts. */
  csv: string;
  /** Problems that stop the run. Empty = every current 행정동 has a 선거구. */
  problems: string[];
  stats: Record<string, number>;
}

export function buildDistrictAreas(input: {
  law: LawDistrict[];
  codes: HdongRow[];
  mix: MixRow[];
  election: string;
}): BuildResult {
  const { law, election } = input;
  const problems: string[] = [];
  const stats: Record<string, number> = {};
  const count = (k: string) => (stats[k] = (stats[k] ?? 0) + 1);

  // 행정동 of the election day, by 시도 and compact 시군구 name. 세종 has no 시군구 name.
  const then = input.codes.filter((r) => r.emd && alive(r, election));
  const bySgg = new Map<string, HdongRow[]>();
  const sggsOf = new Map<string, string[]>();
  for (const r of then) {
    const k = `${r.sido}|${compact(r.sgg)}`;
    if (!bySgg.has(k)) {
      bySgg.set(k, []);
      sggsOf.set(r.sido, [...(sggsOf.get(r.sido) ?? []), compact(r.sgg)]);
    }
    bySgg.get(k)!.push(r);
  }
  for (const [sd, list] of sggsOf) sggsOf.set(sd, list.sort((a, b) => b.length - a.length));

  // 1. 구역표 → election-day 행정동.
  const oldTo = new Map<string, string>(); // 행정동 code → "sido|name"
  for (const d of law) {
    const key = `${d.sido}|${d.name}`;
    const sggs = sggsOf.get(d.sido) ?? [];
    let ctx: string | null = sggs.find((g) => g && d.name.startsWith(g)) ??
      (sggs.includes("") ? "" : null);
    for (const item of d.area.split(/,\s*/u).map(compact).filter(Boolean)) {
      // "성동구왕십리제2동", "수원시장안구파장동", or a bare "공덕동" in the last named 시군구.
      const prefix = sggs.find((g) => g && item.startsWith(g) && item.length > g.length);
      let rest = item;
      if (prefix) {
        ctx = prefix;
        rest = item.slice(prefix.length);
      }
      if (ctx === null) {
        problems.push(`${key}: no 시군구 for "${item}"`);
        continue;
      }
      const pool = bySgg.get(`${d.sido}|${ctx}`) ?? [];
      const hits = rest === "일원" ? pool : pool.filter((r) => dongKey(r.emd) === dongKey(rest));
      if (hits.length === 0 || (rest !== "일원" && hits.length > 1)) {
        problems.push(`${key}: "${rest}" matches ${hits.length} 행정동 in ${ctx || d.sido}`);
        continue;
      }
      for (const r of hits) {
        const prev = oldTo.get(r.code);
        if (prev && prev !== key) problems.push(`${r.code} ${r.emd}: in ${prev} and ${key}`);
        oldTo.set(r.code, key);
      }
    }
  }
  // 출장소 belong to their 읍/면.
  for (const r of then) {
    if (oldTo.has(r.code)) continue;
    const parent = r.emd.match(/^(.+?[읍면])\S*출장소$/u)?.[1];
    const p = parent && bySgg.get(`${r.sido}|${compact(r.sgg)}`)!.find((x) => x.emd === parent);
    if (p && oldTo.has(p.code)) oldTo.set(r.code, oldTo.get(p.code)!);
    else problems.push(`${r.code} ${r.sido} ${r.sgg} ${r.emd}: in no 선거구 on ${election}`);
  }

  // 2. Carry to today's codes.
  const thenByCode = new Map(then.map((r) => [r.code, r]));
  const now = input.codes.filter((r) => r.emd && r.dead === "");
  const bjdThen = new Map<string, Set<string>>();
  const bjdNow = new Map<string, Set<string>>();
  for (const m of input.mix) {
    if (thenByCode.has(m.code) && alive(m, election)) addTo(bjdThen, m.code, m.bjdName);
    if (m.dead === "") addTo(bjdNow, m.code, m.bjdName);
  }
  const origins = (r: HdongRow): HdongRow[] => {
    const sidos = SIDO_BEFORE[r.sido] ?? [r.sido];
    const sggs = SGG_BEFORE[`${r.sido}|${r.sgg}`] ?? [compact(r.sgg)];
    const city = r.sgg.match(/^(\S+시)\s/u)?.[1];
    const out: HdongRow[] = [];
    for (const sd of sidos) {
      const found = sggs.flatMap((g) => bySgg.get(`${sd}|${g}`) ?? []);
      out.push(...(found.length || !city ? found : bySgg.get(`${sd}|${city}`) ?? []));
    }
    return out;
  };
  const nowTo = new Map<string, string>();
  for (const r of now) {
    const same = thenByCode.get(r.code);
    if (same && dongKey(same.emd) === dongKey(r.emd) && oldTo.has(r.code)) {
      nowTo.set(r.code, oldTo.get(r.code)!);
      count("same code");
      continue;
    }
    const pool = origins(r).filter((x) => oldTo.has(x.code));
    const named = pool.filter((x) => dongKey(x.emd) === dongKey(r.emd));
    if (named.length === 1) {
      nowTo.set(r.code, oldTo.get(named[0].code)!);
      count("same name");
      continue;
    }
    const mine = bjdNow.get(r.code) ?? new Set();
    const overlap = new Set(
      pool.filter((x) => [...(bjdThen.get(x.code) ?? [])].some((b) => mine.has(b)))
        .map((x) => oldTo.get(x.code)!),
    );
    if (overlap.size === 1) {
      nowTo.set(r.code, [...overlap][0]);
      count("법정동 overlap");
      continue;
    }
    problems.push(
      `${r.code} ${r.sido} ${r.sgg} ${r.emd}: ${
        overlap.size ? `spans ${[...overlap].sort().join(", ")}` : "no origin"
      }`,
    );
  }

  // 3. One row per 시군구 when it is all one 선거구, else one per 행정동.
  const bySigungu = new Map<string, HdongRow[]>();
  for (const r of now) {
    if (!nowTo.has(r.code)) continue;
    const sig = r.code.slice(0, 5);
    bySigungu.set(sig, [...(bySigungu.get(sig) ?? []), r]);
  }
  const lines = ["election_sg_id,sd_name,sgg_name,sigungu_code,hdong_code,hdong_name"];
  for (const sig of [...bySigungu.keys()].sort()) {
    const rows = bySigungu.get(sig)!.sort((a, b) => a.code.localeCompare(b.code));
    const targets = new Set(rows.map((r) => nowTo.get(r.code)!));
    if (targets.size === 1) {
      lines.push(`${election},${[...targets][0].replace("|", ",")},${sig},,`);
      count("whole-시군구 rows");
    } else {
      for (const r of rows) {
        lines.push(`${election},${nowTo.get(r.code)!.replace("|", ",")},${sig},${r.code},${r.emd}`);
        count("행정동 rows");
      }
    }
  }
  stats["선거구"] = new Set(nowTo.values()).size;
  return { csv: lines.join("\n") + "\n", problems, stats };
}

function addTo(map: Map<string, Set<string>>, key: string, value: string) {
  if (!map.has(key)) map.set(key, new Set());
  map.get(key)!.add(value);
}

/** Today's 법정동→행정동 pairs, as the simple CSV import_bjdong_hdong.ts reads. */
export function bridgeCsv(mix: MixRow[]): string {
  const seen = new Set<string>();
  const lines = ["bjd_code,hdong_code,hdong_name"];
  for (const m of mix) {
    if (m.dead !== "" || !m.emd || !/^\d{10}$/.test(m.bjd)) continue;
    if (seen.has(`${m.bjd}|${m.code}`)) continue;
    seen.add(`${m.bjd}|${m.code}`);
    lines.push(`${m.bjd},${m.code},${m.emd}`);
  }
  return lines.join("\n") + "\n";
}

if (import.meta.main) {
  const { flags } = parseFlags(Deno.args);
  const mix = parseKikMix(await Deno.readFile(flags.mix));
  if (flags.emit === "bridge") {
    console.log(bridgeCsv(mix).trimEnd());
    Deno.exit(0);
  }
  const law = parseLawTable(lawTableFromJson(JSON.parse(await Deno.readTextFile(flags.law))));
  const { csv, problems, stats } = buildDistrictAreas({
    law,
    codes: parseKikH(await Deno.readFile(flags.codes)),
    mix,
    election: flags.election ?? "20240410",
  });
  console.error(`${law.length} 선거구 in the 구역표`, stats);
  for (const p of problems) console.error(`  ${p}`);
  if (problems.length) Deno.exit(1);
  const base = (p: string) => p.split("/").pop();
  const sidos = [...new Set(law.map((d) => sidoShortName(d.sido)))].join(" ");
  console.log(`# ${law.length} 선거구 (${sidos}). Built by scripts/build_district_areas.ts from`);
  console.log(`# --law ${base(flags.law)} --codes ${base(flags.codes)} --mix ${base(flags.mix)}`);
  console.log(csv.trimEnd());
}
