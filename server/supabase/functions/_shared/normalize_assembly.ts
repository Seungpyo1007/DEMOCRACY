// Field mapping for 열린국회정보 rows. The only file that knows Assembly field
// names. Field names verified against live keyless responses on 2026-09-24.

import { assemblyOrigKey } from "./district_names.ts";
import { assemblyVoteInstant, isoDateOrNull } from "./dates.ts";
import type { AssemblyRow } from "./assembly.ts";
import { SOURCES } from "./provenance.ts";

const str = (v: unknown): string | null => {
  if (typeof v === "number") return String(v);
  if (typeof v !== "string") return null;
  const t = v.trim();
  return t === "" ? null : t;
};

export interface MemberRow {
  mona_cd: string;
  name: string;
  party: string | null;
  orig_nm: string | null;
  district_key: string | null;
  elect_gbn: string | null;
  reele_gbn: string | null;
  units: string | null;
  committees: string | null;
  is_current: boolean;
  source_url: string;
  publisher: string;
  fetched_at: string;
}

/** nwvrqwxyaytdsfvhu (current members). */
export function normalizeMember(row: AssemblyRow, fetchedAt: string): MemberRow | null {
  const mona = str(row.MONA_CD);
  const name = str(row.HG_NM);
  if (!mona || !name) return null;
  const orig = str(row.ORIG_NM);
  return {
    mona_cd: mona,
    name,
    party: str(row.POLY_NM),
    orig_nm: orig,
    district_key: assemblyOrigKey(orig),
    elect_gbn: str(row.ELECT_GBN_NM),
    reele_gbn: str(row.REELE_GBN_NM),
    units: str(row.UNITS),
    committees: str(row.CMITS) ?? str(row.CMIT_NM),
    is_current: true,
    source_url: SOURCES.assemblyMembers.url,
    publisher: SOURCES.assemblyMembers.publisher,
    fetched_at: fetchedAt,
  };
}

/**
 * ALLNAMEMBER → portrait URL on assembly.go.kr. We store the URL only and never
 * re-host the image (license unclear; inquiry pending with 국회사무처).
 */
export function normalizePortrait(row: AssemblyRow): { mona_cd: string; photo_url: string } | null {
  const mona = str(row.NAAS_CD);
  const pic = str(row.NAAS_PIC);
  if (!mona || !pic) return null;
  try {
    const u = new URL(pic);
    if (u.protocol !== "https:" || !u.host.endsWith("assembly.go.kr")) return null;
  } catch {
    return null;
  }
  return { mona_cd: mona, photo_url: pic };
}

export interface BillRow {
  bill_id: string;
  bill_no: string | null;
  age: number;
  bill_name: string;
  proposer: string | null;
  rst_mona_cd: string | null;
  propose_dt: string | null;
  committee: string | null;
  committee_dt: string | null;
  cmt_proc_dt: string | null;
  proc_result: string | null;
  proc_dt: string | null;
  detail_link: string | null;
  source_url: string;
  publisher: string;
  fetched_at: string;
}

/** nzmimeepazxkubdpn. RST_MONA_CD is the lead sponsor (대표발의자). */
export function normalizeBill(row: AssemblyRow, fetchedAt: string): BillRow | null {
  const id = str(row.BILL_ID);
  const name = str(row.BILL_NAME);
  const age = Number(str(row.AGE));
  if (!id || !name || !Number.isInteger(age)) return null;
  return {
    bill_id: id,
    bill_no: str(row.BILL_NO),
    age,
    bill_name: name,
    proposer: str(row.PROPOSER),
    rst_mona_cd: str(row.RST_MONA_CD),
    propose_dt: isoDateOrNull(str(row.PROPOSE_DT)),
    committee: str(row.COMMITTEE),
    committee_dt: isoDateOrNull(str(row.COMMITTEE_DT)),
    cmt_proc_dt: isoDateOrNull(str(row.CMT_PROC_DT)),
    proc_result: str(row.PROC_RESULT),
    proc_dt: isoDateOrNull(str(row.PROC_DT)),
    detail_link: str(row.DETAIL_LINK),
    source_url: SOURCES.assemblyBills.url,
    publisher: SOURCES.assemblyBills.publisher,
    fetched_at: fetchedAt,
  };
}

/**
 * The stage shown next to a bill: the Assembly's own wording for a decided
 * bill, otherwise the furthest step the record shows. Descriptive only.
 */
export function billStage(
  bill: Pick<BillRow, "proc_result" | "cmt_proc_dt" | "committee_dt">,
): string {
  if (bill.proc_result) return bill.proc_result;
  if (bill.cmt_proc_dt) return "위원회 의결";
  if (bill.committee_dt) return "위원회 심사";
  return "접수";
}

/** Plenary outcomes that imply a recorded vote. */
export const PLENARY_VOTED_RESULTS = ["원안가결", "수정가결", "부결"];

export type VoteResult = "찬성" | "반대" | "기권" | "불참";
const VOTE_RESULTS = new Set<string>(["찬성", "반대", "기권", "불참"]);

export interface BillVoteRow {
  bill_id: string;
  mona_cd: string;
  result: VoteResult;
  vote_at: string;
  age: number;
  source_url: string;
  publisher: string;
  fetched_at: string;
}

/** nojepdqqaweusdfbi (per member, per bill). */
export function normalizeVote(row: AssemblyRow, fetchedAt: string): BillVoteRow | null {
  const bill = str(row.BILL_ID);
  const mona = str(row.MONA_CD);
  const result = str(row.RESULT_VOTE_MOD);
  const at = assemblyVoteInstant(str(row.VOTE_DATE));
  const age = Number(str(row.AGE));
  if (!bill || !mona || !result || !VOTE_RESULTS.has(result) || !at) return null;
  return {
    bill_id: bill,
    mona_cd: mona,
    result: result as VoteResult,
    vote_at: at,
    age: Number.isInteger(age) ? age : 22,
    source_url: SOURCES.assemblyVotes.url,
    publisher: SOURCES.assemblyVotes.publisher,
    fetched_at: fetchedAt,
  };
}

/**
 * Raw payload minimisation: staff names (private individuals) and birth dates
 * are removed before a members page is written to raw_assembly.
 */
const MEMBER_FIELDS_DROPPED = [
  "BTH_DATE",
  "BTH_GBN_NM",
  "BIRDY_DT",
  "BIRDY_DIV_CD",
  "STAFF",
  "SECRETARY",
  "SECRETARY2",
  "AIDE_NM",
  "CHF_SCRT_NM",
  "SCRT_NM",
];

export function redactAssemblyPayload(service: string, json: unknown): unknown {
  if (json === null || typeof json !== "object") return json;
  const parts = (json as Record<string, unknown>)[service];
  if (!Array.isArray(parts)) return json;
  return {
    [service]: parts.map((part) => {
      if (!part || typeof part !== "object" || !("row" in part)) return part;
      const rows = (part as { row: AssemblyRow[] }).row;
      return {
        row: rows.map((r) => {
          const copy = { ...r };
          for (const f of MEMBER_FIELDS_DROPPED) delete copy[f];
          return copy;
        }),
      };
    }),
  };
}
