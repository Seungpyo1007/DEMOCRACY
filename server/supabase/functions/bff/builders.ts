// Assembles the app's DistrictProfile / HistoryRecord / PledgeBoard JSON from
// stored rows. Rule: anything without usable provenance is dropped here.
// Neutrality: descriptive figures only — no ranks, scores or labels.

import { ApiError } from "../_shared/envelope.ts";
import { dayStamp, kstToday, monthLabel } from "../_shared/dates.ts";
import { billStage } from "../_shared/normalize_assembly.ts";
import {
  isPresentableSourceUrl,
  latest,
  type SourcedNumber,
  sourcedNumber,
  type SourceMeta,
  sourceMeta,
  SOURCES,
} from "../_shared/provenance.ts";
import type {
  BillRec,
  CandidateRec,
  DistrictRec,
  MemberRec,
  MonthlyRate,
  PledgeRec,
  ReadStore,
} from "./store.ts";

export const CURRENT_AGE = 22;
/** First day of the 22대 국회 term; 출석률 is computed from here. */
export const TERM_START = "2024-05-30";
const SERIES_MONTHS = 6;
const RECORD_BILLS = 20;
const CHRONICLE_BILLS = 5;

const round1 = (x: number) => Math.round(x * 10) / 10;

export const memberId = (monaCd: string) => `assembly-${monaCd}`;
export const necPersonId = (sgId: string, huboid: string) => `nec-${sgId}-${huboid}`;

export async function loadDistrictAndIncumbent(
  store: ReadStore,
  id: string,
): Promise<{ district: DistrictRec; member: MemberRec; memberSource: SourceMeta }> {
  const district = await store.district(id);
  if (!district) throw new ApiError("not_found", "Unknown district.");
  const member = await store.incumbent(id);
  const memberSource = member ? sourceMeta(member.source_url, member.fetched_at) : null;
  if (!member || !memberSource) {
    throw new ApiError("not_found", "No sourced incumbent is on record for this district.");
  }
  return { district, member, memberSource };
}

function portrait(member: MemberRec): string | undefined {
  // Link to the Assembly's own image; never a re-hosted copy.
  if (!member.photo_url || !isPresentableSourceUrl(member.photo_url)) return undefined;
  const host = new URL(member.photo_url).host;
  return host.endsWith("assembly.go.kr") ? member.photo_url : undefined;
}

function series(rates: MonthlyRate[], fallbackUrl: string) {
  const points = rates
    .filter((r) => r.denominator > 0)
    .map((r) => ({
      label: monthLabel(r.month),
      value: round1((r.numerator / r.denominator) * 100),
    }))
    .filter((p) => p.label !== "");
  const source = sourceMeta(
    rates.find((r) => isPresentableSourceUrl(r.source_url))?.source_url ?? fallbackUrl,
    latest(...rates.map((r) => r.fetched_at)),
  );
  if (points.length === 0 || source === null) return undefined;
  return { unit: "%", source, points };
}

function billItem(b: BillRec) {
  return {
    id: b.bill_id,
    title: b.bill_name,
    stage: billStage(b),
    stamp: b.propose_dt ? dayStamp(b.propose_dt) : "",
  };
}

// ------------------------------------------------------------------ pledges

const PLEDGE_STATUSES = new Set([
  "notJudged",
  "fulfilled",
  "inProgress",
  "unfulfilled",
  "reversed",
]);

/** 「판정 전」: listed from the 선거공보, no fulfilment call made. */
const NOT_JUDGED = "notJudged";

function pledgeJudgement(raw: unknown) {
  if (!raw || typeof raw !== "object") return undefined;
  const j = raw as { steps?: unknown; sourceUrl?: unknown; fetchedAt?: unknown; source?: unknown };
  const src = j.source && typeof j.source === "object"
    ? (j.source as { sourceUrl?: unknown; fetchedAt?: unknown })
    : j;
  const source = sourceMeta(src.sourceUrl, src.fetchedAt);
  if (!Array.isArray(j.steps) || source === null) return undefined;
  const steps = j.steps
    .filter((s): s is Record<string, unknown> =>
      !!s && typeof s === "object" && typeof (s as { actor?: unknown }).actor === "string" &&
      ((s as { actor: string }).actor.trim() !== "")
    )
    .map((s) => ({
      actor: s.actor as string,
      detail: typeof s.detail === "string" ? s.detail : "",
      stamp: typeof s.stamp === "string" ? s.stamp : "",
    }));
  return steps.length > 0 ? { steps, source } : undefined;
}

