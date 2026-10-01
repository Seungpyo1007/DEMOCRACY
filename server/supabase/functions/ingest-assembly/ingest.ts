// 열린국회정보 ingest: members (daily), bills + plenary votes (every 6h), member portraits
// copied into Storage (daily, `mode=portraits`), and a by-hand backfill of an earlier
// term's bills (`mode=bills_backfill`).
// Every run writes raw pages first, then upserts normalized rows. Idempotent.

import { ASSEMBLY_SERVICES, fetchAssemblyAll, fetchAssemblyPages } from "../_shared/assembly.ts";
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
import { isPresentableSourceUrl, SOURCES } from "../_shared/provenance.ts";

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
  /** Where portrait copies go: the 'portraits' Storage bucket. Needed by mode=portraits. */
  storage?: PortraitStorage;
  /** Portraits copied per run (keeps under the function time limit). */
  portraitBatch?: number;
}

export interface PortraitStorage {
  upload(path: string, bytes: Uint8Array, contentType: string): Promise<void>;
}

/** Larger than any official portrait; the bucket refuses more anyway. */
const PORTRAIT_MAX_BYTES = 2 * 1024 * 1024;

const PORTRAIT_TYPES: Record<string, string> = { "image/jpeg": "jpg", "image/png": "png" };

async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", bytes as BufferSource);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/**
 * Copies current members' portraits into Storage: those not copied yet, or whose Assembly
 * URL changed (a new photo). The path carries the content hash, so a new photo never
 * overwrites a file an app may have cached. A copy starts 'unconfirmed' and keeps
 * whatever licence was recorded for the member before (see the portraits migration).
 */
export async function ingestPortraits(deps: AssemblyIngestDeps) {
  if (!deps.storage) throw new Error("portraits: no storage configured");
  const fetchedAt = (deps.now?.() ?? new Date()).toISOString();
  const members = await deps.db.select<{ mona_cd: string; photo_url: string | null }>(
    "members",
    { select: "mona_cd,photo_url", is_current: "eq.true", photo_url: "not.is.null" },
  );
  const copied = await deps.db.select<{ mona_cd: string; source_url: string }>("portraits", {
    select: "mona_cd,source_url",
  });
  const have = new Map(copied.map((c) => [c.mona_cd, c.source_url]));
  const todo = members.filter((m) =>
    m.photo_url && isPresentableSourceUrl(m.photo_url) && have.get(m.mona_cd) !== m.photo_url
  );
  const batch = todo.slice(0, deps.portraitBatch ?? 60);

  let failed = 0;
  const rows: object[] = [];
  for (const m of batch) {
    try {
      const res = await deps.fetch(m.photo_url!);
      const type = (res.headers.get("content-type") ?? "").split(";")[0].trim().toLowerCase();
      const ext = PORTRAIT_TYPES[type];
      if (!res.ok || !ext) throw new Error(`status ${res.status}, type ${type || "none"}`);
      const bytes = new Uint8Array(await res.arrayBuffer());
      if (bytes.length === 0 || bytes.length > PORTRAIT_MAX_BYTES) {
        throw new Error(`size ${bytes.length}`);
      }
      const sha = await sha256Hex(bytes);
      const path = `members/${m.mona_cd}-${sha.slice(0, 16)}.${ext}`;
      await deps.storage.upload(path, bytes, type);
      rows.push({
        mona_cd: m.mona_cd,
        storage_path: path,
        source_url: m.photo_url,
        content_type: type,
        bytes: bytes.length,
        sha256: sha,
        fetched_at: fetchedAt,
      });
    } catch {
      // One bad image does not stop the rest; it is tried again tomorrow.
      failed += 1;
    }
  }
  if (rows.length > 0) await deps.db.upsert("portraits", rows, "mona_cd");
  return {
    candidates: todo.length,
    copied: rows.length,
    failed,
    remaining: todo.length - batch.length,
  };
}

const AGE = "22";

/** The earliest term a backfill may ask for. */
const OLDEST_BACKFILL_AGE = 17;
/** Pages per backfill call: 10 x 1000 rows keeps one call well under the time limit. */
const BACKFILL_PAGES = 10;

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

