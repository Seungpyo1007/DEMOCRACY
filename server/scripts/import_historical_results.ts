// Historical 국회의원 지역구 results (e.g. data.go.kr 역대 선거 결과 CSV) →
// election_results, as SQL. Use when the API backfill (ingest-nec?mode=backfill)
// is not enough (older terms, or runner-up rows).
//
// Input CSV:
//   sg_id,sd_name,sgg_name,huboid,name,party,votes,share,is_winner
//   20160413,서울특별시,마포구을,100118xxx,가상 인물,다라당,52011,44.1,true
// huboid may be blank for file rows; a stable id "file-<sgId>-<sd>-<sgg>-<name>" is used.
//
// Usage:
//   deno run --allow-read scripts/import_historical_results.ts results.csv \
//     --source-url "https://www.data.go.kr/data/<id>/fileData.do" --fetched-at 2026-09-24 > results.sql

import { districtNameKey } from "../supabase/functions/_shared/district_names.ts";
import { parseCsvObjects } from "./lib/csv.ts";
import { parseFlags, requireHttpUrl, type SqlValue, upsertSql } from "./lib/sql.ts";

export function resultsToSql(csv: string, opts: { sourceUrl: string; fetchedAt: string }): string {
  const errors: string[] = [];
  const out: Record<string, SqlValue>[] = [];
  parseCsvObjects(csv).forEach((r, i) => {
    const line = i + 2;
    if (!/^\d{8}$/.test(r.sg_id ?? "")) return errors.push(`line ${line}: sg_id`);
    if (!r.sd_name || !r.sgg_name || !r.name) {
      return errors.push(`line ${line}: sd_name/sgg_name/name`);
    }
    const share = r.share === "" ? null : Number(r.share);
    const votes = r.votes === "" ? null : Number(r.votes.replace(/,/g, ""));
    if (
      (share !== null && !Number.isFinite(share)) || (votes !== null && !Number.isFinite(votes))
    ) {
      return errors.push(`line ${line}: votes/share not numeric`);
    }
    const sgg = r.sgg_name.replace(/\s+/g, "");
    out.push({
      sg_id: r.sg_id,
      sg_typecode: 2,
      huboid: r.huboid || `file-${r.sg_id}-${r.sd_name}-${sgg}-${r.name}`,
      sd_name: r.sd_name,
      sgg_name: sgg,
      name_key: districtNameKey(r.sd_name, sgg),
      name: r.name,
      party: r.party || null,
      votes,
      share,
      is_winner: /^(true|1|y|당선)$/i.test(r.is_winner ?? ""),
      source_url: opts.sourceUrl,
      publisher: "중앙선거관리위원회",
      fetched_at: opts.fetchedAt,
    });
  });
  if (errors.length) throw new Error(`results CSV invalid:\n${errors.join("\n")}`);
  return upsertSql("election_results", out, ["sg_id", "sg_typecode", "huboid"]);
}

if (import.meta.main) {
  const { flags, positional } = parseFlags(Deno.args);
  console.log(resultsToSql(await Deno.readTextFile(positional[0]), {
    sourceUrl: requireHttpUrl(flags["source-url"], "--source-url"),
    fetchedAt: new Date(flags["fetched-at"] ?? Date.now()).toISOString(),
  }));
}
