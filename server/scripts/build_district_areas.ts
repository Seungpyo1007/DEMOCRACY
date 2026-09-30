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
 * Where a unit came from, for the units renamed or re-coded after an election. Keyed by the
 * later names; values are earlier names, searched as well as the unit's own. A "시도|시군구"
 * value is a 시군구 that sat in another 시도 (군위군, 경북 → 대구 in 2023). 일반구 created later
 * (화성시 동탄구 → 화성시) need no entry.
 */
export const SIDO_BEFORE: Record<string, string[]> = {
  "전남광주통합특별시": ["광주광역시", "전라남도"],
  "강원특별자치도": ["강원도"],
  "전북특별자치도": ["전라북도"],
};
export const SGG_BEFORE: Record<string, string[]> = {
  "인천광역시|제물포구": ["중구", "동구"],
  "인천광역시|영종구": ["중구"],
  "인천광역시|검단구": ["서구"],
  "인천광역시|서해구": ["서구"],
  "인천광역시|미추홀구": ["남구"],
  "대구광역시|군위군": ["경상북도|군위군"],
};

/** KIKcd writes "숭의1,3동" and "도화2.3동" where the 구역표 writes "숭의1·3동". */
const compact = (s: string) => s.replace(/[\s·ㆍ.,]/gu, "");
/** "홍제제1동" = "홍제1동", "금호2·3가동" = "금호2.3가동". */
const dongKey = (s: string) => compact(s).replace(/제(\d)/gu, "$1");
const alive = (r: { born: string; dead: string }, day: string) =>
  r.born <= day && (r.dead === "" || r.dead > day);
/** A day after every recorded change: alive on it = alive today. */
export const TODAY = "99999999";

/** One comma-separated entry of a 선거구's 구역, and the 행정동 it names. */
export interface TableItem {
  /** "sido|name" of its 선거구. */
  district: string;
  /** As the table writes it: "망원제1동", or "중구" for "중구 일원". */
  label: string;
  /** Codes of the 행정동 it names, alive on the election day. Empty when unresolved. */
  codes: string[];
}

export interface TableResolution {
  election: string;
  /** 행정동 alive on the election day. */
  then: HdongRow[];
  /** Election-day 행정동 code → "sido|name". */
  oldTo: Map<string, string>;
  items: TableItem[];
  problems: string[];
}

/** 구역표 → the 행정동 alive on its election day. */
export function resolveTable(
  law: LawDistrict[],
  codes: HdongRow[],
  election: string,
): TableResolution {
  const problems: string[] = [];
  const items: TableItem[] = [];

  // 행정동 of the election day, by 시도 and compact 시군구 name. 세종 has no 시군구 name.
  const then = codes.filter((r) => r.emd && alive(r, election));
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

  const oldTo = new Map<string, string>(); // 행정동 code → "sido|name"
  for (const d of law) {
    const key = `${d.sido}|${d.name}`;
    const sggs = sggsOf.get(d.sido) ?? [];
    // Where a bare 동 name is looked up: the 시군구 the 선거구 is named after, or every 일반구
    // of the city it is named after (the 2016 table lists 수원시갑's 동 without their 구).
    const within = (name: string): string[] | null => {
      const exact = sggs.find((g) => g && name.startsWith(g));
      if (exact) return [exact];
      const city = name.match(/^(\S+?시)/u)?.[1];
      const parts = city ? sggs.filter((g) => g.startsWith(city)) : [];
      return parts.length ? parts : null;
    };
    let ctx: string[] | null = within(d.name) ?? (sggs.includes("") ? [""] : null);
    for (const raw of splitArea(d.area)) {
      // "세종특별자치시 일원" is the whole 시도.
      const item = compact(raw).replace(new RegExp(`^${compact(d.sido)}(?=일원$)`, "u"), "");
      // "성동구왕십리제2동", "수원시장안구파장동", or a bare "공덕동" in the last named 시군구.
      const prefix = sggs.find((g) => g && item.startsWith(g) && item.length > g.length);
      let rest = item;
      if (prefix) {
        ctx = [prefix];
        rest = item.slice(prefix.length);
      }
      const entry: TableItem = { district: key, label: itemLabel(raw, prefix), codes: [] };
      items.push(entry);
      if (ctx === null) {
        problems.push(`${key}: no 시군구 for "${item}"`);
        continue;
      }
      if (rest.includes("(")) {
        // "봉담읍(분천리, 왕림리)": part of a 행정동, which no 행정동 code can stand for.
        problems.push(`${key}: "${raw}" names part of a 행정동`);
        continue;
      }
      const pool = ctx.flatMap((g) => bySgg.get(`${d.sido}|${g}`) ?? []);
      const hits = rest === "일원" ? pool : pool.filter((r) => dongKey(r.emd) === dongKey(rest));
      if (hits.length === 0 || (rest !== "일원" && hits.length > 1)) {
        const where = ctx.join("/") || d.sido;
        problems.push(`${key}: "${rest}" matches ${hits.length} 행정동 in ${where}`);
        continue;
      }
      for (const r of hits) {
        const prev = oldTo.get(r.code);
        if (prev && prev !== key) problems.push(`${r.code} ${r.emd}: in ${prev} and ${key}`);
        oldTo.set(r.code, key);
        entry.codes.push(r.code);
      }
    }
  }
  // 출장소 belong to their 읍/면.
  for (const r of then) {
    if (oldTo.has(r.code)) continue;
    const parent = r.emd.match(/^(.+?[읍면])\S*출장소$/u)?.[1];
    const p = parent && bySgg.get(`${r.sido}|${compact(r.sgg)}`)!.find((x) => x.emd === parent);
    if (p && oldTo.has(p.code)) {
      oldTo.set(r.code, oldTo.get(p.code)!);
      items.find((i) => i.codes.includes(p.code))?.codes.push(r.code);
    } else problems.push(`${r.code} ${r.sido} ${r.sgg} ${r.emd}: in no 선거구 on ${election}`);
  }
  return { election, then, oldTo, items, problems };
}

