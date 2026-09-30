// 공직선거법 [별표 1] of three general elections → how each 22대 선거구 came to be:
//   * region docs (data/region_22/<districtId>.json) for import_curated.ts --kind region, one
//     dated event per election that changed the 선거구 or kept it as it was;
//   * district_lineage rows (data/district_lineage_22.csv) for import_district_lineage.ts, so
//     a renamed or split 선거구 keeps its past elections.
//
// Two tables are compared on the 행정동 alive on the later election day: the later table is
// read on that day (build_district_areas.ts' resolveTable), the earlier one read on its own day
// and carried forward (carryTo). A 행정동 either table cannot place, or places only in part
// (봉담읍's 리 in 2020, a 동 later cut in two), makes every relation touching it unknown, and an
// unknown relation says nothing. What is said is read off the two tables and nothing else:
//   same      one old 선거구, the same 행정동 → 「구역 변동 없음」 or 「선거구 이름 변경」
//   split     one old 선거구, whose 행정동 now make up several new ones → 「선거구 분할」
//   merged    several old 선거구, all of each inside this one → 「선거구 통합」
//   boundary  anything else, named by whole 구역표 items only → 「선거구 구역 변경」 /
//             「선거구 구역 재편」; if a change cuts through an item the relation is unknown.
//
// Inputs: lawService JSON of the version in force on each election day (20대 MST 181619,
// 21대 216091, 22대 261101) and 행안부 KIKcd_H / KIKmix "(말소코드포함)", as for
// build_district_areas.ts. Each event cites the version whose table made the change
// (--changed21 / --changed22, e.g. 215523 and 261101), found by diffing the versions between.
//
// Usage:
//   deno run --allow-read --allow-write scripts/build_district_lineage.ts \
//     --law20 law_181619.json --law21 law_216091.json --law22 law_261101.json \
//     --changed21 215523 --changed22 261101 --fetched-at 2026-09-28 \
//     --codes KIKcd_H.20260720 --mix KIKmix.20260720 --out data

import {
  carryTo,
  type HdongRow,
  type LawDistrict,
  lawTableFromJson,
  type MixRow,
  parseKikH,
  parseKikMix,
  parseLawTable,
  resolveTable,
  type TableItem,
} from "./build_district_areas.ts";
import {
  districtIdFor,
  districtNameKey,
  formatDistrictDisplayName,
  necSggCode,
  sidoShortName,
  spaceSplitSuffix,
} from "../supabase/functions/_shared/district_names.ts";
import { parseFlags } from "./lib/sql.ts";

/**
 * A part of a new 선거구 that came from one old 선거구: all of it, or the items `labels`.
 * `excluded`, when known, is the rest of that old 선거구, as items of the 선거구 it went to.
 */
export interface Part {
  from: string;
  whole: boolean;
  labels: string[];
  excluded?: string[];
}

/** Items of an old 선거구 that went to new 선거구 `to`. */
export interface Moved {
  to: string;
  labels: string[];
}

export type Relation =
  | { kind: "same"; from: string }
  | { kind: "split"; from: string; into: string[] }
  | { kind: "merged"; from: string[] }
  /** Keeps the name of `main`; `gained` came in, `lost` went to other new 선거구. */
  | { kind: "boundary"; main: string; gained: Part[]; lost: Moved[] }
  /** No old 선거구 of the same name: what it is made of. */
  | { kind: "rebuilt"; parts: Part[] }
  | { kind: "unknown"; reason: string };

export interface Transition {
  relations: Map<string, Relation>;
  /** New 선거구 → the one old 선거구 its whole area came from, when there is one. */
  predecessor: Map<string, string>;
  problems: string[];
}

/** "강원도|춘천시" and "강원특별자치도|춘천시" are the same name. */
const sameName = (x: string, y: string) => nameKeyOf(x) === nameKeyOf(y);
export const nameKeyOf = (key: string) => {
  const [sido, name] = key.split("|");
  return districtNameKey(sido, name);
};

