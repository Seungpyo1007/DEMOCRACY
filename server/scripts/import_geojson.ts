// 22대 선거구 boundaries (GeoJSON FeatureCollection) → district_shapes, as SQL.
// Candidate source: OhmyNews `2024_22_elec_map` — its license must be confirmed
// and passed as --license before anything is imported.
//
// Each feature needs the 시도 and 선거구 names in its properties; name the
// property keys with --sd-prop / --sgg-prop (defaults: SIDO, SGG). 시도 may be
// short ("서울") or full ("서울특별시"); matching uses the same name key as the
// rest of the backend, so ids line up with districts.id.
//
// Usage:
//   deno run --allow-read scripts/import_geojson.ts 2024_22_elec.geojson \
//     --sd-prop SIDO_SGG --sgg-prop SGG --license "CC BY 4.0, OhmyNews" \
//     --source-url "https://github.com/OhmyNews/2024_22_elec_map" --districts districts.csv > shapes.sql
//
// --districts: CSV `id,name_key` exported from the districts table
// (`\copy (select id, name_key from districts) to districts.csv csv header`).

import { districtNameKey } from "../supabase/functions/_shared/district_names.ts";
import { parseCsvObjects } from "./lib/csv.ts";
import { parseFlags, requireHttpUrl, type SqlValue, upsertSql } from "./lib/sql.ts";

export function geojsonToSql(
  geojson: unknown,
  opts: {
    sdProp: string;
    sggProp: string;
    idByKey: Map<string, string>;
    license: string;
    sourceUrl: string;
    fetchedAt: string;
  },
): { sql: string; unmatched: string[] } {
  const features = (geojson as { features?: unknown[] })?.features;
  if (!Array.isArray(features)) throw new Error("not a FeatureCollection");
  if (!opts.license.trim()) throw new Error("--license is required");
  const out: Record<string, SqlValue>[] = [];
  const unmatched: string[] = [];
  for (const f of features) {
    const feat = f as { properties?: Record<string, unknown>; geometry?: unknown };
    const sd = String(feat.properties?.[opts.sdProp] ?? "").trim();
    const sgg = String(feat.properties?.[opts.sggProp] ?? "").trim();
    const id = opts.idByKey.get(districtNameKey(sd, sgg));
    if (!id || !feat.geometry) {
      unmatched.push(`${sd} ${sgg}`);
      continue;
    }
    out.push({
      district_id: id,
      geojson: { type: "Feature", properties: { id }, geometry: feat.geometry },
      license_note: opts.license,
      source_url: opts.sourceUrl,
      fetched_at: opts.fetchedAt,
    });
  }
  return { sql: upsertSql("district_shapes", out, ["district_id"]), unmatched };
}

if (import.meta.main) {
  const { flags, positional } = parseFlags(Deno.args);
  const idByKey = new Map(
    parseCsvObjects(await Deno.readTextFile(flags["districts"])).map((r) => [r.name_key, r.id]),
  );
  const { sql, unmatched } = geojsonToSql(JSON.parse(await Deno.readTextFile(positional[0])), {
    sdProp: flags["sd-prop"] ?? "SIDO",
    sggProp: flags["sgg-prop"] ?? "SGG",
    idByKey,
    license: flags["license"] ?? "",
    sourceUrl: requireHttpUrl(flags["source-url"], "--source-url"),
    fetchedAt: new Date(flags["fetched-at"] ?? Date.now()).toISOString(),
  });
  for (const u of unmatched) console.error(`unmatched feature: ${u}`);
  console.log(sql);
}
