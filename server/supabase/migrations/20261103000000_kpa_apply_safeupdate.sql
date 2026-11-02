-- kpa_apply again, with one change: the ruling_periods wipe says `where true`.
--
-- PostgREST runs with pg_safeupdate, which refuses a DELETE without a WHERE clause.
-- The first production call of kpa_apply stopped there and rolled back.

create or replace function public.kpa_apply(
  p_tag text, p_schema_version int, p_files jsonb,
  p_parties jsonb, p_ruling_periods jsonb, p_boards jsonb, p_photos jsonb
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

  summary := jsonb_build_object(
    'parties', n_parties,
    'rulingPeriods', n_periods,
    'boards', n_boards,
    'pledges', n_pledges,
    'pledgesNew', n_new,
    'pledgesRemoved', n_removed,
    'judgedKept', to_jsonb(coalesce(judged_kept, '{}')),
    'photos', n_photos,
    'photosUnmatched', to_jsonb(coalesce(photos_unmatched, '{}'))
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

revoke execute on function public.kpa_apply(text, int, jsonb, jsonb, jsonb, jsonb, jsonb)
  from public, anon, authenticated;
