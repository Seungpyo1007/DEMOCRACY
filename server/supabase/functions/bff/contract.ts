// A TS mirror of the app's Dart parsers' required-field rules
// (app/lib/src/core/provenance/source_metadata.dart, features/district/domain/*,
// features/history/domain/history_record.dart, features/pledges/domain/pledge.dart).
// Returns a list of violations; empty = the app would parse it.
//
// One deliberate difference: `record.attendance` / `record.votes` are optional
// (the app is making them optional); `record.bills` stays required.

type J = Record<string, unknown>;
const isMap = (v: unknown): v is J => v !== null && typeof v === "object" && !Array.isArray(v);
const nonEmpty = (v: unknown): v is string => typeof v === "string" && v.trim() !== "";

function source(v: unknown, field: string, errs: string[]) {
  if (!isMap(v)) return errs.push(`${field}: no source object`);
  if (!nonEmpty(v.sourceUrl)) return errs.push(`${field}: sourceUrl missing`);
  let u: URL;
  try {
    u = new URL(v.sourceUrl);
  } catch {
    return errs.push(`${field}: sourceUrl not a URL`);
  }
  if (!["http:", "https:"].includes(u.protocol) || u.host === "") {
    errs.push(`${field}: sourceUrl not absolute http(s)`);
  }
  if (!nonEmpty(v.fetchedAt) || Number.isNaN(Date.parse(v.fetchedAt))) {
    errs.push(`${field}: fetchedAt missing or unparseable`);
  }
}

function sourcedValue(v: unknown, field: string, errs: string[]) {
  if (!isMap(v)) return errs.push(`${field}: no value object`);
  if (typeof v.value !== "number") errs.push(`${field}: value not a number`);
  source(v, field, errs);
}

function series(v: unknown, field: string, errs: string[]) {
  if (!isMap(v)) return errs.push(`${field}: series not an object`);
  const pts = Array.isArray(v.points) ? v.points : [];
  if (pts.length === 0) errs.push(`${field}: series needs at least one point`);
  pts.forEach((p, i) => {
    if (!isMap(p) || !nonEmpty(p.label) || typeof p.value !== "number") {
      errs.push(`${field}.points[${i}]: needs label and numeric value`);
    }
  });
  source(v.source, field, errs);
}

function politician(v: unknown, field: string, errs: string[]) {
  if (!isMap(v)) return errs.push(`${field}: not an object`);
  if (typeof v.id !== "string" || typeof v.name !== "string") {
    errs.push(`${field}: id and name are required`);
  }
  for (const k of ["party", "summary", "portraitUrl"]) {
    if (v[k] !== undefined && v[k] !== null && typeof v[k] !== "string") {
      errs.push(`${field}.${k}: must be a string`);
    }
  }
  if (Array.isArray(v.stats)) {
    v.stats.forEach((s, i) => {
      if (!isMap(s) || !nonEmpty(s.label)) return errs.push(`${field}.stats[${i}]: label required`);
      sourcedValue(s.value, `${field}.stats.${s.label}`, errs);
    });
  }
  if (isMap(v.record)) {
    const r = v.record;
    if (!isMap(r.bills)) {
      errs.push(`${field}.record.bills: required when record is present`);
    } else {
      const items = Array.isArray(r.bills.items) ? r.bills.items : [];
      items.forEach((b, i) => {
        if (!isMap(b) || !nonEmpty(b.id) || !nonEmpty(b.title)) {
          errs.push(`${field}.record.bills.items[${i}]: needs id and title`);
        }
      });
      source(r.bills.source, `${field}.record.bills`, errs);
    }
    if (r.attendance !== undefined) series(r.attendance, `${field}.record.attendance`, errs);
    if (r.votes !== undefined) series(r.votes, `${field}.record.votes`, errs);
  }
}

function district(v: unknown, errs: string[]) {
  if (!isMap(v)) return errs.push("district: block required");
  if (!nonEmpty(v.id) || !nonEmpty(v.displayName)) errs.push("district: id and displayName");
}

export function validateDistrictProfile(json: unknown): string[] {
  const errs: string[] = [];
  if (!isMap(json)) return ["profile: not an object"];
  district(json.district, errs);
  politician(json.incumbent ?? {}, "incumbent", errs);
  if (json.candidates !== undefined && !Array.isArray(json.candidates)) {
    errs.push("candidates: not a list");
  }
  (Array.isArray(json.candidates) ? json.candidates : []).forEach((c, i) =>
    politician(c, `candidates[${i}]`, errs)
  );
  source(json.source, "district", errs);
  return errs;
}

