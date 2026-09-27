// Curated district_lineage → SQL: which past 선거구 (by name key) a 22대 district's past
// election rows come from, when it differs from the district's own name key.
//
// Input CSV (data/district_lineage_22.csv, built by scripts/build_district_lineage.ts):
//   district_id,display_name,sg_id,name_key,note
//   nec-bef89d01,경기 하남시 갑,20200415,경기하남시,제22대 구역 전체가 제21대 하남시 선거구 안
// display_name is for reading only. The output replaces every lineage row of the districts
// in the file for the elections in the file, so a rebuilt file drops rows it no longer has.
//
// Usage:
//   deno run --allow-read scripts/import_district_lineage.ts data/district_lineage_22.csv > l.sql

import { isDistrictId } from "../supabase/functions/_shared/district_names.ts";
import { parseCsvObjects } from "./lib/csv.ts";
import { lit, parseFlags, type SqlValue, upsertSql } from "./lib/sql.ts";

export function lineageToSql(csv: string): string {
  const errors: string[] = [];
  const rows: Record<string, SqlValue>[] = [];
  parseCsvObjects(csv).forEach((r, i) => {
    const line = i + 2;
    if (!isDistrictId(r.district_id ?? "")) return errors.push(`line ${line}: district_id`);
    if (!/^\d{8}$/.test(r.sg_id ?? "")) return errors.push(`line ${line}: sg_id`);
    if (!r.name_key || /\s/.test(r.name_key)) {
      return errors.push(`line ${line}: name_key must be a non-empty key without spaces`);
    }
    rows.push({
      district_id: r.district_id,
      sg_id: r.sg_id,
      name_key: r.name_key,
      note: r.note || null,
    });
  });
  if (errors.length) throw new Error(`lineage CSV invalid:\n${errors.join("\n")}`);
  if (rows.length === 0) throw new Error("lineage CSV: no rows");
  const ids = [...new Set(rows.map((r) => r.district_id as string))].sort();
  const sgIds = [...new Set(rows.map((r) => r.sg_id as string))].sort();
  return [
    "begin;",
    `delete from public.district_lineage where sg_id in (${sgIds.map(lit).join(", ")})` +
    ` and district_id in (${ids.map(lit).join(", ")});`,
    upsertSql("district_lineage", rows, ["district_id", "sg_id", "name_key"]).trim(),
    "commit;",
  ].join("\n") + "\n";
}

if (import.meta.main) {
  const { positional } = parseFlags(Deno.args);
  console.log(lineageToSql(await Deno.readTextFile(positional[0])));
}
