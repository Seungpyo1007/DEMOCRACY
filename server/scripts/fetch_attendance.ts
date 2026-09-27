// 국회의원 본회의 출결현황 (열린국회정보 file dataset) → data/attendance_22/<회기>.csv.
//
// Dataset: https://open.assembly.go.kr/portal/data/service/selectServicePage.do/O4Q5B50011905O18367
// 국회사무처 posts one .xlsx per 회기 (22대: 제415회 onward; older 회기 are PDFs of the 21대).
// There is no Open API for it, so this script lists the dataset's files through the portal's
// own file-list endpoint, downloads each 22대 .xlsx and converts it to the CSV that
// import_attendance.ts reads:
//   mona_cd,member_name,meeting_date,meeting_label,status
//
// Source layout (one sheet): 의원명, 소속정당, then one column per 본회의 차수 whose second header
// row holds its date, then that 회기's counts 회의일수/출석/결석/청가/출장/결석신고서, then the
// 22대 totals and a 비고 column. A cell holds the source wording (출석 / 결석 / 청가 / 출장 /
// 결석신고서) or "-" for a sitting held while the person was not a member (before 승계/보궐 or
// after 퇴직). "-" is not a sitting of theirs: the source leaves it out of 회의일수, so no row is
// written for it. Every file is checked against its own count columns before anything is written.
//
// The files name members only (a same-name pair is told apart by writing one in 한자, e.g.
// 朴芝源). MONA_CD comes from 국회의원 정보 통합 API (ALLNAMEMBER), restricted to 22대 members:
// a 한자 name matches NAAS_CH_NM; a Hangul name that still has two 22대 candidates keeps the one
// whose 한자 name is not written in any 22대 file (the source's own way of telling them apart:
// 박지원 is 8BF5855P, 朴芝源 is H7X3372O). Anything else ambiguous stops.
//
// Usage (from server/):
//   deno run --allow-net=open.assembly.go.kr --allow-read --allow-write=data/attendance_22 \
//     --allow-env=ASSEMBLY_API_KEY scripts/fetch_attendance.ts [--fetched-at YYYY-MM-DD]
// It always rewrites every 22대 회기 file, so a corrected re-post (「(수정)」) replaces the old one.
// ASSEMBLY_API_KEY is optional: without it ALLNAMEMBER returns at most 5 rows per name, which
// is enough unless a name has more than 5 members in history (the script stops and says so).

import { ATTENDANCE_STATUSES } from "./import_attendance.ts";
import { parseFlags } from "./lib/sql.ts";
import { readFirstSheet } from "./lib/xlsx.ts";

export const ATTENDANCE_DATASET = "O4Q5B50011905O18367";
export const ATTENDANCE_SOURCE_URL =
  `https://open.assembly.go.kr/portal/data/service/selectServicePage.do/${ATTENDANCE_DATASET}`;
/** 제415회 is the first 회기 of the 22대 국회. */
export const FIRST_22_SESSION = 415;

const COUNT_HEADERS = ["회의일수", ...ATTENDANCE_STATUSES];
const NOT_SEATED = "-";

export interface Sitting {
  label: string; // "제438회 제1차"
  date: string; // "2026-08-20"
}

export interface SheetMember {
  name: string;
  /** One per sitting; null where the source has "-" (not a member then). */
  statuses: (string | null)[];
}

export interface AttendanceSheet {
  session: number;
  sittings: Sitting[];
  members: SheetMember[];
}

/**
 * Reads one 회기 file. Throws when the layout is not the one described above or when a
 * member's cells do not add up to the file's own 회의일수/출석/... columns.
 */