export function validateHistoryRecord(json: unknown): string[] {
  const errs: string[] = [];
  if (!isMap(json)) return ["history: not an object"];
  district(json.district, errs);

  const region = json.region;
  if (!isMap(region)) {
    errs.push("region: block required");
  } else {
    (Array.isArray(region.events) ? region.events : []).forEach((e, i) => {
      if (!isMap(e) || !nonEmpty(e.title)) return errs.push(`region.events[${i}]: title`);
      if (e.year !== null && e.year !== undefined && !Number.isInteger(e.year)) {
        errs.push(`region.events[${i}]: year neither int nor null`);
      }
    });
    source(region.source, "region", errs);
  }

  const elections = json.elections;
  if (!isMap(elections)) {
    errs.push("elections: block required");
  } else {
    (Array.isArray(elections.rows) ? elections.rows : []).forEach((r, i) => {
      if (!isMap(r) || !Number.isInteger(r.term) || !Number.isInteger(r.year)) {
        return errs.push(`elections.rows[${i}]: term and year`);
      }
      if (r.ongoing === true) return;
      const w = r.winner;
      if (!isMap(w) || !nonEmpty(w.name) || typeof r.share !== "number") {
        errs.push(`elections.rows[${i}]: decided row needs winner and share`);
      }
    });
    source(elections.source, "elections", errs);
  }

  const leg = json.legislator;
  if (!isMap(leg)) {
    errs.push("legislator: block required");
  } else {
    const inc = leg.incumbent;
    if (!isMap(inc) || typeof inc.id !== "string" || typeof inc.name !== "string") {
      errs.push("legislator.incumbent: id and name");
    }
    (Array.isArray(leg.events) ? leg.events : []).forEach((e, i) => {
      if (!isMap(e) || !nonEmpty(e.mark) || !nonEmpty(e.title)) {
        errs.push(`legislator.events[${i}]: mark and title`);
      }
    });
    source(leg.source, "legislator", errs);
  }
  return errs;
}

export function validatePledgeBoard(json: unknown): string[] {
  const errs: string[] = [];
  if (!isMap(json)) return ["pledges: not an object"];
  (Array.isArray(json.pledges) ? json.pledges : []).forEach((p, i) => {
    const f = `pledges[${i}]`;
    if (!isMap(p) || typeof p.id !== "string" || !nonEmpty(p.title)) {
      return errs.push(`${f}: id and title`);
    }
    if (p.status === "reversed") {
      let okUrl = false;
      try {
        okUrl = typeof p.evidenceUrl === "string" && !!new URL(p.evidenceUrl);
      } catch { /* invalid */ }
      if (!okUrl) errs.push(`${f}: reversed requires evidenceUrl`);
    }
    source(p.source, f, errs);
    const j = p.judgement;
    if (isMap(j) && Array.isArray(j.steps) && j.steps.length > 0) {
      j.steps.forEach((s, k) => {
        if (!isMap(s) || !nonEmpty(s.actor)) errs.push(`${f}.judgement.steps[${k}]: actor`);
      });
      source(j.source, `${f}.judgement`, errs);
    }
  });
  source(json.source, "pledgeBoard", errs);
  return errs;
}

/**
 * DirectionReport (features/ai_match/domain/direction_report.dart). Each block
 * is optional -- null or absent is 준비 중 -- but a block that is present must
 * parse. The BFF serves `trend` only; `stances` and `issues` are model output
 * and must stay null until something produces them with a disclosure.
 */
export function validateDirectionReport(json: unknown): string[] {
  const errs: string[] = [];
  if (!isMap(json)) return ["direction: not an object"];
  const t = json.trend;
  if (t !== null && t !== undefined) {
    if (!isMap(t)) {
      errs.push("trend: not an object");
    } else {
      for (const k of ["legislatorName", "fromTerm", "toTerm", "summary"]) {
        if (typeof t[k] !== "string") errs.push(`trend.${k}: must be a string`);
      }
      if (!Number.isInteger(t.billCount)) errs.push("trend.billCount: must be an int");
      for (const k of ["fromCount", "toCount", "excludedCount"]) {
        if (t[k] !== undefined && t[k] !== null && !Number.isInteger(t[k])) {
          errs.push(`trend.${k}: must be an int when present`);
        }
      }
      (Array.isArray(t.fields) ? t.fields : []).forEach((f, i) => {
        const share = (v: unknown) => v === null || typeof v === "number";
        if (!isMap(f) || !nonEmpty(f.label) || !share(f.from) || !share(f.to)) {
          return errs.push(`trend.fields[${i}]: needs label and from/to as number or null`);
        }
        if (f.from === null && f.to === null) errs.push(`trend.fields[${i}]: no term at all`);
      });
      source(t.source, "direction.trend", errs);
    }
  }
  for (const k of ["stances", "issues"]) {
    if (json[k] !== null && json[k] !== undefined) {
      errs.push(`${k}: model output is not served`);
    }
  }
  return errs;
}

export function validateAddressSuggestions(json: unknown): string[] {
  const errs: string[] = [];
  if (!isMap(json) || !Array.isArray(json.suggestions)) return ["suggestions: list required"];
  json.suggestions.forEach((s, i) => {
    if (!isMap(s) || !nonEmpty(s.address)) return errs.push(`suggestions[${i}]: address`);
    const d = s.district;
    if (!isMap(d) || !nonEmpty(d.id) || !nonEmpty(d.displayName)) {
      errs.push(`suggestions[${i}]: district id/displayName`);
    }
  });
  return errs;
}

/** The envelope every BFF response shares. */
export function validateEnvelope(json: unknown, expectError: boolean): string[] {
  const errs: string[] = [];
  if (!isMap(json)) return ["envelope: not an object"];
  if (
    !nonEmpty(json.servedAt) || !/Z$/.test(json.servedAt) || Number.isNaN(Date.parse(json.servedAt))
  ) {
    errs.push("envelope: servedAt must be ISO-8601 UTC");
  }
  if (expectError) {
    const e = json.error;
    const codes = [
      "not_found",
      "no_match",
      "not_curated",
      "bad_request",
      "upstream",
      "internal",
      "unauthorized",
      "forbidden",
      "consent_required",
      "conflict",
      "too_soon",
    ];
    if (!isMap(e) || !codes.includes(e.code as string) || typeof e.message !== "string") {
      errs.push("envelope: error {code, message}");
    }
  } else if (!isMap(json.data)) {
    errs.push("envelope: data object required");
  }
  return errs;
}
