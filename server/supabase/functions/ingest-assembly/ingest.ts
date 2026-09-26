// 열린국회정보 ingest: members (daily), bills + plenary votes (every 6h).
// Every run writes raw pages first, then upserts normalized rows. Idempotent.

import { ASSEMBLY_SERVICES, fetchAssemblyAll } from "../_shared/assembly.ts";
import { CURRENT_DISTRICT_SG_ID } from "../_shared/district_names.ts";
import type { FetchLike, RetryOptions } from "../_shared/http.ts";
import { writeRaw } from "../_shared/ingest_common.ts";
import {
  type MemberRow,
  normalizeBill,
  normalizeMember,
  normalizePortrait,
  normalizeVote,
  PLENARY_VOTED_RESULTS,
  redactAssemblyPayload,
} from "../_shared/normalize_assembly.ts";
import { inList, type Postgrest } from "../_shared/postgrest.ts";
import { SOURCES } from "../_shared/provenance.ts";

export interface AssemblyIngestDeps {
  db: Postgrest;
  fetch: FetchLike;
  key: string;
  now?: () => Date;
  retry?: RetryOptions;
  pageSize?: number;
  /** Bills whose plenary votes are fetched per run (keeps under the function time limit). */
  voteBatch?: number;
  /** Refuse to retire members when fewer than this many came back (partial response guard). */
  minMembers?: number;
}

const AGE = "22";

function rawSink(
  deps: AssemblyIngestDeps,
  service: string,
  params: Record<string, string>,
  sourceUrl: string,
  fetchedAt: string,
) {
  return async ({ pIndex, json }: { pIndex: number; json: unknown }) => {
    await writeRaw(deps.db, {
      table: "raw_assembly",
      service,
      params,
      page: pIndex,
      payload: redactAssemblyPayload(service, json),
      sourceUrl,
      fetchedAt,
    });
  };
}

export async function ingestMembers(deps: AssemblyIngestDeps) {
  const fetchedAt = (deps.now?.() ?? new Date()).toISOString();
  const opts = { fetch: deps.fetch, key: deps.key, retry: deps.retry, pageSize: deps.pageSize };

  const memberRows = await fetchAssemblyAll(ASSEMBLY_SERVICES.members, {}, {
    ...opts,
    onPage: rawSink(deps, ASSEMBLY_SERVICES.members, {}, SOURCES.assemblyMembers.url, fetchedAt),
  });
  const members = memberRows.map((r) => normalizeMember(r, fetchedAt)).filter((m): m is MemberRow =>
    m !== null
  );
  const minMembers = deps.minMembers ?? 250;
  if (members.length < minMembers) {
    throw new Error(
      `members: only ${members.length} rows (expected >= ${minMembers}); not applied`,
    );
  }

  const portraitRows = await fetchAssemblyAll(ASSEMBLY_SERVICES.allMembers, {}, {
    ...opts,
    onPage: rawSink(
      deps,
      ASSEMBLY_SERVICES.allMembers,
      {},
      SOURCES.assemblyAllMembers.url,
      fetchedAt,
    ),
  });
  const photos = new Map<string, string>();
  for (const r of portraitRows) {
    const p = normalizePortrait(r);
    if (p) photos.set(p.mona_cd, p.photo_url);
  }

  const districts = await deps.db.select<{ id: string; name_key: string }>("districts", {
    select: "id,name_key",
    sg_id: `eq.${CURRENT_DISTRICT_SG_ID}`,
  });
  const byKey = new Map(districts.map((d) => [d.name_key, d.id]));
  const overrides = await deps.db.select<{ mona_cd: string; district_id: string }>(
    "member_district_overrides",
    { select: "mona_cd,district_id" },
  );
  const override = new Map(overrides.map((o) => [o.mona_cd, o.district_id]));

  const unmatched: string[] = [];
  const rows = members.map((m) => {
    const districtId = override.get(m.mona_cd) ??
      (m.district_key ? byKey.get(m.district_key) ?? null : null);
    if (m.district_key && !districtId) unmatched.push(m.orig_nm ?? m.mona_cd);
    return { ...m, district_id: districtId, photo_url: photos.get(m.mona_cd) ?? null };
  });
  await deps.db.upsert("members", rows, "mona_cd");

  // Retire anyone no longer in the current-member list.
  const current = new Set(rows.map((r) => r.mona_cd));
  const previous = await deps.db.select<{ mona_cd: string }>("members", {
    select: "mona_cd",
    is_current: "eq.true",
  });
  const retired = previous.map((p) => p.mona_cd).filter((m) => !current.has(m));
  if (retired.length > 0) {
    await deps.db.update("members", { mona_cd: inList(retired) }, { is_current: false });
  }

  return {
    members: rows.length,
    withPortrait: rows.filter((r) => r.photo_url).length,
    retired: retired.length,
    unmatchedDistricts: unmatched,
  };
}

