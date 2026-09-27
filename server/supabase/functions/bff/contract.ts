// A TS mirror of the app's Dart parsers' required-field rules
// (app/lib/src/core/provenance/source_metadata.dart, features/district/domain/*,
// features/history/domain/history_record.dart, features/pledges/domain/pledge.dart,
// features/results/domain/*, features/reviews/domain/resident_review.dart,
// features/reviews/data/remote_*).
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

/** KstInstant.parse: parseable, and stating its offset (Z or ±hh:mm). */
function offsetTimestamp(v: unknown): boolean {
  return nonEmpty(v) && !Number.isNaN(Date.parse(v)) && /(Z|[+-]\d{2}:?\d{2})$/.test(v);
}

const isRate = (v: unknown, max = 100) => typeof v === "number" && v >= 0 && v <= max;

/** PollDisclosure.fromJson: all the 제108조제5항 items, or the series does not parse. */
function pollDisclosure(v: unknown, field: string, errs: string[]) {
  if (!isMap(v)) return errs.push(`${field}.disclosure: required`);
  for (const k of ["client", "pollster", "samplingMethod", "surveyMethod"]) {
    if (!nonEmpty(v[k])) errs.push(`${field}.disclosure.${k}: required`);
  }
  for (const k of ["fieldStart", "fieldEnd"]) {
    if (!offsetTimestamp(v[k])) errs.push(`${field}.disclosure.${k}: timestamp with offset`);
  }
  if (!Number.isInteger(v.sampleSize) || (v.sampleSize as number) <= 0) {
    errs.push(`${field}.disclosure.sampleSize: positive int`);
  }
  if (!isRate(v.marginOfError, 50)) errs.push(`${field}.disclosure.marginOfError: 0..50`);
  for (const k of ["confidenceLevel", "responseRate"]) {
    if (!isRate(v[k])) errs.push(`${field}.disclosure.${k}: 0..100`);
  }
  for (const k of ["questionnaire", "nesdcRegistration"]) {
    let okUrl = false;
    try {
      const u = new URL(v[k] as string);
      okUrl = ["http:", "https:"].includes(u.protocol) && u.host !== "";
    } catch { /* invalid */ }
    if (!okUrl) errs.push(`${field}.disclosure.${k}: absolute http(s) URL`);
  }
  source(v.source, `${field}.disclosure`, errs);
}

/**
 * RawElectionResults.fromJson (features/results/domain/election_results.dart,
 * election_schedule.dart, poll_disclosure.dart). The schedule key must be
 * present: null states that no election is pending, absence fails to parse.
 */