export function parseAttendanceSheet(rows: string[][]): AttendanceSheet {
  const h = rows.findIndex((r) => r[0]?.trim() === "의원명");
  if (h < 1 || rows[h + 1]?.[0]?.trim() !== "의원명") {
    throw new Error("attendance sheet: no 의원명 header rows");
  }
  const head = rows[h].map((c) => c.trim());
  const dates = rows[h + 1].map((c) => c.trim());
  const countAt = head.indexOf("회의일수");
  if (countAt < 0 || COUNT_HEADERS.some((k, i) => head[countAt + i] !== k)) {
    throw new Error(`attendance sheet: count columns changed: ${head.slice(countAt).join(",")}`);
  }
  const sessionMatch = /(\d+)회/.exec(rows[h - 1].slice(2, countAt).join(" "));
  if (!sessionMatch) throw new Error("attendance sheet: no 회기 in the header");
  const session = Number(sessionMatch[1]);

  const sittings: Sitting[] = [];
  for (let i = 2; i < countAt; i++) {
    const n = /^(\d+)차\(본회의\)$/.exec(head[i].replace(/\s/g, ""));
    const d = /(\d{4})년\s*(\d{1,2})월\s*(\d{1,2})일/.exec(dates[i]);
    if (!n || !d) throw new Error(`attendance sheet: column ${i + 1} is not a dated 본회의`);
    sittings.push({
      label: `제${session}회 제${Number(n[1])}차`,
      date: `${d[1]}-${d[2].padStart(2, "0")}-${d[3].padStart(2, "0")}`,
    });
  }
  if (sittings.length === 0) throw new Error("attendance sheet: no sittings");

  const errors: string[] = [];
  const members: SheetMember[] = [];
  for (const r of rows.slice(h + 2)) {
    const name = (r[0] ?? "").trim();
    if (!name) continue;
    const statuses = sittings.map((_, k) => {
      const v = (r[2 + k] ?? "").trim();
      return v === NOT_SEATED ? null : v;
    });
    const bad = statuses.filter((s) =>
      s !== null && !(ATTENDANCE_STATUSES as readonly string[]).includes(s)
    );
    if (bad.length) errors.push(`${name}: unknown status ${bad.join(",")}`);
    const seated = statuses.filter((s): s is string => s !== null);
    const mine = [
      seated.length,
      ...ATTENDANCE_STATUSES.map((k) => seated.filter((s) => s === k).length),
    ];
    const theirs = COUNT_HEADERS.map((_, i) => Number((r[countAt + i] ?? "").trim() || "0"));
    if (mine.join() !== theirs.join()) {
      errors.push(`${name}: cells give ${mine.join("/")} but the file says ${theirs.join("/")}`);
    }
    members.push({ name, statuses });
  }
  if (errors.length) throw new Error(`attendance sheet 제${session}회:\n${errors.join("\n")}`);
  if (new Set(members.map((m) => m.name)).size !== members.length) {
    throw new Error(`attendance sheet 제${session}회: a name appears twice`);
  }
  return { session, sittings, members };
}

/** One ALLNAMEMBER row, reduced to what name resolution needs. */
export interface MemberCandidate {
  code: string; // NAAS_CD (= MONA_CD)
  name: string; // NAAS_NM
  hanja: string; // NAAS_CH_NM
  terms: string; // GTELT_ERACO, e.g. "제21대, 제22대"
}

const HANJA = /[\u3400-\u9fff\uf900-\ufaff]/;

/**
 * Maps every name written in a file to one MONA_CD. `lookup(name)` returns ALLNAMEMBER rows
 * for a Hangul name. Throws listing every name it could not place.
 */
export async function resolveMonaCodes(
  names: string[],
  lookup: (hangulName: string) => Promise<MemberCandidate[]>,
): Promise<Map<string, string>> {
  const is22 = (c: MemberCandidate) => /제22대/.test(c.terms);
  const hanjaNames = new Set(names.filter((n) => HANJA.test(n)));
  const pool = new Map<string, MemberCandidate[]>();
  for (const n of new Set(names)) {
    if (!hanjaNames.has(n)) pool.set(n, (await lookup(n)).filter((c) => c.name === n && is22(c)));
  }
  const everyone = [...pool.values()].flat();
  const out = new Map<string, string>();
  const errors: string[] = [];
  for (const n of new Set(names)) {
    let found = hanjaNames.has(n) ? everyone.filter((c) => c.hanja === n) : pool.get(n) ?? [];
    if (found.length > 1 && !hanjaNames.has(n)) {
      found = found.filter((c) => !hanjaNames.has(c.hanja));
    }
    const codes = [...new Set(found.map((c) => c.code))];
    if (codes.length === 1) out.set(n, codes[0]);
    else errors.push(`${n}: ${codes.length ? `ambiguous ${codes.join("/")}` : "no 22대 member"}`);
  }
  if (errors.length) throw new Error(`cannot place members:\n${errors.join("\n")}`);
  return out;
}

