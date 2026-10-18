// Curated content → SQL.
//
//   --kind pledges : pledges typed in by hand from 선거공보 / 5대공약 PDFs.
//                    Files live in data/pledges_22/, one per district.
//   --kind region  : a district's chronology, from the 구역표 or a district office's records.
//
// pledges JSON:
//   { "districtId": "nec-xxxxxxxx",
//     "source": { "sourceUrl": "https://policy.nec.go.kr/...", "fetchedAt": "2026-09-24T00:00:00Z",
//                 "publisher": "중앙선거관리위원회" },     // optional; defaults to the URL host
//     "monaCd": "ABC1234D",
//     "pledges": [ { "id": "mapo-b-01", "title": "...", "category": "교통",
//                    "status": "notJudged|fulfilled|inProgress|unfulfilled|reversed",
//                    "evidenceUrl": "https://...",           // required for reversed
//                    "billIds": ["PRC_..."],                 // bills cited as evidence
//                    "judgement": { "steps": [{ "actor": "...", "detail": "...", "stamp": "..." }],
//                                   "source": { "sourceUrl": "...", "fetchedAt": "..." } },
//                    "source": { "sourceUrl": "...", "fetchedAt": "..." } } ] }
//   Status is a curator's descriptive call backed by evidence; the backend
//   never scores or ranks. notJudged (「판정 전」) is a pledge listed from the
//   document with no call made: it must carry no judgement, evidenceUrl or
//   billIds, so a list-only board cannot smuggle a verdict in.
//
// region JSON:
//   { "districtId": "nec-xxxxxxxx", "source": {...},
//     "events": [ { "year": 1944 | null, "title": "...", "detail": "...",
//                   "source": {...} } ] }           // optional; defaults to the doc's source
//   data/region_22/ holds one per 22대 선거구 (선거구 변천 from the 구역표), built by
//   scripts/build_district_lineage.ts.
//
//   --kind parties : data/parties.json, party colours and 여당 periods (see the parties
//                    migration). One file for the whole country.
//
// parties JSON:
//   { "parties": [ { "name": "더불어민주당",              // as NEC / the Assembly spell it
//                    "color": "#RRGGBB" | null,         // null: no authoritative colour found
//                    "colorSource": { "sourceUrl": "...", "checkedAt": "2026-10-07" },
//                    "aliases": [], "predecessor": "새누리당", "note": "..." } ],
//     "rulingPeriods": [ { "startsOn": "2022-05-10", "endsOn": "2025-04-04" | null,
//                          "party": "국민의힘" | null,   // null: acting presidency
//                          "president": "윤석열", "note": "...", "sourceUrl": "..." } ] }
//
// Usage: deno run --allow-read scripts/import_curated.ts --kind pledges pledges.json > p.sql

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

const STATUSES = new Set(["notJudged", "fulfilled", "inProgress", "unfulfilled", "reversed"]);