export function validateElectionResults(json: unknown): string[] {
  const errs: string[] = [];
  if (!isMap(json)) return ["results: not an object"];

  if (!("electionSchedule" in json)) {
    errs.push("electionSchedule: key required (null when no election is pending)");
  } else if (json.electionSchedule !== null) {
    const s = json.electionSchedule;
    if (!isMap(s)) {
      errs.push("electionSchedule: object or null");
    } else {
      if (!offsetTimestamp(s.pollsClose)) errs.push("electionSchedule.pollsClose: with offset");
      if (
        s.electionName !== undefined && s.electionName !== null &&
        typeof s.electionName !== "string"
      ) {
        errs.push("electionSchedule.electionName: must be a string");
      }
      source(s.source, "electionSchedule", errs);
    }
  }
  if (
    json.electionName !== undefined && json.electionName !== null &&
    typeof json.electionName !== "string"
  ) {
    errs.push("electionName: must be a string");
  }
  if (json.live !== undefined && json.live !== null && typeof json.live !== "boolean") {
    errs.push("live: must be a boolean");
  }

  (Array.isArray(json.districts) ? json.districts : []).forEach((d, i) => {
    const f = `districts[${i}]`;
    if (!isMap(d) || !nonEmpty(d.districtId) || typeof d.districtName !== "string") {
      return errs.push(`${f}: districtId and districtName`);
    }
    if (typeof d.countedShare !== "number") errs.push(`${f}: countedShare not a number`);
    (Array.isArray(d.tallies) ? d.tallies : []).forEach((t, k) => {
      if (!isMap(t) || !nonEmpty(t.name) || typeof t.share !== "number") {
        return errs.push(`${f}.tallies[${k}]: name and share`);
      }
      if (t.party !== undefined && t.party !== null && typeof t.party !== "string") {
        errs.push(`${f}.tallies[${k}].party: must be a string`);
      }
    });
    source(d.source, f, errs);
  });

  (Array.isArray(json.historical) ? json.historical : []).forEach((p, i) => {
    if (!isMap(p) || !Number.isInteger(p.year) || typeof p.share !== "number") {
      errs.push(`historical[${i}]: int year and numeric share`);
    }
  });

  (Array.isArray(json.polls) ? json.polls : []).forEach((p, i) => {
    const f = `polls[${i}]`;
    if (!isMap(p) || !nonEmpty(p.label)) return errs.push(`${f}: label`);
    (Array.isArray(p.points) ? p.points : []).forEach((pt, k) => {
      if (!isMap(pt) || !Number.isInteger(pt.year) || typeof pt.share !== "number") {
        errs.push(`${f}.points[${k}]: int year and numeric share`);
      }
    });
    pollDisclosure(p.disclosure, f, errs);
  });
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

/** ReviewBoard.fromJson: summary {average, respondents:int, axes[]}, reviews[]. */
export function validateReviewBoard(json: unknown): string[] {
  const errs: string[] = [];
  if (!isMap(json)) return ["reviews: not an object"];
  const s = json.summary;
  if (!isMap(s) || typeof s.average !== "number" || !Number.isInteger(s.respondents)) {
    errs.push("summary: average and integer respondents");
  } else {
    (Array.isArray(s.axes) ? s.axes : []).forEach((a, i) => {
      if (!isMap(a) || typeof a.label !== "string" || typeof a.score !== "number") {
        errs.push(`summary.axes[${i}]: label and score`);
      }
    });
  }
  (Array.isArray(json.reviews) ? json.reviews : []).forEach((r, i) => {
    if (
      !isMap(r) || typeof r.id !== "string" || typeof r.body !== "string" ||
      typeof r.score !== "number"
    ) {
      return errs.push(`reviews[${i}]: id, body and score`);
    }
    if (r.author !== undefined && r.author !== null && typeof r.author !== "string") {
      errs.push(`reviews[${i}].author: must be a string`);
    }
    if (r.verifiedResident !== undefined && typeof r.verifiedResident !== "boolean") {
      errs.push(`reviews[${i}].verifiedResident: must be a boolean`);
    }
  });
  return errs;
}

/** The channel and threads: messages need id, author and body; threads id and title. */
export function validateCommunity(json: unknown): string[] {
  const errs: string[] = [];
  if (!isMap(json)) return ["community: not an object"];
  if (!Array.isArray(json.messages)) errs.push("messages: list required");
  if (!Array.isArray(json.threads)) errs.push("threads: list required");
  (Array.isArray(json.messages) ? json.messages : []).forEach((m, i) => {
    if (!isMap(m) || !nonEmpty(m.id) || typeof m.author !== "string" || !nonEmpty(m.body)) {
      return errs.push(`messages[${i}]: id, author and body`);
    }
    for (const k of ["verifiedResident", "mine"]) {
      if (m[k] !== undefined && typeof m[k] !== "boolean") {
        errs.push(`messages[${i}].${k}: must be a boolean`);
      }
    }
  });
  (Array.isArray(json.threads) ? json.threads : []).forEach((t, i) => {
    if (!isMap(t) || !nonEmpty(t.id) || !nonEmpty(t.title)) {
      return errs.push(`threads[${i}]: id and title`);
    }
    if (t.replies !== undefined && !Number.isInteger(t.replies)) {
      errs.push(`threads[${i}].replies: must be an integer`);
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
      "residency_required",
      "content_rejected",
      "rate_limited",
    ];
    if (!isMap(e) || !codes.includes(e.code as string) || typeof e.message !== "string") {
      errs.push("envelope: error {code, message}");
    }
  } else if (!isMap(json.data)) {
    errs.push("envelope: data object required");
  }
  return errs;
}