export function compareTables(input: {
  oldLaw: LawDistrict[];
  newLaw: LawDistrict[];
  oldDay: string;
  newDay: string;
  codes: HdongRow[];
  mix: MixRow[];
}): Transition {
  const { oldDay, newDay, codes, mix } = input;
  const oldRes = resolveTable(input.oldLaw, codes, oldDay);
  const newRes = resolveTable(input.newLaw, codes, newDay);
  const carried = carryTo(oldRes, codes, mix, newDay);
  const problems = [
    ...oldRes.problems.map((p) => `${oldDay}: ${p}`),
    ...newRes.problems.map((p) => `${newDay}: ${p}`),
    ...carried.problems.map((p) => `${oldDay}→${newDay}: ${p}`),
  ];
  const a = carried.nowTo; // new-day 행정동 → old 선거구
  const b = newRes.oldTo; // new-day 행정동 → new 선거구

  const codesOf = new Map<string, string[]>();
  const oldCodesOf = new Map<string, string[]>();
  for (const r of newRes.then) {
    if (b.has(r.code)) push(codesOf, b.get(r.code)!, r.code);
    if (a.has(r.code)) push(oldCodesOf, a.get(r.code)!, r.code);
  }
  const preds = (n: string) => new Set((codesOf.get(n) ?? []).map((t) => a.get(t) ?? "?"));
  const succs = (o: string) => new Set((oldCodesOf.get(o) ?? []).map((t) => b.get(t) ?? "?"));
  const itemsOf = new Map<string, TableItem[]>();
  for (const it of newRes.items) push(itemsOf, it.district, it);

  /** The items of `owner` that make up exactly `set`, or null if one is cut. */
  const itemsFor = (owner: string, set: Set<string>): string[] | null => {
    const labels: string[] = [];
    let covered = 0;
    for (const it of itemsOf.get(owner) ?? []) {
      const inside = it.codes.filter((t) => set.has(t)).length;
      if (inside === 0) continue;
      if (inside !== it.codes.length) return null;
      labels.push(it.label);
      covered += inside;
    }
    return covered === set.size ? labels : null;
  };
  /** What of `n` came from each old 선거구 other than `skip`. */
  const partsOf = (n: string, skip?: string): Part[] | null => {
    const byOld = new Map<string, Set<string>>();
    for (const t of codesOf.get(n) ?? []) {
      if (a.get(t) === skip) continue;
      if (!byOld.has(a.get(t)!)) byOld.set(a.get(t)!, new Set());
      byOld.get(a.get(t)!)!.add(t);
    }
    const parts: Part[] = [];
    for (const o of sortByTable([...byOld.keys()], input.oldLaw)) {
      const set = byOld.get(o)!;
      const labels = itemsFor(n, set);
      if (labels === null) return null;
      const whole = set.size === (oldCodesOf.get(o) ?? []).length;
      const excluded = whole ? null : movedOut(o, n)?.flatMap((m) => m.labels);
      parts.push({ from: o, whole, labels, ...(excluded ? { excluded } : {}) });
    }
    return parts;
  };

  /** Where the rest of old 선거구 `o` went, besides `n`, as whole items of each. */
  const movedOut = (o: string, n: string): Moved[] | null => {
    const byNew = new Map<string, Set<string>>();
    for (const t of oldCodesOf.get(o) ?? []) {
      if (b.get(t) === n) continue;
      if (!byNew.has(b.get(t)!)) byNew.set(b.get(t)!, new Set());
      byNew.get(b.get(t)!)!.add(t);
    }
    const out: Moved[] = [];
    for (const to of sortByTable([...byNew.keys()], input.newLaw)) {
      const labels = itemsFor(to, byNew.get(to)!);
      if (labels === null) return null;
      out.push({ to, labels });
    }
    return out;
  };

  const relations = new Map<string, Relation>();
  const predecessor = new Map<string, string>();
  const unknown = (n: string, reason: string) => relations.set(n, { kind: "unknown", reason });
  for (const d of input.newLaw) {
    const n = `${d.sido}|${d.name}`;
    const ps = [...preds(n)];
    if (ps.length === 0 || ps.includes("?")) {
      unknown(n, "part of it is in no old 선거구");
      continue;
    }
    if (ps.some((o) => succs(o).has("?"))) {
      unknown(n, "an old 선거구 it touches is partly in no new 선거구");
      continue;
    }
    if (ps.length === 1) predecessor.set(n, ps[0]);
    if (ps.length === 1 && succs(ps[0]).size === 1) {
      relations.set(n, { kind: "same", from: ps[0] });
      continue;
    }
    if (ps.length === 1) {
      const into = [...succs(ps[0])];
      if (into.every((s) => preds(s).size === 1)) {
        relations.set(n, { kind: "split", from: ps[0], into: sortByTable(into, input.newLaw) });
        continue;
      }
    }
    if (ps.length > 1 && ps.every((o) => succs(o).size === 1)) {
      relations.set(n, { kind: "merged", from: sortByTable(ps, input.oldLaw) });
      continue;
    }
    const main = ps.find((o) => sameName(o, n));
    if (!main) {
      const parts = partsOf(n);
      if (parts === null) unknown(n, "a change cuts through a 구역표 item");
      else relations.set(n, { kind: "rebuilt", parts });
      continue;
    }
    const gained = partsOf(n, main);
    const lost = movedOut(main, n);
    if (gained === null || lost === null) {
      unknown(n, "a change cuts through a 구역표 item");
      continue;
    }
    relations.set(n, { kind: "boundary", main, gained, lost });
  }
  return { relations, predecessor, problems };
}

