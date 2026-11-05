-- 시·도지사 and 구청장·시장·군수 from KoreaPoliticsAPI (#98).
--
-- KPA ships the offices (offices.json, type metro-head / local-head) and who holds them
-- (terms.json, an open term). Both are KPA's facts, so kpa_apply replaces the two tables
-- whole in the same transaction as the rest of a release.
--
-- local_offices.code is the 행정구역 code KPA uses as the office id: two digits for a
-- 시·도, five (법정동 code prefix) for a 시·군·구. An address's admCd starts with the
-- same five digits, which is how the BFF finds the offices for an address. A 일반구
-- (수원시 장안구, 41111) has no office of its own; its city (41110) is the one.
--
-- local_heads has a row only while someone holds the office. No row means vacant or
-- not known yet, and the app says so instead of guessing.

create table public.local_offices (
  id text primary key,
  level text not null check (level in ('metro', 'local')),
  code text not null unique check (code ~ '^[0-9]{2}([0-9]{3})?$'),
  sido text not null,
  name text not null,
  source_url text not null,
  checked_at date not null,
  check ((level = 'metro') = (length(code) = 2))
);

create table public.local_heads (
  office_id text primary key references public.local_offices (id),
  kpa_person_id text not null,
  name text not null,
  party text,
  starts_on date not null,
  how text not null,
  election_id text,
  source_url text not null,
  checked_at date not null
);

alter table public.local_offices enable row level security;
alter table public.local_heads enable row level security;
revoke all on public.local_offices from anon, authenticated;
revoke all on public.local_heads from anon, authenticated;

-- A new argument list is a new function, so the old one goes.
drop function public.kpa_apply(text, int, jsonb, jsonb, jsonb, jsonb, jsonb);

create or replace function public.kpa_apply(
  p_tag text, p_schema_version int, p_files jsonb,
  p_parties jsonb, p_ruling_periods jsonb, p_boards jsonb, p_photos jsonb,
  p_local_offices jsonb, p_local_heads jsonb
) returns jsonb
language plpgsql set search_path = '' as $$
declare
  unknown text[];
  n_parties int;
  n_periods int;
  n_boards int;
  n_pledges int;
  n_new int;
  n_removed int;
  judged_kept text[];
  n_photos int;
  photos_unmatched text[];
  n_offices int;
  n_heads int;
  summary jsonb;
begin
  select array_agg(b->>'district_id' order by b->>'district_id') into unknown
  from jsonb_array_elements(p_boards) b
  where not exists (select 1 from public.districts d where d.id = b->>'district_id');
  if unknown is not null then
    raise exception 'kpa_unknown_district: %', array_to_string(unknown, ', ');
  end if;

  -- ---------------------------------------------------------------- parties
  -- A kpa_id that moved to another name would break the unique key on the upsert.
  update public.parties p set kpa_id = null
  from jsonb_array_elements(p_parties) e
  where p.kpa_id = e->>'kpa_id' and p.name <> e->>'name';

  insert into public.parties
    (name, kpa_id, color, color_source_url, color_checked_at, predecessor, note)
  select e->>'name', e->>'kpa_id', e->>'color', e->>'color_source_url',
         (e->>'color_checked_at')::date, e->>'predecessor', e->>'note'
  from jsonb_array_elements(p_parties) e
  on conflict (name) do update set
    kpa_id = excluded.kpa_id,
    color = excluded.color,
    color_source_url = excluded.color_source_url,
    color_checked_at = excluded.color_checked_at,
    predecessor = excluded.predecessor,
    note = excluded.note;
  get diagnostics n_parties = row_count;

  -- ---------------------------------------------------------------- ruling_periods
  delete from public.ruling_periods where true;
  insert into public.ruling_periods (starts_on, ends_on, party_name, president, note, source_url)
  select (e->>'starts_on')::date, (e->>'ends_on')::date, e->>'party_name', e->>'president',
         e->>'note', e->>'source_url'
  from jsonb_array_elements(p_ruling_periods) e;
  get diagnostics n_periods = row_count;

  -- ---------------------------------------------------------------- pledges
  insert into public.pledge_boards (district_id, source_url, publisher, fetched_at)
  select b->>'district_id', b->>'source_url', b->>'publisher', (b->>'fetched_at')::timestamptz
  from jsonb_array_elements(p_boards) b
  on conflict (district_id) do update set
    source_url = excluded.source_url,
    publisher = excluded.publisher,
    fetched_at = excluded.fetched_at;
  get diagnostics n_boards = row_count;

  -- A pledge KPA no longer lists goes if nobody judged it. A judged one stays, since the
  -- verdict is ours, and is reported so someone looks at it.
  select array_agg(x.id order by x.id) into judged_kept
  from public.pledges x
  where x.status <> 'notJudged'
    and exists (select 1 from jsonb_array_elements(p_boards) b where b->>'district_id' = x.district_id)
    and not exists (
      select 1 from jsonb_array_elements(p_boards) b, jsonb_array_elements(b->'pledges') p
      where p->>'id' = x.id
    );

  with gone as (
    delete from public.pledges x
    where x.status = 'notJudged'
      and exists (select 1 from jsonb_array_elements(p_boards) b where b->>'district_id' = x.district_id)
      and not exists (
        select 1 from jsonb_array_elements(p_boards) b, jsonb_array_elements(b->'pledges') p
        where p->>'id' = x.id
      )
    returning 1
  )
  select count(*) into n_removed from gone;

  with up as (
    insert into public.pledges
      (id, district_id, title, status, sort, page, source_url, publisher, fetched_at)
    select p->>'id', b->>'district_id', p->>'title', 'notJudged', (p->>'sort')::int,
           (p->>'page')::int, b->>'source_url', b->>'publisher', (b->>'fetched_at')::timestamptz
    from jsonb_array_elements(p_boards) b, jsonb_array_elements(b->'pledges') p
    on conflict (id) do update set
      title = excluded.title,
      sort = excluded.sort,
      page = excluded.page,
      source_url = excluded.source_url,
      publisher = excluded.publisher,
      fetched_at = excluded.fetched_at
    returning (xmax = 0) as inserted
  )
  select count(*), count(*) filter (where inserted) into n_pledges, n_new from up;

  -- ---------------------------------------------------------------- portraits
  -- Only the licence record. A member whose portrait is not copied yet has no row to
  -- update; they are listed, and the next release (or a force=1 rerun) picks them up.
  with upd as (
    update public.portraits t set
      license = e->>'license',
      attribution = e->>'attribution',
      license_checked_at = (e->>'license_checked_at')::timestamptz,
      license_note = e->>'license_note'
    from jsonb_array_elements(p_photos) e
    where t.mona_cd = e->>'mona_cd'
    returning 1
  )
  select count(*) into n_photos from upd;

  select array_agg(e->>'person_id' order by e->>'person_id') into photos_unmatched
  from jsonb_array_elements(p_photos) e
  where not exists (select 1 from public.portraits t where t.mona_cd = e->>'mona_cd');

  -- ---------------------------------------------------------------- local heads
  -- Both tables are KPA's alone, so they are replaced whole. Heads go first: they point
  -- at offices.
  delete from public.local_heads where true;
  delete from public.local_offices where true;
  insert into public.local_offices (id, level, code, sido, name, source_url, checked_at)
  select e->>'id', e->>'level', e->>'code', e->>'sido', e->>'name', e->>'source_url',
         (e->>'checked_at')::date
  from jsonb_array_elements(p_local_offices) e;
  get diagnostics n_offices = row_count;

  insert into public.local_heads
    (office_id, kpa_person_id, name, party, starts_on, how, election_id, source_url, checked_at)
  select e->>'office_id', e->>'kpa_person_id', e->>'name', e->>'party',
         (e->>'starts_on')::date, e->>'how', e->>'election_id', e->>'source_url',
         (e->>'checked_at')::date
  from jsonb_array_elements(p_local_heads) e;
  get diagnostics n_heads = row_count;

  summary := jsonb_build_object(
    'parties', n_parties,
    'rulingPeriods', n_periods,
    'boards', n_boards,
    'pledges', n_pledges,
    'pledgesNew', n_new,
    'pledgesRemoved', n_removed,
    'judgedKept', to_jsonb(coalesce(judged_kept, '{}')),
    'photos', n_photos,
    'photosUnmatched', to_jsonb(coalesce(photos_unmatched, '{}')),
    'localOffices', n_offices,
    'localHeads', n_heads
  );

  insert into public.kpa_imports (tag, schema_version, files, summary)
  values (p_tag, p_schema_version, p_files, summary)
  on conflict (tag) do update set
    schema_version = excluded.schema_version,
    files = excluded.files,
    summary = excluded.summary,
    applied_at = now();

  return summary;
end $$;

revoke execute on function public.kpa_apply(text, int, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb)
  from public, anon, authenticated;
