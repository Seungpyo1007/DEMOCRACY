// GET /districts/{id}/bills?months=N: the incumbent's 대표발의 bills proposed in the last N
// calendar months (KST), each with its own page.
//
// This is raw public text for the app's on-device AI: the app reads the titles on the reader's
// device to match them against the reader's interests and to count issue labels by month. Nothing
// here is model output, nothing is scored, and nothing comes back from the device.

import { ApiError } from "../_shared/envelope.ts";
import { isoDateOrNull } from "../_shared/dates.ts";
import { isPresentableSourceUrl, latest, sourceMeta, SOURCES } from "../_shared/provenance.ts";
import { CURRENT_AGE, loadDistrictAndSeat, memberId } from "./builders.ts";
import type { BillRec, ReadStore } from "./store.ts";

/** The months a caller may ask for, and the default. */
export const BILL_MONTHS_DEFAULT = 6;
export const BILL_MONTHS_MAX = 12;

/** The most bills one answer carries; a member leads a few a month at most. */
export const BILL_WINDOW_LIMIT = 200;

/**
 * The first KST calendar day of the window: the 1st of the month `months - 1` months before the
 * current one, so `months` = 6 on 2026-09-24 is 2026-04-01 (April through September).
 */
export function windowStart(now: Date, months: number): string {
  const kst = new Date(now.getTime() + 9 * 60 * 60 * 1000);
  const first = new Date(Date.UTC(kst.getUTCFullYear(), kst.getUTCMonth() - (months - 1), 1));
  const y = first.getUTCFullYear();
  const m = String(first.getUTCMonth() + 1).padStart(2, "0");
  return `${y}-${m}-01`;
}

/** `months` from the query: an integer 1..12, or the default when absent. */
export function parseMonths(raw: string | null): number {
  if (raw === null || raw.trim() === "") return BILL_MONTHS_DEFAULT;
  const n = Number(raw);
  if (!Number.isInteger(n) || n < 1 || n > BILL_MONTHS_MAX) {
    throw new ApiError("bad_request", `months must be an integer 1-${BILL_MONTHS_MAX}.`);
  }
  return n;
}

function billJson(b: BillRec) {
  const proposedOn = isoDateOrNull(b.propose_dt);
  // The bill's own likms page when the Assembly gave one, as the discussion threads link it;
  // otherwise the dataset it came from.
  const url = isPresentableSourceUrl(b.detail_link) ? b.detail_link : b.source_url;
  if (proposedOn === null || !isPresentableSourceUrl(url)) return null;
  return {
    id: b.bill_id,
    title: b.bill_name,
    committee: b.committee ?? null,
    proposedOn,
    sourceUrl: url,
  };
}

export async function buildMemberBills(store: ReadStore, id: string, now: Date, months: number) {
  const { district, seat } = await loadDistrictAndSeat(store, id);
  if (seat.kind !== "held") {
    throw new ApiError("not_found", "No sitting member is on record for this district.");
  }
  const member = seat.member;
  const since = windowStart(now, months);
  const [rows, count] = await Promise.all([
    store.billsSince(member.mona_cd, CURRENT_AGE, since, BILL_WINDOW_LIMIT),
    store.billCount(member.mona_cd, CURRENT_AGE),
  ]);
  // billCount falls back to the term's latest ingest, so a member with no bills in the window
  // still gets a sourced empty list rather than an unsourced one.
  const source = sourceMeta(
    SOURCES.assemblyBills.url,
    latest(count.fetched_at, ...rows.map((r) => r.fetched_at)),
  );
  if (source === null) throw new ApiError("not_found", "The term's bills have not been loaded.");
  return {
    district: { id: district.id, displayName: district.display_name },
    legislator: { id: memberId(member.mona_cd), name: member.name },
    since,
    months,
    bills: rows.map(billJson).filter((b) => b !== null),
    source,
  };
}