function push<T>(m: Map<string, T[]>, k: string, v: T) {
  m.set(k, [...(m.get(k) ?? []), v]);
}

function sortByTable(keys: string[], law: LawDistrict[]): string[] {
  const order = new Map(law.map((d, i) => [`${d.sido}|${d.name}`, i]));
  return [...keys].sort((x, y) => (order.get(x) ?? 0) - (order.get(y) ?? 0));
}

// ------------------------------------------------------------------ wording

/** Picks 은/는, 이/가, 으로/로 by the last syllable. Digits and Latin read as vowels. */
export function josa(word: string, withFinal: string, without: string): string {
  const last = word.trim().at(-1) ?? "";
  const code = last.charCodeAt(0) - 0xac00;
  if (code < 0 || code > 11171) return word + without;
  const final = code % 28;
  // 으로/로: ㄹ takes 로.
  if (withFinal === "으로" && final === 8) return word + without;
  return word + (final ? withFinal : without);
}

/** "경기도|화성시을" → "화성시 을", with the 시도 when it is not `home`'s. */
export function nameOf(key: string, home?: string): string {
  const [sido, name] = key.split("|");
  const short = spaceSplitSuffix(name);
  return home && sidoShortName(home.split("|")[0]) !== sidoShortName(sido)
    ? `${sidoShortName(sido)} ${short}`
    : short;
}

/** ["화성시 을", "화성시 정"] → "화성시 을·정". */
export function joinNames(names: string[]): string {
  const parts = names.map((n) => n.match(/^(.*) ([갑을병정무])$/u));
  if (parts.every((p) => p) && new Set(parts.map((p) => p![1])).size === 1) {
    return `${parts[0]![1]} ${parts.map((p) => p![2]).join("·")}`;
  }
  return names.join("·");
}

const MAX_LABELS = 4;
/**
 * "공덕동, 아현동", or "공덕동, 아현동, 도화동, 용강동 등 9곳" past four. Commas, not "·":
 * a 동 name can hold a "·" of its own (불로·봉무동).
 */
export function joinLabels(labels: string[]): string {
  const clean = labels.map((l) => l.replace(/ㆍ/gu, "·"));
  if (clean.length <= MAX_LABELS) return clean.join(", ");
  return `${clean.slice(0, MAX_LABELS).join(", ")} 등 ${clean.length}곳`;
}

/**
 * "동구 갑 전체", "동구 을(방촌동 제외)" or "동구 을 일부(방촌동)", whichever names fewer
 * items.
 */
function partText(p: Part, home: string): string {
  const name = nameOf(p.from, home);
  if (p.whole) return `${name} 전체`;
  if (p.excluded && p.excluded.length > 0 && p.excluded.length < p.labels.length) {
    return `${name}(${joinLabels(p.excluded)} 제외)`;
  }
  return `${name} 일부(${joinLabels(p.labels)})`;
}

export interface EventText {
  title: string;
  detail: string;
}

