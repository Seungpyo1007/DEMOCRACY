// 본회의 출결 (Assembly file dataset, not an API) → plenary_attendance, as SQL.
//
// Source: 열린국회정보 「국회의원 본회의 출결현황」, one .xlsx per 회기
//   https://open.assembly.go.kr/portal/data/service/selectServicePage.do/O4Q5B50011905O18367
// scripts/fetch_attendance.ts converts those files to data/attendance_22/<회기>.csv:
//   mona_cd,member_name,meeting_date,meeting_label,status
//   ABC1234D,홍길동,2026-03-05,제432회 제3차,출석
// member_name is optional and only there for review. status keeps the source wording
// (출석 / 결석 / 청가 / 출장 / 결석신고서); a sitting the person was not a member for has no row.
// Only 출석 counts as attended in the BFF's rate; nothing else is inferred.
//
// Usage (from server/):
//   deno run --allow-read scripts/import_attendance.ts data/attendance_22 > att.sql
// Arguments are CSV files or directories of them. --source-url / --fetched-at override the
// `# source:` / `# fetched:` header lines the committed files carry.

import { parseCsvObjects } from "./lib/csv.ts";
import { parseFlags, requireHttpUrl, type SqlValue, upsertSql } from "./lib/sql.ts";

/** Every value the source uses in a sitting cell (besides "-", not a member then). */
export const ATTENDANCE_STATUSES = ["출석", "결석", "청가", "출장", "결석신고서"] as const;

export function parseAttendance(
  csv: string,
  opts: { sourceUrl: string; fetchedAt: string },
): Record<string, SqlValue>[] {
  const errors: string[] = [];
  const out = new Map<string, Record<string, SqlValue>>();
  parseCsvObjects(csv).forEach((r, i) => {
    const line = i + 2;
    if (!r.mona_cd) return errors.push(`line ${line}: mona_cd`);
    if (!/^\d{4}-\d{2}-\d{2}$/.test(r.meeting_date ?? "")) {
      return errors.push(`line ${line}: meeting_date`);
    }
    if (!r.meeting_label || !r.status) return errors.push(`line ${line}: meeting_label/status`);
    if (!(ATTENDANCE_STATUSES as readonly string[]).includes(r.status)) {
      return errors.push(`line ${line}: status ${r.status}`);
    }
    out.set(`${r.mona_cd}|${r.meeting_date}|${r.meeting_label}`, {
      mona_cd: r.mona_cd,
      meeting_date: r.meeting_date,
      meeting_label: r.meeting_label,
      status: r.status,
      source_url: opts.sourceUrl,
      publisher: "국회사무처",
      fetched_at: opts.fetchedAt,
    });
  });
  if (errors.length) throw new Error(`attendance CSV invalid:\n${errors.join("\n")}`);
  return [...out.values()];
}

/** `# source: <url>` and `# fetched: <date>` from a file's leading comment lines. */
export function attendanceHeader(csv: string): { sourceUrl?: string; fetchedAt?: string } {
  const out: { sourceUrl?: string; fetchedAt?: string } = {};
  for (const line of csv.replace(/^﻿/, "").split(/\r?\n/)) {
    if (!line.startsWith("#")) break;
    const m = /^#\s*(source|fetched):\s*(\S+)/.exec(line);
    if (m?.[1] === "source") out.sourceUrl = m[2];
    if (m?.[1] === "fetched") out.fetchedAt = m[2];
  }
  return out;
}

export function attendanceToSql(
  csv: string,
  opts: { sourceUrl: string; fetchedAt: string },
): string {
  return upsertSql("plenary_attendance", parseAttendance(csv, opts), [
    "mona_cd",
    "meeting_date",
    "meeting_label",
  ]);
}

async function csvPaths(args: string[]): Promise<string[]> {
  const out: string[] = [];
  for (const a of args) {
    if ((await Deno.stat(a)).isDirectory) {
      const names: string[] = [];
      for await (const e of Deno.readDir(a)) {
        if (e.isFile && e.name.endsWith(".csv")) names.push(`${a.replace(/\/$/, "")}/${e.name}`);
      }
      out.push(...names.sort());
    } else {
      out.push(a);
    }
  }
  return out;
}

if (import.meta.main) {
  const { flags, positional } = parseFlags(Deno.args);
  const paths = await csvPaths(positional);
  if (paths.length === 0) throw new Error("no attendance CSV given");
  for (const path of paths) {
    const csv = await Deno.readTextFile(path);
    const header = attendanceHeader(csv);
    const fetched = flags["fetched-at"] ?? header.fetchedAt ?? "";
    if (!fetched || Number.isNaN(Date.parse(fetched))) {
      throw new Error(`${path}: --fetched-at or a '# fetched:' line is required`);
    }
    console.log(`-- ${path}`);
    console.log(attendanceToSql(csv, {
      sourceUrl: requireHttpUrl(flags["source-url"] ?? header.sourceUrl, "--source-url"),
      fetchedAt: new Date(fetched).toISOString(),
    }));
  }
}