export function pledgeJson(p: PledgeRec) {
  const source = sourceMeta(p.source_url, p.fetched_at);
  if (!source || !p.id || !p.title || !PLEDGE_STATUSES.has(p.status)) return null;
  const evidence = isPresentableSourceUrl(p.evidence_url) ? p.evidence_url : undefined;
  if (p.status === "reversed" && !evidence) return null;
  // A pledge nobody has judged carries no part of a verdict, even if a row
  // somehow holds one (the migration forbids it; this is the second lock).
  if (p.status === NOT_JUDGED) {
    return { id: p.id, title: p.title, category: p.category ?? "", status: p.status, source };
  }
  const judgement = pledgeJudgement(p.judgement);
  return {
    id: p.id,
    title: p.title,
    category: p.category ?? "",
    status: p.status,
    source,
    ...(evidence ? { evidenceUrl: evidence } : {}),
    ...(judgement ? { judgement } : {}),
  };
}

async function curatedPledges(store: ReadStore, districtId: string) {
  const found = await store.pledgeBoard(districtId);
  if (!found) return null;
  const source = sourceMeta(found.board.source_url, found.board.fetched_at);
  const pledges = found.pledges.map(pledgeJson).filter((p) => p !== null);
  if (!source || pledges.length === 0) return null;
  return { source, pledges };
}

export async function buildPledges(store: ReadStore, id: string) {
  const district = await store.district(id);
  if (!district) throw new ApiError("not_found", "Unknown district.");
  const board = await curatedPledges(store, id);
  if (!board) throw new ApiError("not_curated", "Pledges for this district are not curated yet.");
  return board;
}

// ------------------------------------------------------------------ profile

function candidateJson(c: CandidateRec) {
  if (!sourceMeta(c.source_url, c.fetched_at)) return null;
  const summary = c.kind === "preliminary"
    ? (c.career1 ? `예비후보 · ${c.career1}` : "예비후보")
    : (c.career1 ?? "");
  return {
    id: necPersonId(c.sg_id, c.huboid),
    name: c.name,
    party: c.party ?? "무소속",
    summary,
    stats: [] as unknown[],
  };
}

/** Registered candidates of the upcoming election; finals win over preliminaries. */
function pickCandidates(rows: CandidateRec[]) {
  const standing = rows.filter((c) => c.status === null || c.status === "등록");
  const finals = standing.filter((c) => c.kind === "final");
  const chosen = finals.length > 0 ? finals : standing;
  return chosen
    .map(candidateJson)
    .filter((c) => c !== null)
    .sort((a, b) => a.name.localeCompare(b.name, "ko"));
}

export async function buildProfile(store: ReadStore, id: string, now: Date) {
  const { district, member, memberSource } = await loadDistrictAndIncumbent(store, id);
  const mona = member.mona_cd;

  const [attendanceTotal, billCount, bills, attendance, votes, pledges, candidates] = await Promise
    .all([
      store.attendanceSince(mona, TERM_START),
      store.billCount(mona, CURRENT_AGE),
      store.recentBills(mona, CURRENT_AGE, RECORD_BILLS),
      store.monthlyAttendance(mona, SERIES_MONTHS),
      store.monthlyVoteParticipation(mona, SERIES_MONTHS),
      curatedPledges(store, id),
      store.upcomingCandidates(district, kstToday(now)),
    ]);

  const stats: { label: string; unit: string; value: SourcedNumber }[] = [];
  if (attendanceTotal && attendanceTotal.denominator > 0) {
    const v = sourcedNumber(
      round1((attendanceTotal.numerator / attendanceTotal.denominator) * 100),
      attendanceTotal.source_url,
      attendanceTotal.fetched_at,
    );
    if (v) stats.push({ label: "출석률", unit: "%", value: v });
  }
  const billsSource = sourceMeta(SOURCES.assemblyBills.url, billCount.fetched_at);
  if (billsSource) {
    stats.push({
      label: "발의 법안",
      unit: "건",
      value: { value: billCount.count, ...billsSource },
    });
  }
  // 공약 이행 = fulfilled ÷ judged. A 「판정 전」 pledge is neither kept nor
  // broken, so it is left out of both sides; a board with nothing judged has
  // no rate at all rather than a 0 % that would read as a verdict.
  const judged = pledges?.pledges.filter((p) => p.status !== NOT_JUDGED) ?? [];
  if (pledges && judged.length > 0) {
    const fulfilled = judged.filter((p) => p.status === "fulfilled").length;
    stats.push({
      label: "공약 이행",
      unit: "%",
      value: { value: Math.round((fulfilled / judged.length) * 100), ...pledges.source },
    });
  }

  let record: Record<string, unknown> | undefined;
  if (billsSource) {
    record = { bills: { source: billsSource, items: bills.map(billItem) } };
    const att = series(attendance, "");
    if (att) record.attendance = att;
    const vt = series(votes, SOURCES.assemblyVotes.url);
    if (vt) record.votes = vt;
  }

  const photo = portrait(member);
  return {
    district: { id: district.id, displayName: district.display_name },
    source: memberSource,
    incumbent: {
      id: memberId(mona),
      name: member.name,
      party: member.party ?? "무소속",
      summary: member.reele_gbn ?? "",
      ...(photo ? { portraitUrl: photo } : {}),
      stats,
      ...(record ? { record } : {}),
    },
    candidates: pickCandidates(candidates),
  };
}