export async function ingestBills(deps: AssemblyIngestDeps) {
  const fetchedAt = (deps.now?.() ?? new Date()).toISOString();
  const params = { AGE };
  const rows = await fetchAssemblyAll(ASSEMBLY_SERVICES.bills, params, {
    fetch: deps.fetch,
    key: deps.key,
    retry: deps.retry,
    pageSize: deps.pageSize,
    onPage: rawSink(deps, ASSEMBLY_SERVICES.bills, params, SOURCES.assemblyBills.url, fetchedAt),
  });
  const bills = rows.map((r) => normalizeBill(r, fetchedAt)).filter((b) => b !== null);
  await deps.db.upsert("bills", bills, "bill_id");
  return { bills: bills.length };
}

/**
 * Plenary votes for bills decided in plenary that have not been fetched yet
 * (or came back empty recently, since vote data can lag the decision).
 */
export async function ingestVotes(deps: AssemblyIngestDeps) {
  const now = deps.now?.() ?? new Date();
  const fetchedAt = now.toISOString();
  const batch = deps.voteBatch ?? 40;

  // SQL function (see migration): plenary-decided bills with no vote_fetch_log
  // row, or an empty one inside the retry window. Kept server-side because
  // the bill list is too long for a URL filter.
  const retrySince = new Date(now.getTime() - 14 * 86_400_000).toISOString().slice(0, 10);
  const todo = await deps.db.rpc<{ bill_id: string }[]>("bills_needing_votes", {
    p_age: Number(AGE),
    p_results: PLENARY_VOTED_RESULTS,
    p_retry_since: retrySince,
    p_limit: batch,
  });

  let votes = 0;
  for (const bill of todo) {
    const params = { AGE, BILL_ID: bill.bill_id };
    const rows = await fetchAssemblyAll(ASSEMBLY_SERVICES.votes, params, {
      fetch: deps.fetch,
      key: deps.key,
      retry: deps.retry,
      pageSize: deps.pageSize ?? 400,
      onPage: rawSink(deps, ASSEMBLY_SERVICES.votes, params, SOURCES.assemblyVotes.url, fetchedAt),
    });
    const normalized = rows.map((r) => normalizeVote(r, fetchedAt)).filter((v) => v !== null);
    await deps.db.upsert("bill_votes", normalized, "bill_id,mona_cd");
    await deps.db.upsert("vote_fetch_log", [{
      bill_id: bill.bill_id,
      row_count: normalized.length,
      checked_at: fetchedAt,
    }], "bill_id");
    votes += normalized.length;
  }
  return { billsChecked: todo.length, votes };
}

export async function runAssemblyIngest(mode: string, deps: AssemblyIngestDeps) {
  switch (mode) {
    case "members":
      return await ingestMembers(deps);
    case "bills":
      return await ingestBills(deps);
    case "votes":
      return await ingestVotes(deps);
    case "bills_votes":
      return { bills: await ingestBills(deps), votes: await ingestVotes(deps) };
    default:
      throw new RangeError(`unknown mode "${mode}" (members | bills | votes | bills_votes)`);
  }
}