/** The event for new 선거구 `n` under `rel`; `term` is the 대 of the earlier election. */
export function describe(n: string, rel: Relation, term: number): EventText | null {
  switch (rel.kind) {
    case "unknown":
      return null;
    case "same":
      return sameName(rel.from, n)
        ? { title: "선거구 구역 변동 없음", detail: `제${term}대 총선과 같은 구역` }
        : {
          title: "선거구 이름 변경",
          detail: `${nameOf(rel.from, n)} → ${nameOf(n)}, 구역은 그대로`,
        };
    case "split":
      return {
        title: "선거구 분할",
        detail: `${josa(nameOf(rel.from, n), "이", "가")} ${
          josa(joinNames(rel.into.map((x) => nameOf(x, n))), "으로", "로")
        } 나뉨`,
      };
    case "merged":
      return {
        title: "선거구 통합",
        detail: `${josa(joinNames(rel.from.map((x) => nameOf(x, n))), "이", "가")} ${
          josa(nameOf(n), "으로", "로")
        } 합쳐짐`,
      };
    case "rebuilt": {
      const parts = [...rel.parts].sort((x, y) => Number(y.whole) - Number(x.whole))
        .map((p) => partText(p, n));
      return { title: "선거구 구역 재편", detail: `구성: ${parts.join(", ")}` };
    }
    case "boundary": {
      const bits = [
        ...rel.gained.map((p) =>
          p.whole
            ? `${nameOf(p.from, n)} 전체 편입`
            : `${nameOf(p.from, n)}에서 ${joinLabels(p.labels)} 편입`
        ),
        ...rel.lost.map((l) =>
          `${josa(joinLabels(l.labels), "은", "는")} ${josa(nameOf(l.to, n), "으로", "로")} 옮겨감`
        ),
      ];
      return { title: "선거구 구역 변경", detail: bits.join(". ") };
    }
  }
}

// ------------------------------------------------------------------ build

export interface Version {
  /** 법령일련번호 of the version whose table made the change. */
  mst: string;
  /** Election year the table first applied to. */
  year: number;
  /** 대 of the election before it. */
  prevTerm: number;
}

export const lawPage = (mst: string) => `https://www.law.go.kr/LSW/lsInfoP.do?lsiSeq=${mst}`;
const PUBLISHER = "국가법령정보센터";

export interface RegionDoc {
  districtId: string;
  displayName: string;
  source: { sourceUrl: string; fetchedAt: string; publisher: string };
  events: {
    year: number;
    title: string;
    detail: string;
    source: { sourceUrl: string; fetchedAt: string; publisher: string };
  }[];
}

export interface LineageRow {
  district_id: string;
  display_name: string;
  sg_id: string;
  name_key: string;
  note: string;
}

/**
 * Region docs and lineage rows for every 22대 선거구 in `current`. `t21` compares the 20대 and
 * 21대 tables, `t22` the 21대 and 22대. A 22대 선거구 gets the 2020 event only when its whole
 * area was one 21대 선거구 of the same name; the 2020 event of a differently named one would be
 * about another 선거구.
 */
