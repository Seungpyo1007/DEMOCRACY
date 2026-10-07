-- Party colours (#95) and 여당/야당 (#96).
--
-- Principles
--  * Until now the product showed a party by name only, with no colour, for neutrality.
--    The operator reversed that on 2026-10-07: a party is shown with its own official
--    colour. The name is still always shown as text beside it, so colour never carries
--    the meaning alone.
--  * A colour is a fact about the party, so it is sourced like every other figure: the
--    party's own CI page or announcement, recorded per row with the date it was checked.
--    A party whose colour could not be confirmed keeps a null colour and the app draws it
--    neutral. Nothing is guessed from a logo.
--  * 여당 is not hard-coded. ruling_periods says which party held the presidency over which
--    dates, and the BFF reads a record against its own date: today for a sitting member,
--    the election day for a result or a candidate.
--  * A period with a null party_name is an acting presidency (대통령 궐위, 권한대행): no
--    president, so no party is 여당 and nobody is marked 여 or 야. A suspended president
--    (탄핵소추 의결 후 직무정지) is still president, so that stretch stays with the party.
--  * Periods are half-open: starts_on inclusive, ends_on exclusive (the day the next
--    period starts), so a date belongs to exactly one period.
--  * Both tables are curated: data/parties.json → scripts/import_curated.ts --kind parties.
--  * Same access model as the other tables: RLS on, no policies, no grants. The BFF reads
--    with the service role.

create table public.parties (
  -- Exactly as NEC and the Assembly spell it; the key every party string is matched on.
  name text primary key,
  -- '#RRGGBB', upper case. Null: no authoritative colour was found.
  color text check (color ~ '^#[0-9A-F]{6}$'),
  color_source_url text
    check (color_source_url is null or public.is_presentable_source_url(color_source_url)),
  color_checked_at date,
  -- Other spellings of the same party seen in the data (e.g. a shortened name).
  aliases text[] not null default '{}',
  -- The name this party was renamed from, when it was a rename (자유한국당 ← 새누리당).
  predecessor text,
  note text,
  check (color is null or (color_source_url is not null and color_checked_at is not null))
);

create table public.ruling_periods (
  starts_on date primary key,
  -- Exclusive. Null: still running.
  ends_on date check (ends_on is null or ends_on > starts_on),
  -- The president's party over the period; null for an acting presidency.
  party_name text references public.parties (name) on update cascade,
  president text not null,
  note text,
  source_url text not null check (public.is_presentable_source_url(source_url)),
  -- No date may fall in two periods.
  exclude using gist ((daterange(starts_on, ends_on, '[)')) with &&)
);

alter table public.parties enable row level security;
revoke all on public.parties from anon, authenticated;
alter table public.ruling_periods enable row level security;
revoke all on public.ruling_periods from anon, authenticated;

comment on table public.parties is
  'Party colours with their source. Name is shown as text beside any colour, always.';
comment on table public.ruling_periods is
  '여당 by date. Half-open [starts_on, ends_on). party_name null = acting presidency.';
