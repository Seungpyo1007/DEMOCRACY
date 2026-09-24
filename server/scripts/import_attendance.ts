// 본회의 출결 (Assembly file dataset, not an API) → plenary_attendance, as SQL.
//
// The Assembly publishes plenary attendance as downloadable files whose layout
// varies by session. A human converts the file to this CSV first:
//   mona_cd,meeting_date,meeting_label,status
//   ABC1234D,2026-03-05,제432회 제3차,출석
// status keeps the source wording (출석 / 결석 / 청가 / 출장 / ...). Only 출석
// counts as attended in the BFF's descriptive rate; nothing else is inferred.
//
// Usage:
//   deno run --allow-read scripts/import_attendance.ts attendance.csv \
//     --source-url "<the dataset page on open.assembly.go.kr>" --fetched-at 2026-09-24 > att.sql

import { parseCsvObjects } from "./lib/csv.ts";
import { parseFlags, requireHttpUrl, type SqlValue, upsertSql } from "./lib/sql.ts";

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

if (import.meta.main) {
  const { flags, positional } = parseFlags(Deno.args);
  console.log(attendanceToSql(await Deno.readTextFile(positional[0]), {
    sourceUrl: requireHttpUrl(flags["source-url"], "--source-url"),
    fetchedAt: new Date(flags["fetched-at"] ?? Date.now()).toISOString(),
  }));
}