export interface BillsBackfillOptions {
  /** 대수, e.g. 21. Must be an earlier term than the current one. */
  age: number;
  /** First page to fetch (1-based): the previous call's `nextPage`. */
  page?: number;
  /** Pages to fetch in this call. */
  pages?: number;
}

/**
 * Backfills an earlier term's bills for members who sit now.
 *
 * The direction view compares an incumbent's 대표발의 bills across terms, so it
 * needs the 21대 rows the 6-hourly job never fetched (that job stays on the
 * current term and is unchanged). A whole term is ~25 pages of 1000, too many
 * for one function call, so this fetches a window of pages and reports
 * `nextPage` until `done`.
 *
 * Only bills led by a current member are kept: a former member has no
 * district page to show them on. MONA_CD identifies the person across terms,
 * so a re-elected member's 21대 bills carry the same RST_MONA_CD as their 22대
 * ones; a member first elected in 22대 simply has no 21대 rows.
 */
export async function ingestBillsBackfill(deps: AssemblyIngestDeps, opts: BillsBackfillOptions) {
  const current = Number(AGE);
  if (!Number.isInteger(opts.age) || opts.age < OLDEST_BACKFILL_AGE || opts.age >= current) {
    throw new RangeError(
      `age must be an earlier term (${OLDEST_BACKFILL_AGE}-${current - 1}); ` +
        `the current term is loaded by mode=bills`,
    );
  }
  const firstPage = opts.page ?? 1;
  const maxPages = opts.pages ?? BACKFILL_PAGES;
  if (
    !Number.isInteger(firstPage) || firstPage < 1 || !Number.isInteger(maxPages) || maxPages < 1
  ) {
    throw new RangeError("page and pages must be positive integers");
  }

  const sitting = await deps.db.select<{ mona_cd: string }>("members", {
    select: "mona_cd",
    is_current: "eq.true",
  });
  if (sitting.length === 0) {
    throw new Error("no current members on record; run mode=members first");
  }
  const keep = new Set(sitting.map((m) => m.mona_cd));

  const fetchedAt = (deps.now?.() ?? new Date()).toISOString();
  const params = { AGE: String(opts.age) };
  const run = await fetchAssemblyPages(ASSEMBLY_SERVICES.bills, params, {
    fetch: deps.fetch,
    key: deps.key,
    retry: deps.retry,
    pageSize: deps.pageSize,
    firstPage,
    maxPages,
    onPage: rawSink(deps, ASSEMBLY_SERVICES.bills, params, SOURCES.assemblyBills.url, fetchedAt),
  });
  const bills = run.rows
    .map((r) => normalizeBill(r, fetchedAt))
    .filter((b) => b !== null)
    .filter((b) => b.age === opts.age && b.rst_mona_cd !== null && keep.has(b.rst_mona_cd));
  await deps.db.upsert("bills", bills, "bill_id");
  return {
    age: opts.age,
    pages: [firstPage, run.lastPage],
    fetched: run.rows.length,
    kept: bills.length,
    total: run.total,
    done: run.done,
    nextPage: run.done ? null : run.lastPage + 1,
  };
}

/** An integer query parameter: absent is undefined, anything else not a number is refused. */
function intParam(params: URLSearchParams | undefined, name: string): number | undefined {
  const raw = params?.get(name);
  if (raw === null || raw === undefined || raw === "") return undefined;
  if (!/^\d+$/.test(raw)) throw new RangeError(`${name} must be an integer`);
  return Number(raw);
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

export async function runAssemblyIngest(
  mode: string,
  deps: AssemblyIngestDeps,
  params?: URLSearchParams,
) {
  switch (mode) {
    case "members":
      return await ingestMembers(deps);
    case "bills":
      return await ingestBills(deps);
    case "votes":
      return await ingestVotes(deps);
    case "bills_votes":
      return { bills: await ingestBills(deps), votes: await ingestVotes(deps) };
    case "portraits":
      return await ingestPortraits(deps);
    case "bills_backfill": {
      const age = intParam(params, "age");
      if (age === undefined) throw new RangeError("bills_backfill needs age, e.g. age=21");
      return await ingestBillsBackfill(deps, {
        age,
        page: intParam(params, "page"),
        pages: intParam(params, "pages"),
      });
    }
    default:
      throw new RangeError(
        `unknown mode "${mode}" (members | bills | votes | bills_votes | portraits | bills_backfill)`,
      );
  }
}
