// GET /districts/{id}/direction: the part of the app's direction view that
// can be computed without a model.
//
// Only `trend` is served: how the incumbent's 대표발의 bills split across
// policy fields in the 21대 and in the 22대, counted from each bill's
// 소관위원회 through the fixed table in bill_fields.ts. The other two blocks of
// the view -- candidate stances and local issues -- would need a model to
// read pledge and news wording, and are not served; the app shows them as
// 준비 중. Nothing here is AI output and nothing is labelled as such.

import { latest, type SourceMeta, sourceMeta, SOURCES } from "../_shared/provenance.ts";
import { BILL_FIELDS, type BillField, fieldForCommittee } from "./bill_fields.ts";
import { CURRENT_AGE, loadDistrictAndIncumbent } from "./builders.ts";
import type { BillCommitteeRec, ReadStore } from "./store.ts";

/** The earlier term the current one is compared with. */
export const PREVIOUS_AGE = CURRENT_AGE - 1;

const termLabel = (age: number) => `${age}대`;

/** One term's bills, by field. Bills with no committee are counted apart. */
export interface TermTally {
  /** Bills that have a field. */
  counted: number;
  /** Bills with no 소관위원회 yet, left out of the shares. */
  unassigned: number;
  byField: Map<BillField, number>;
}

export function tallyTerm(rows: BillCommitteeRec[]): TermTally {
  const byField = new Map<BillField, number>();
  let unassigned = 0;
  for (const row of rows) {
    const field = fieldForCommittee(row.committee);
    if (field === null) {
      unassigned += 1;
      continue;
    }
    byField.set(field, (byField.get(field) ?? 0) + 1);
  }
  return { counted: rows.length - unassigned, unassigned, byField };
}

/** Percent to one decimal place. */
const percent = (n: number, total: number) => Math.round((n / total) * 1000) / 10;

/** The field(s) with the largest share of a term, with that share; null for an empty term. */
function largest(tally: TermTally): { labels: BillField[]; share: number } | null {
  if (tally.counted === 0) return null;
  const top = Math.max(...tally.byField.values());
  return {
    labels: BILL_FIELDS.filter((f) => tally.byField.get(f) === top),
    share: percent(top, tally.counted),
  };
}

const named = (labels: BillField[]) => `${labels.join(", ")} 분야`;
const shown = (share: number) => `${Math.round(share)}%`;

/**
 * A plain sentence built from the numbers: which field had the largest share
 * in each term. It says what the counts are, never whether a shift is good.
 */
export function trendSummary(
  from: TermTally,
  to: TermTally,
  fromTerm: string,
  toTerm: string,
): string {
  const a = largest(from);
  const b = largest(to);
  if (a && b) {
    if (a.labels.join() === b.labels.join()) {
      return `${fromTerm}와 ${toTerm} 모두 ${named(a.labels)} 법안 비중이 가장 큽니다` +
        `(${fromTerm} ${shown(a.share)}, ${toTerm} ${shown(b.share)}).`;
    }
    return `${fromTerm}에는 ${named(a.labels)} 법안 비중이 가장 컸고(${shown(a.share)}), ` +
      `${toTerm}에는 ${named(b.labels)} 비중이 가장 큽니다(${shown(b.share)}).`;
  }
  if (b) {
    return `${toTerm}에는 ${named(b.labels)} 법안 비중이 가장 큽니다(${shown(b.share)}). ` +
      `${fromTerm}에는 집계된 대표발의 법안이 없습니다.`;
  }
  if (a) {
    return `${fromTerm}에는 ${named(a.labels)} 법안 비중이 가장 컸습니다(${shown(a.share)}). ` +
      `${toTerm}에는 집계된 대표발의 법안이 없습니다.`;
  }
  return "";
}

export interface TrendJson {
  legislatorName: string;
  fromTerm: string;
  toTerm: string;
  billCount: number;
  fromCount: number;
  toCount: number;
  excludedCount: number;
  fields: { label: BillField; from: number | null; to: number | null }[];
  summary: string;
  source: SourceMeta;
}

/**
 * The trend block, or null when there is nothing to split: neither term has a
 * bill with a committee.
 *
 * A term with no counted bills has no point at all (`from`/`to` null), which
 * is not the same as a 0% share -- a member first elected in the 22대 has no
 * 21대 bills, and the chart should show no 21대 end rather than a row of zeros.
 */
export function fieldTrend(
  legislatorName: string,
  from: TermTally,
  to: TermTally,
  source: SourceMeta,
): TrendJson | null {
  if (from.counted === 0 && to.counted === 0) return null;
  const fromTerm = termLabel(PREVIOUS_AGE);
  const toTerm = termLabel(CURRENT_AGE);
  const share = (t: TermTally, f: BillField) =>
    t.counted === 0 ? null : percent(t.byField.get(f) ?? 0, t.counted);
  return {
    legislatorName,
    fromTerm,
    toTerm,
    billCount: from.counted + to.counted,
    fromCount: from.counted,
    toCount: to.counted,
    excludedCount: from.unassigned + to.unassigned,
    // Fixed table order, and only fields with a bill in either term.
    fields: BILL_FIELDS
      .filter((f) => (from.byField.get(f) ?? 0) + (to.byField.get(f) ?? 0) > 0)
      .map((f) => ({ label: f, from: share(from, f), to: share(to, f) })),
    summary: trendSummary(from, to, fromTerm, toTerm),
    source,
  };
}

export async function buildDirection(store: ReadStore, id: string) {
  const { district, member } = await loadDistrictAndIncumbent(store, id);
  const mona = member.mona_cd;

  const [fromCount, toCount, fromRows, toRows] = await Promise.all([
    store.billCount(mona, PREVIOUS_AGE),
    store.billCount(mona, CURRENT_AGE),
    store.billCommittees(mona, PREVIOUS_AGE),
    store.billCommittees(mona, CURRENT_AGE),
  ]);

  // billCount falls back to the term's latest ingest, so a null fetch time
  // means the term has not been loaded at all. Until the 21대 backfill has
  // run, "no 21대 bills" would be a claim about the member that is really a
  // gap in the data, so the block is not served.
  const loaded = fromCount.fetched_at !== null && toCount.fetched_at !== null;
  const source = sourceMeta(
    SOURCES.assemblyBills.url,
    latest(fromCount.fetched_at, toCount.fetched_at),
  );
  const trend = loaded && source
    ? fieldTrend(member.name, tallyTerm(fromRows), tallyTerm(toRows), source)
    : null;

  return {
    district: { id: district.id, displayName: district.display_name },
    trend,
    // Model output; not produced. The app shows each as 준비 중.
    stances: null,
    issues: null,
  };
}