/** "성동구 금호2·3가동" → "금호2·3가동", "중구 일원" → "중구": the item as a reader names it. */
function itemLabel(raw: string, prefix: string | undefined): string {
  if (/일원$/u.test(raw)) return raw.replace(/\s*일원$/u, "");
  if (!prefix) return raw.trim();
  let seen = 0;
  for (let i = 0; i < raw.length; i++) {
    if (seen === prefix.length) return raw.slice(i).trim();
    seen += compact(raw[i]).length;
  }
  return raw.trim();
}

/** "a, b(c, d), e" → ["a", "b(c, d)", "e"]: a parenthesised list is one item. */
function splitArea(area: string): string[] {
  const out: string[] = [];
  let depth = 0;
  let cur = "";
  for (const ch of area) {
    if (ch === "(") depth++;
    if (ch === ")") depth = Math.max(0, depth - 1);
    if (ch === "," && depth === 0) {
      out.push(cur.trim());
      cur = "";
    } else cur += ch;
  }
  out.push(cur.trim());
  return out.filter(Boolean);
}

export interface Carried {
  /** 행정동 alive on the target day. */
  now: HdongRow[];
  /** Target-day 행정동 code → "sido|name" of the election's 선거구. */
  nowTo: Map<string, string>;
  problems: string[];
  stats: Record<string, number>;
}

/**
 * A resolved table carried to the 행정동 alive on [day] (default: today):
 *   1. same code, same name;
 *   2. same 동 name in the 시군구 it came from (renamed 시도/시군구, new 일반구);
 *   3. 법정동 overlap, when every 행정동 of the election day sharing a 법정동 lies in one 선거구.
 * Anything else is a problem and has no 선거구.
 */
export function carryTo(
  res: TableResolution,
  codes: HdongRow[],
  mix: MixRow[],
  day = TODAY,
): Carried {
  const { then, oldTo, election } = res;
  const problems: string[] = [];
  const stats: Record<string, number> = {};
  const count = (k: string) => (stats[k] = (stats[k] ?? 0) + 1);
  const bySgg = new Map<string, HdongRow[]>();
  for (const r of then) {
    const k = `${r.sido}|${compact(r.sgg)}`;
    bySgg.set(k, [...(bySgg.get(k) ?? []), r]);
  }

  const thenByCode = new Map(then.map((r) => [r.code, r]));
  const now = codes.filter((r) => r.emd && alive(r, day));
  const bjdThen = new Map<string, Set<string>>();
  const bjdNow = new Map<string, Set<string>>();
  for (const m of mix) {
    if (thenByCode.has(m.code) && alive(m, election)) addTo(bjdThen, m.code, m.bjdName);
    if (alive(m, day)) addTo(bjdNow, m.code, m.bjdName);
  }
  const origins = (r: HdongRow): HdongRow[] => {
    const own = compact(r.sgg);
    const extra = SGG_BEFORE[`${r.sido}|${r.sgg}`] ?? [];
    const sggs = [own, ...extra.filter((g) => !g.includes("|"))];
    const out: HdongRow[] = [];
    for (const g of extra.filter((g) => g.includes("|"))) out.push(...bySgg.get(g) ?? []);
    for (const sd of [r.sido, ...(SIDO_BEFORE[r.sido] ?? [])]) {
      const found = sggs.flatMap((g) => bySgg.get(`${sd}|${g}`) ?? []);
      if (found.length) {
        out.push(...found);
        continue;
      }
      // 일반구 created (화성시 동탄구 ← 화성시) or abolished (부천시 ← 부천시 원미구) since.
      const city = r.sgg.match(/^(\S+시)\s/u)?.[1] ?? (own.endsWith("시") ? own : null);
      if (!city) continue;
      for (const [k, rows] of bySgg) if (k.startsWith(`${sd}|${city}`)) out.push(...rows);
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
  return { now, nowTo, problems, stats };
}

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
  const res = resolveTable(law, input.codes, election);
  const { now, nowTo, problems, stats } = carryTo(res, input.codes, input.mix);
  problems.unshift(...res.problems);
  const count = (k: string) => (stats[k] = (stats[k] ?? 0) + 1);

  // One row per 시군구 when it is all one 선거구, else one per 행정동.
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