export function buildLineage(input: {
  current: LawDistrict[];
  t21: Transition;
  t22: Transition;
  v21: Version;
  v22: Version;
  /** The 22대 version, which every doc is read against. */
  currentMst: string;
  fetchedAt: string;
}): { docs: RegionDoc[]; lineage: LineageRow[]; stats: Record<string, number> } {
  const { t21, t22, v21, v22, fetchedAt } = input;
  const stats: Record<string, number> = {};
  const count = (k: string) => (stats[k] = (stats[k] ?? 0) + 1);
  const src = (mst: string) => ({ sourceUrl: lawPage(mst), fetchedAt, publisher: PUBLISHER });
  const docs: RegionDoc[] = [];
  const lineage: LineageRow[] = [];

  for (const d of input.current) {
    const n = `${d.sido}|${d.name}`;
    const districtId = districtIdFor(necSggCode(d.sido, d.name));
    const displayName = formatDistrictDisplayName(d.sido, d.name);
    const events: RegionDoc["events"] = [];

    const p21 = t22.predecessor.get(n);
    const r22 = t22.relations.get(n);
    const r21 = p21 && sameName(p21, n) ? t21.relations.get(p21) : undefined;
    const e21 = r21 && p21 ? describe(p21, r21, v21.prevTerm) : null;
    if (e21) events.push({ year: v21.year, ...e21, source: src(v21.mst) });
    const e22 = r22 ? describe(n, r22, v22.prevTerm) : null;
    if (e22) events.push({ year: v22.year, ...e22, source: src(v22.mst) });
    count(`2020 ${r21?.kind ?? "none"}`);
    count(`2024 ${r22?.kind ?? "none"}`);

    if (events.length > 0) {
      docs.push({ districtId, displayName, source: src(input.currentMst), events });
    }

    // Lineage: the 선거구 this one's whole area was in, when it had another name.
    const p20 = p21 ? t21.predecessor.get(p21) : undefined;
    const key = nameKeyOf(n);
    if (p21 && nameKeyOf(p21) !== key) {
      lineage.push({
        district_id: districtId,
        display_name: displayName,
        sg_id: "20200415",
        name_key: nameKeyOf(p21),
        note: `제22대 구역 전체가 제21대 ${nameOf(p21)} 선거구 안`,
      });
    }
    if (p20 && nameKeyOf(p20) !== key) {
      lineage.push({
        district_id: districtId,
        display_name: displayName,
        sg_id: "20160413",
        name_key: nameKeyOf(p20),
        note: `제22대 구역 전체가 제20대 ${nameOf(p20)} 선거구 안`,
      });
    }
  }
  stats["docs"] = docs.length;
  stats["events"] = docs.reduce((s, d) => s + d.events.length, 0);
  stats["lineage rows"] = lineage.length;
  return { docs, lineage, stats };
}

export function lineageCsv(rows: LineageRow[]): string {
  const q = (s: string) => (/[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s);
  const lines = ["district_id,display_name,sg_id,name_key,note"];
  for (const r of rows) {
    lines.push(
      [r.district_id, r.display_name, r.sg_id, r.name_key, r.note].map(q).join(","),
    );
  }
  return lines.join("\n") + "\n";
}

if (import.meta.main) {
  const { flags } = parseFlags(Deno.args);
  const law = async (path: string) =>
    parseLawTable(lawTableFromJson(JSON.parse(await Deno.readTextFile(path))));
  const [law20, law21, law22] = await Promise.all([
    law(flags.law20),
    law(flags.law21),
    law(flags.law22),
  ]);
  const codes = parseKikH(await Deno.readFile(flags.codes));
  const mix = parseKikMix(await Deno.readFile(flags.mix));
  const t21 = compareTables({
    oldLaw: law20,
    newLaw: law21,
    oldDay: "20160413",
    newDay: "20200415",
    codes,
    mix,
  });
  const t22 = compareTables({
    oldLaw: law21,
    newLaw: law22,
    oldDay: "20200415",
    newDay: "20240410",
    codes,
    mix,
  });
  const fetchedAt = new Date(`${flags["fetched-at"]}T00:00:00+09:00`).toISOString();
  const currentMst = flags.current ?? flags.changed22;
  const { docs, lineage, stats } = buildLineage({
    current: law22,
    t21,
    t22,
    v21: { mst: flags.changed21, year: 2020, prevTerm: 20 },
    v22: { mst: flags.changed22, year: 2024, prevTerm: 21 },
    currentMst,
    fetchedAt,
  });
  for (const p of [...t21.problems, ...t22.problems]) console.error(`  ${p}`);
  for (const [label, t] of [["2020", t21], ["2024", t22]] as const) {
    for (const [n, r] of t.relations) {
      if (r.kind === "unknown") console.error(`  ${label} ${n}: unknown (${r.reason})`);
    }
  }
  console.error(stats);
  const out = flags.out ?? "data";
  await Deno.mkdir(`${out}/region_22`, { recursive: true });
  for (const doc of docs) {
    await Deno.writeTextFile(
      `${out}/region_22/${doc.districtId}.json`,
      JSON.stringify(doc, null, 2) + "\n",
    );
  }
  await Deno.writeTextFile(`${out}/district_lineage_22.csv`, lineageCsv(lineage));
}