export function pledgesToSql(doc: J): string {
  const districtId = String(doc.districtId ?? "");
  if (!isDistrictId(districtId)) throw new Error("districtId must look like nec-xxxxxxxx");
  const board = source(doc.source, "board");
  const list = Array.isArray(doc.pledges) ? (doc.pledges as J[]) : [];
  if (list.length === 0) throw new Error("pledges: empty");

  const rows: Record<string, SqlValue>[] = list.map((p, i) => {
    const f = `pledges[${i}]`;
    if (typeof p.id !== "string" || !p.id || typeof p.title !== "string" || !p.title) {
      throw new Error(`${f}: id and title required`);
    }
    if (!STATUSES.has(String(p.status))) throw new Error(`${f}: bad status`);
    if (
      p.status === "notJudged" &&
      (p.judgement !== undefined || p.evidenceUrl !== undefined ||
        (Array.isArray(p.billIds) && p.billIds.length > 0))
    ) {
      throw new Error(`${f}: notJudged carries no judgement, evidenceUrl or billIds`);
    }
    if (p.status === "reversed" && !isPresentableSourceUrl(p.evidenceUrl)) {
      throw new Error(`${f}: reversed requires evidenceUrl`);
    }
    const s = source(p.source, f);
    let judgement: SqlValue = null;
    if (p.judgement) {
      const j = p.judgement as J;
      source(j.source, `${f}.judgement`);
      const steps = Array.isArray(j.steps) ? (j.steps as J[]) : [];
      if (steps.length === 0 || steps.some((st) => typeof st.actor !== "string" || !st.actor)) {
        throw new Error(`${f}.judgement: every step needs an actor`);
      }
      judgement = j;
    }
    return {
      id: p.id,
      district_id: districtId,
      mona_cd: typeof doc.monaCd === "string" ? doc.monaCd : null,
      title: p.title,
      category: typeof p.category === "string" ? p.category : null,
      status: String(p.status),
      evidence_url: typeof p.evidenceUrl === "string" ? p.evidenceUrl : null,
      bill_ids: Array.isArray(p.billIds) ? p.billIds.map(String) : [],
      judgement,
      sort: i,
      source_url: s.url,
      publisher: s.publisher,
      fetched_at: s.at,
    };
  });

  return [
    "begin;",
    upsertSql("pledge_boards", [{
      district_id: districtId,
      source_url: board.url,
      publisher: board.publisher,
      fetched_at: board.at,
    }], ["district_id"]).trim(),
    `delete from public.pledges where district_id = ${lit(districtId)};`,
    upsertSql("pledges", rows, ["id"]).trim(),
    "commit;",
  ].join("\n") + "\n";
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

const HEX = /^#[0-9A-F]{6}$/;
const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

/**
 * data/parties.json → parties + ruling_periods. The whole file is the truth: periods are
 * replaced wholesale, parties upserted (a party is never deleted, since old results name it).
 * A colour needs its own source; a period needs a source and must not overlap another.
 */
export function partiesToSql(doc: J): string {
  const parties = Array.isArray(doc.parties) ? (doc.parties as J[]) : [];
  const periods = Array.isArray(doc.rulingPeriods) ? (doc.rulingPeriods as J[]) : [];
  if (parties.length === 0) throw new Error("parties: empty");
  const names = new Set<string>();
  const partyRows: Record<string, SqlValue>[] = parties.map((p, i) => {
    const f = `parties[${i}]`;
    if (typeof p.name !== "string" || p.name.trim() === "") throw new Error(`${f}: name required`);
    if (p.name === "무소속") throw new Error(`${f}: 무소속 is not a party`);
    if (names.has(p.name)) throw new Error(`${f}: duplicate ${p.name}`);
    names.add(p.name);
    let color: string | null = null;
    let sourceUrl: string | null = null;
    let checkedAt: string | null = null;
    if (p.color !== null && p.color !== undefined) {
      if (typeof p.color !== "string" || !HEX.test(p.color)) {
        throw new Error(`${f}: color must be #RRGGBB in upper case`);
      }
      const s = p.colorSource as J | undefined;
      if (!s || !isPresentableSourceUrl(s.sourceUrl) || !ISO_DATE.test(String(s.checkedAt))) {
        throw new Error(`${f}: a colour needs colorSource {sourceUrl, checkedAt: YYYY-MM-DD}`);
      }
      color = p.color;
      sourceUrl = s.sourceUrl;
      checkedAt = String(s.checkedAt);
    }
    const aliases = Array.isArray(p.aliases) ? p.aliases.map(String) : [];
    return {
      name: p.name,
      color,
      color_source_url: sourceUrl,
      color_checked_at: checkedAt,
      aliases,
      predecessor: typeof p.predecessor === "string" ? p.predecessor : null,
      note: typeof p.note === "string" ? p.note : null,
    };
  });
  for (const r of partyRows) {
    if (r.predecessor !== null && !names.has(r.predecessor as string)) {
      throw new Error(`${r.name}: predecessor ${r.predecessor} is not listed`);
    }
  }

  const periodRows: Record<string, SqlValue>[] = periods.map((p, i) => {
    const f = `rulingPeriods[${i}]`;
    if (!ISO_DATE.test(String(p.startsOn))) throw new Error(`${f}: startsOn YYYY-MM-DD`);
    if (p.endsOn !== null && !ISO_DATE.test(String(p.endsOn))) {
      throw new Error(`${f}: endsOn YYYY-MM-DD or null`);
    }
    if (p.endsOn !== null && String(p.endsOn) <= String(p.startsOn)) {
      throw new Error(`${f}: endsOn must be after startsOn`);
    }
    if (p.party !== null && !names.has(String(p.party))) {
      throw new Error(`${f}: party ${p.party} is not listed`);
    }
    if (typeof p.president !== "string" || !p.president) throw new Error(`${f}: president`);
    if (!isPresentableSourceUrl(p.sourceUrl)) throw new Error(`${f}: sourceUrl required`);
    return {
      starts_on: String(p.startsOn),
      ends_on: p.endsOn === null ? null : String(p.endsOn),
      party_name: p.party === null ? null : String(p.party),
      president: p.president,
      note: typeof p.note === "string" ? p.note : null,
      source_url: p.sourceUrl,
    };
  });
  const sorted = [...periodRows].sort((a, b) =>
    String(a.starts_on).localeCompare(String(b.starts_on))
  );
  sorted.forEach((r, i) => {
    const next = sorted[i + 1];
    if (!next) return;
    if (r.ends_on === null || String(r.ends_on) > String(next.starts_on)) {
      throw new Error(`rulingPeriods: ${r.starts_on} overlaps ${next.starts_on}`);
    }
  });

  return [
    "begin;",
    upsertSql("parties", partyRows, ["name"]).trim(),
    "delete from public.ruling_periods;",
    periodRows.length === 0 ? "" : upsertSql("ruling_periods", periodRows, []).trim(),
    "commit;",
  ].filter(Boolean).join("\n") + "\n";
}

if (import.meta.main) {
  const { flags, positional } = parseFlags(Deno.args);
  const doc = JSON.parse(await Deno.readTextFile(positional[0])) as J;
  if (flags.kind === "pledges") console.log(pledgesToSql(doc));
  else if (flags.kind === "region") console.log(regionToSql(doc));
  else if (flags.kind === "parties") console.log(partiesToSql(doc));
  else throw new Error("--kind pledges|region|parties");
}