// ------------------------------------------------------------------ history

export async function buildHistory(store: ReadStore, id: string) {
  const { district, member, memberSource } = await loadDistrictAndIncumbent(store, id);
  const incumbentId = memberId(member.mona_cd);
  const districtSource = sourceMeta(district.source_url, district.fetched_at);

  const [elections, results, region, bills, billCount] = await Promise.all([
    store.generalElections(),
    store.resultsFor(district),
    store.regionTimeline(id),
    store.recentBills(member.mona_cd, CURRENT_AGE, CHRONICLE_BILLS),
    store.billCount(member.mona_cd, CURRENT_AGE),
  ]);

  // Elections: one row per general election with a sourced winner here, plus
  // an `ongoing` marker only while that election is being counted.
  const rows: Record<string, unknown>[] = [];
  const wins: { year: number; term: number; party: string; share: number }[] = [];
  const usedResults: string[] = [];
  const ordered = [...elections].sort((a, b) =>
    (a.vote_date ?? "").localeCompare(b.vote_date ?? "")
  );
  for (const e of ordered) {
    const year = Number((e.vote_date ?? e.sg_id).slice(0, 4));
    if (e.term === null || !Number.isInteger(year)) continue;
    if (e.count_status === "counting") {
      rows.push({ term: e.term, year, ongoing: true });
      continue;
    }
    const winners = results.filter((r) =>
      r.sg_id === e.sg_id && r.is_winner && typeof r.share === "number" &&
      sourceMeta(r.source_url, r.fetched_at) !== null
    );
    if (winners.length !== 1) continue; // none, or ambiguous: leave it out rather than guess
    const w = winners[0];
    const isIncumbent = w.name === member.name;
    const party = w.party ?? "무소속";
    rows.push({
      term: e.term,
      year,
      winner: {
        id: isIncumbent ? incumbentId : necPersonId(w.sg_id, w.huboid),
        name: w.name,
        party,
      },
      share: w.share,
    });
    usedResults.push(w.fetched_at ?? "");
    if (isIncumbent) wins.push({ year, term: e.term, party, share: w.share as number });
  }
  const electionsSource = usedResults.length > 0
    ? sourceMeta(SOURCES.necWinners.url, latest(...usedResults))
    : districtSource;
  if (!electionsSource) throw new ApiError("internal", "District has no source.");

  // Region: curated timeline, or an empty one attributed to the district record.
  let regionBlock: { source: SourceMeta; events: unknown[] };
  const regionSource = region
    ? sourceMeta(region.timeline.source_url, region.timeline.fetched_at)
    : null;
  if (region && regionSource) {
    regionBlock = {
      source: regionSource,
      events: region.events
        .filter((e) => typeof e.title === "string" && e.title.trim() !== "")
        .filter((e) => e.year === null || Number.isInteger(e.year))
        .map((e) => ({ year: e.year, title: e.title, ...(e.detail ? { detail: e.detail } : {}) })),
    };
  } else {
    regionBlock = { source: districtSource ?? electionsSource, events: [] };
  }

  const billsSource = sourceMeta(SOURCES.assemblyBills.url, billCount.fetched_at);
  const events = [
    ...wins.map((w) => ({
      mark: String(w.year),
      title: `제${w.term}대 국회의원 당선`,
      detail: `${w.party} · 득표율 ${w.share}%`,
    })),
    ...[...bills].reverse().map((b) => {
      const stamp = b.propose_dt ? dayStamp(b.propose_dt) : "";
      const mark = b.propose_dt ? monthLabel(b.propose_dt) : "";
      return {
        mark,
        title: b.bill_name,
        detail: [stamp, billStage(b)].filter(Boolean).join(" · "),
      };
    }).filter((e) => e.mark !== ""),
  ];

  const photo = portrait(member);
  return {
    district: { id: district.id, displayName: district.display_name },
    region: regionBlock,
    elections: { source: electionsSource, basis: "득표율은 당선자 기준", rows },
    legislator: {
      source: billsSource ?? memberSource,
      incumbent: {
        id: incumbentId,
        name: member.name,
        party: member.party ?? "무소속",
        summary: member.reele_gbn ?? "",
        ...(photo ? { portraitUrl: photo } : {}),
      },
      events,
    },
  };
}
