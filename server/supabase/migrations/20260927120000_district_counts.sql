-- Final 개표 per 선거구 for past general elections (ingest-nec ?mode=counts).
--
-- Principles (same as init)
--  * One row per 선거구 per election: NEC's "합계" row. The per-구시군 rows are left in
--    raw_nec only.
--  * Keyed by (sg_id, sg_typecode, name_key), the key winners are joined by. Only the 22대
--    (20240410) rows carry a district_id: the districts table is the 22대 선거구, and an
--    older 선거구 may not match any of them. Nothing here guesses that it does.
--  * Only finished counts. The ingest refuses an election whose day has not passed, so a
--    count in progress is never stored as final; counted_share is 100 on every row it
--    writes. A live count, when it comes, is a different pipeline with its own gate
--    (docs/ELECTION_LAW.md, 제167조제2항).
--  * Candidates are name, party and votes: the published result, nothing personal.
--  * RLS on with no policies; anon/authenticated have no grants. Only the service role reads.

create table public.district_counts (
  sg_id text not null,
  sg_typecode int not null,
  name_key text not null,              -- "서울마포구을", districtNameKey(sdName, sggName)
  sd_name text not null,
  sgg_name text not null,
  district_id text references public.districts (id) on delete set null,
  electorate int check (electorate >= 0),              -- sunsu, 선거인수
  turnout int check (turnout >= 0),                    -- tusu, 투표수 (a count, not a rate)
  valid_votes int not null check (valid_votes > 0),    -- yutusu, 유효투표수
  invalid_votes int check (invalid_votes >= 0),        -- mutusu, 무효투표수
  abstentions int check (abstentions >= 0),            -- gigwonsu, 기권수
  -- [{name, party, votes}], in NEC's 기호 order. party null = 무소속 or not given.
  candidates jsonb not null check (
    jsonb_typeof(candidates) = 'array' and jsonb_array_length(candidates) > 0
  ),
  counted_share numeric not null check (counted_share between 0 and 100),
  source_url text not null check (public.is_presentable_source_url(source_url)),
  publisher text not null,
  fetched_at timestamptz not null,
  primary key (sg_id, sg_typecode, name_key)
);
-- The FK, and the historical lookup of one 선거구 across elections.
create index on public.district_counts (district_id);
create index on public.district_counts (name_key);

alter table public.district_counts enable row level security;
revoke all on public.district_counts from anon, authenticated;

-- A one-off per election, like the winners backfill (no cron):
--   select public.call_ingest('ingest-nec', 'mode=counts&sgIds=20240410');
