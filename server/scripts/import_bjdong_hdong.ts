// 법정동 → 행정동 bridge, as SQL on stdout.
//
// Accepts either
//  (a) the 행정안전부 "행정동·법정동 코드 매핑" (KIKmix) file saved as UTF-8 CSV:
//      행정동코드,시도명,시군구명,읍면동명,법정동코드,동리명,생성일자,말소일자
//      Rows with a 말소일자 are skipped. 리-level 법정동 codes are kept as-is.
//  (b) a simple CSV: bjd_code,hdong_code,hdong_name
//
// Usage:
//   deno run --allow-read scripts/import_bjdong_hdong.ts KIKmix.csv \
//     --source-url "https://www.mois.go.kr/..." --fetched-at 2026-09-24 > bridge.sql

import { parseCsvObjects } from "./lib/csv.ts";
import { parseFlags, requireHttpUrl, type SqlValue, upsertSql } from "./lib/sql.ts";

export function parseBridge(
  csv: string,
  opts: { sourceUrl: string; fetchedAt: string },
): Record<string, SqlValue>[] {
  const rows = parseCsvObjects(csv);
  const out = new Map<string, Record<string, SqlValue>>();
  for (const r of rows) {
    const bjd = r["bjd_code"] ?? r["법정동코드"];
    const hd = r["hdong_code"] ?? r["행정동코드"];
    const name = r["hdong_name"] ?? r["읍면동명"] ?? null;
    if (r["말소일자"]) continue;
    if (!/^\d{10}$/.test(bjd ?? "") || !/^\d{10}$/.test(hd ?? "")) continue;
    out.set(`${bjd}|${hd}`, {
      bjd_code: bjd,
      hdong_code: hd,
      hdong_name: name || null,
      source_url: opts.sourceUrl,
      fetched_at: opts.fetchedAt,
    });
  }
  return [...out.values()];
}

export function bridgeToSql(csv: string, opts: { sourceUrl: string; fetchedAt: string }): string {
  return upsertSql("bjdong_hdong", parseBridge(csv, opts), ["bjd_code", "hdong_code"]);
}

if (import.meta.main) {
  const { flags, positional } = parseFlags(Deno.args);
  console.log(bridgeToSql(await Deno.readTextFile(positional[0]), {
    sourceUrl: requireHttpUrl(flags["source-url"], "--source-url"),
    fetchedAt: new Date(flags["fetched-at"] ?? Date.now()).toISOString(),
  }));
}
