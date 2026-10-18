// A party as the app is sent it: its name, its own colour when one is on record with a
// source, and whether it held the presidency on the date the record is about.
//
// The name stays the plain `party` string every payload already carries; this goes next to
// it as `partyInfo`, so an app that does not know the field reads the payload as before.

export type PartySide = "ruling" | "opposition";

export interface PartyInfo {
  name: string;
  /** "#RRGGBB", or null when no sourced colour is on record. */
  color: string | null;
  /** Relative to the record's date; null when it cannot be said. */
  side: PartySide | null;
}

/** The parties table as the store reads it (see the parties migration). */
export interface PartyRec {
  name: string;
  color: string | null;
  color_source_url: string | null;
  color_checked_at: string | null;
  aliases?: string[] | null;
}

/** ruling_periods: [starts_on, ends_on), party_name null for an acting presidency. */
export interface RulingPeriodRec {
  starts_on: string;
  ends_on: string | null;
  party_name: string | null;
}

/** Not a party: no colour, never 여 or 야. */
export const INDEPENDENT = "무소속";

const HEX = /^#[0-9A-F]{6}$/;
const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

export class PartyBook {
  private readonly byName = new Map<string, PartyRec>();

  constructor(
    parties: PartyRec[],
    private readonly periods: RulingPeriodRec[],
  ) {
    for (const p of parties) {
      this.byName.set(p.name, p);
      for (const a of p.aliases ?? []) if (!this.byName.has(a)) this.byName.set(a, p);
    }
  }

  static readonly empty = new PartyBook([], []);

  /** The period a KST date falls in, or null when none covers it. */
  periodOn(isoDate: string): RulingPeriodRec | null {
    if (!ISO_DATE.test(isoDate)) return null;
    return this.periods.find((p) =>
      p.starts_on <= isoDate && (p.ends_on === null || isoDate < p.ends_on)
    ) ?? null;
  }

  /**
   * `name` as of `isoDate`. Side is said only for a party on record, on a date a period
   * covers, and outside an acting presidency; a colour only when it carries a source.
   */
  info(name: string | null | undefined, isoDate: string | null): PartyInfo {
    const shown = name && name.trim() !== "" ? name : INDEPENDENT;
    const rec = shown === INDEPENDENT ? undefined : this.byName.get(shown);
    if (!rec) return { name: shown, color: null, side: null };
    const color = rec.color && HEX.test(rec.color) && rec.color_source_url && rec.color_checked_at
      ? rec.color
      : null;
    const period = isoDate ? this.periodOn(isoDate) : null;
    let side: PartySide | null = null;
    if (period && period.party_name !== null) {
      const ruling = this.byName.get(period.party_name);
      // The foreign key keeps the ruling party on record; if it is not, say nothing.
      if (ruling) side = ruling.name === rec.name ? "ruling" : "opposition";
    }
    return { name: shown, color, side };
  }
}

/** "20240410" → "2024-04-10"; anything else → null. */
export function sgIdDate(sgId: string): string | null {
  const m = /^(\d{4})(\d{2})(\d{2})$/.exec(sgId);
  return m ? `${m[1]}-${m[2]}-${m[3]}` : null;
}

/**
 * The book for one response. Colour and side are decoration on a name the payload already
 * carries, so a failed read (the tables not migrated yet, say) gives an empty book and the
 * response goes out with names only, as before, instead of failing.
 */
export async function loadPartyBook(
  store: { partyBook(): Promise<{ parties: PartyRec[]; periods: RulingPeriodRec[] }> },
): Promise<PartyBook> {
  try {
    const { parties, periods } = await store.partyBook();
    return new PartyBook(parties, periods);
  } catch {
    return PartyBook.empty;
  }
}
