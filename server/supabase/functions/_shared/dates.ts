// Date formatting in Korea Standard Time. The source data is all KST.

const KST_OFFSET_MS = 9 * 60 * 60 * 1000;

function kstParts(date: Date): { year: number; month: number; day: number } {
  const shifted = new Date(date.getTime() + KST_OFFSET_MS);
  return {
    year: shifted.getUTCFullYear(),
    month: shifted.getUTCMonth() + 1,
    day: shifted.getUTCDate(),
  };
}

/** "2026-05-12" (a KST calendar date) → "5월 12일". */
export function dayStamp(isoDate: string): string {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(isoDate);
  if (!m) return "";
  return `${Number(m[2])}월 ${Number(m[3])}일`;
}

/** "2026-05" → "5월". */
export function monthLabel(yearMonth: string): string {
  const m = /^(\d{4})-(\d{2})/.exec(yearMonth);
  return m ? `${Number(m[2])}월` : "";
}

/** KST year-month "YYYY-MM" for an instant. */
export function kstYearMonth(date: Date): string {
  const { year, month } = kstParts(date);
  return `${year}-${String(month).padStart(2, "0")}`;
}

export function kstToday(now: Date): string {
  const { year, month, day } = kstParts(now);
  return `${year}-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
}

/** "YYYYMMDD" → "YYYY-MM-DD", or null. */
export function compactToIsoDate(value: string | null | undefined): string | null {
  const m = /^(\d{4})(\d{2})(\d{2})$/.exec((value ?? "").trim());
  return m ? `${m[1]}-${m[2]}-${m[3]}` : null;
}

/** "YYYY-MM-DD" (or longer) → "YYYY-MM-DD", or null. */
export function isoDateOrNull(value: string | null | undefined): string | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec((value ?? "").trim());
  return m ? `${m[1]}-${m[2]}-${m[3]}` : null;
}

/** Assembly VOTE_DATE "20260917 155315" (KST) → ISO UTC instant, or null. */
export function assemblyVoteInstant(value: string | null | undefined): string | null {
  const m = /^(\d{4})(\d{2})(\d{2})\s*(\d{2})?(\d{2})?(\d{2})?$/.exec((value ?? "").trim());
  if (!m) return null;
  const [, y, mo, d, h = "00", mi = "00", s = "00"] = m;
  return new Date(`${y}-${mo}-${d}T${h}:${mi}:${s}+09:00`).toISOString();
}
