// Curated content → SQL.
//
//   --kind region  : a district's chronology, from the 구역표 or a district office's records.
//
// region JSON:
//   { "districtId": "nec-xxxxxxxx", "source": {...},
//     "events": [ { "year": 1944 | null, "title": "...", "detail": "...",
//                   "source": {...} } ] }           // optional; defaults to the doc's source
//   data/region_22/ holds one per 22대 선거구 (선거구 변천 from the 구역표), built by
//   scripts/build_district_lineage.ts.
//
// Parties, 여당 periods and pledge lists used to be imported here too (--kind parties and
// --kind pledges). They come from KoreaPoliticsAPI releases now, through the ingest-kpa
// function.
//
// Usage: deno run --allow-read scripts/import_curated.ts --kind region region.json > r.sql

import { isDistrictId } from "../supabase/functions/_shared/district_names.ts";
import { isPresentableSourceUrl, isTimestamp } from "../supabase/functions/_shared/provenance.ts";
import { lit, parseFlags, type SqlValue, upsertSql } from "./lib/sql.ts";

type J = Record<string, unknown>;

function source(v: unknown, field: string): { url: string; at: string; publisher: string } {
  const s = v as J | undefined;
  if (!s || !isPresentableSourceUrl(s.sourceUrl) || !isTimestamp(s.fetchedAt)) {
    throw new Error(`${field}: source {sourceUrl, fetchedAt} required`);
  }
  if (s.publisher !== undefined && (typeof s.publisher !== "string" || !s.publisher.trim())) {
    throw new Error(`${field}: publisher must be a non-empty string when given`);
  }
  return {
    url: s.sourceUrl,
    at: new Date(s.fetchedAt).toISOString(),
    publisher: typeof s.publisher === "string"
      ? s.publisher.trim()
      : new URL(s.sourceUrl).host.replace(/^www\./, ""),
  };
}

export function regionToSql(doc: J): string {
  const districtId = String(doc.districtId ?? "");
  if (!isDistrictId(districtId)) throw new Error("districtId must look like nec-xxxxxxxx");
  const s = source(doc.source, "region");
  const events = Array.isArray(doc.events) ? (doc.events as J[]) : [];
  const rows: Record<string, SqlValue>[] = events.map((e, i) => {
    if (typeof e.title !== "string" || !e.title) throw new Error(`events[${i}]: title required`);
    if (e.year !== null && e.year !== undefined && !Number.isInteger(e.year)) {
      throw new Error(`events[${i}]: year must be an integer or null`);
    }
    const es = e.source === undefined ? s : source(e.source, `events[${i}]`);
    return {
      district_id: districtId,
      year: (e.year as number | null | undefined) ?? null,
      title: e.title,
      detail: typeof e.detail === "string" ? e.detail : null,
      sort: i,
      source_url: es.url,
      publisher: es.publisher,
      fetched_at: es.at,
    };
  });
  const insert = rows.length === 0 ? "" : upsertSql("region_events", rows, []).trim();
  return [
    "begin;",
    upsertSql("region_timelines", [{
      district_id: districtId,
      source_url: s.url,
      publisher: s.publisher,
      fetched_at: s.at,
    }], ["district_id"]).trim(),
    `delete from public.region_events where district_id = ${lit(districtId)};`,
    insert,
    "commit;",
  ].filter(Boolean).join("\n") + "\n";
}

if (import.meta.main) {
  const { flags, positional } = parseFlags(Deno.args);
  const doc = JSON.parse(await Deno.readTextFile(positional[0])) as J;
  if (flags.kind === "region") console.log(regionToSql(doc));
  else throw new Error("--kind region (parties and pledges come from ingest-kpa)");
}