export interface CsvMeta {
  fileName: string;
  fileSeq: number;
  postedAt: string;
  fetchedAt: string; // YYYY-MM-DD
}

/** The committed CSV for one 회기, header comments first. Rows by date, 차수, name. */
export function sessionCsv(
  sheet: AttendanceSheet,
  codes: Map<string, string>,
  meta: CsvMeta,
): string {
  const rows: string[][] = [];
  sheet.sittings.forEach((s, k) => {
    for (const m of sheet.members) {
      const status = m.statuses[k];
      if (status === null) continue;
      const code = codes.get(m.name);
      if (!code) throw new Error(`no MONA_CD for ${m.name}`);
      rows.push([code, m.name, s.date, s.label, status]);
    }
  });
  rows.sort((a, b) =>
    a[2].localeCompare(b[2]) || a[3].localeCompare(b[3], "ko", { numeric: true }) ||
    a[1].localeCompare(b[1], "ko")
  );
  const cell = (v: string) => /[",\n]/.test(v) ? `"${v.replace(/"/g, '""')}"` : v;
  return [
    `# 국회의원 본회의 출결현황 (국회사무처), ${meta.fileName.replace(/[",]/g, " ")}`,
    `# source: ${ATTENDANCE_SOURCE_URL}`,
    `# file: fileSeq=${meta.fileSeq} posted ${meta.postedAt}`,
    `# fetched: ${meta.fetchedAt}`,
    `# generated by scripts/fetch_attendance.ts; do not edit by hand`,
    "mona_cd,member_name,meeting_date,meeting_label,status",
    ...rows.map((r) => r.map(cell).join(",")),
    "",
  ].join("\n");
}

// ------------------------------------------------------------------ network (CLI only)

const PORTAL = "https://open.assembly.go.kr";
const UA = { "User-Agent": "DEMOCRACY-data-import" };

interface PortalFile {
  fileSeq: number;
  viewFileNm: string;
  fileExt: string;
  ftCrDttm: string;
}

export function sessionOfFileName(name: string): number | null {
  const m = /제\s*(\d+)\s*회/.exec(name);
  return m ? Number(m[1]) : null;
}

async function listFiles(): Promise<PortalFile[]> {
  const res = await fetch(`${PORTAL}/portal/data/file/searchFileData.do`, {
    method: "POST",
    headers: { ...UA, "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ infId: ATTENDANCE_DATASET, infSeq: "1", page: "1", rows: "500" }),
  });
  if (!res.ok) throw new Error(`file list: HTTP ${res.status}`);
  const json = await res.json() as { data?: PortalFile[] };
  if (!Array.isArray(json.data) || json.data.length === 0) throw new Error("file list: empty");
  return json.data;
}

async function download(f: PortalFile): Promise<Uint8Array> {
  const url = new URL(`${PORTAL}/portal/data/file/downloadFileData.do`);
  url.searchParams.set("infId", ATTENDANCE_DATASET);
  url.searchParams.set("infSeq", "1");
  url.searchParams.set("fileSeq", String(f.fileSeq));
  const res = await fetch(url, { headers: UA });
  if (!res.ok) throw new Error(`${f.viewFileNm}: HTTP ${res.status}`);
  return new Uint8Array(await res.arrayBuffer());
}

async function allNameMember(name: string, key: string | undefined): Promise<MemberCandidate[]> {
  const url = new URL(`${PORTAL}/portal/openapi/ALLNAMEMBER`);
  if (key) url.searchParams.set("KEY", key);
  url.searchParams.set("Type", "json");
  url.searchParams.set("pIndex", "1");
  url.searchParams.set("pSize", "100");
  url.searchParams.set("NAAS_NM", name);
  const res = await fetch(url, { headers: UA });
  if (!res.ok) throw new Error(`ALLNAMEMBER ${name}: HTTP ${res.status}`);
  const json = await res.json() as Record<string, unknown>;
  const parts = json.ALLNAMEMBER as { head?: { list_total_count?: number }[]; row?: unknown }[];
  if (!Array.isArray(parts)) return [];
  const total = parts[0]?.head?.find((x) => typeof x.list_total_count === "number")
    ?.list_total_count ?? 0;
  const rows = (parts.find((p) => Array.isArray(p.row))?.row ?? []) as Record<string, unknown>[];
  const out = rows.map((r) => ({
    code: String(r.NAAS_CD ?? ""),
    name: String(r.NAAS_NM ?? ""),
    hanja: String(r.NAAS_CH_NM ?? ""),
    terms: String(r.GTELT_ERACO ?? ""),
  }));
  if (out.length < total && !holdsEveryExactMatch(name, out)) {
    throw new Error(`ALLNAMEMBER ${name}: ${total} rows, got ${out.length}; set ASSEMBLY_API_KEY`);
  }
  return out;
}

/**
 * NAAS_NM is a prefix match and rows come sorted by name, so a cut-off page (the keyless
 * sample key stops at 5 rows) still holds every exact match once it reaches a longer name.
 */
export function holdsEveryExactMatch(name: string, rows: MemberCandidate[]): boolean {
  const sorted = rows.every((r, i) => i === 0 || rows[i - 1].name.localeCompare(r.name) <= 0);
  return sorted && rows.length > 0 && rows[rows.length - 1].name !== name;
}

if (import.meta.main) {
  const { flags } = parseFlags(Deno.args);
  const outDir = flags.out ?? "data/attendance_22";
  const fetchedAt = flags["fetched-at"] ??
    new Date(Date.now() + 9 * 3600_000).toISOString().slice(0, 10);
  const key = Deno.env.get("ASSEMBLY_API_KEY") || undefined;

  // Every 22대 file, always: names are resolved across all of them (see resolveMonaCodes).
  const files = (await listFiles())
    .filter((f) => f.fileExt.toLowerCase() === "xlsx")
    .map((f) => ({ f, session: sessionOfFileName(f.viewFileNm) }))
    .filter((x): x is { f: PortalFile; session: number } =>
      x.session !== null && x.session >= FIRST_22_SESSION
    )
    .sort((a, b) => a.session - b.session);
  if (files.length === 0) throw new Error("no 22대 .xlsx files in the dataset");
  if (new Set(files.map((x) => x.session)).size !== files.length) {
    throw new Error("two files for one 회기; check the dataset page");
  }

  const sheets = [];
  for (const { f, session } of files) {
    const sheet = parseAttendanceSheet(await readFirstSheet(await download(f)));
    if (sheet.session !== session) {
      throw new Error(`${f.viewFileNm}: the sheet says 제${sheet.session}회`);
    }
    sheets.push({ f, sheet });
  }

  const cache = new Map<string, MemberCandidate[]>();
  const codes = await resolveMonaCodes(
    sheets.flatMap(({ sheet }) => sheet.members.map((m) => m.name)),
    async (n) => {
      if (!cache.has(n)) cache.set(n, await allNameMember(n, key));
      return cache.get(n)!;
    },
  );

  await Deno.mkdir(outDir, { recursive: true });
  for (const { f, sheet } of sheets) {
    const csv = sessionCsv(sheet, codes, {
      fileName: f.viewFileNm,
      fileSeq: f.fileSeq,
      postedAt: f.ftCrDttm,
      fetchedAt,
    });
    await Deno.writeTextFile(`${outDir}/${sheet.session}.csv`, csv);
    console.error(
      `제${sheet.session}회: ${sheet.sittings.length} sittings, ${sheet.members.length} members`,
    );
  }
}
