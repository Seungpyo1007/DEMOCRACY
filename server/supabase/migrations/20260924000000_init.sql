-- DEMOCRACY data backend: schema, RLS, BFF helper functions, cron schedules.
--
-- Principles
--  * raw_* keep the fetched payload (minus personal fields) + source_url + fetched_at.
--  * Every normalized row carries source_url + publisher + fetched_at. source_url is a
--    human-visitable dataset page, never a keyed API URL (enforced by a CHECK).
--  * RLS is enabled on every table with NO policies: anon/authenticated cannot read or
--    write anything. Only edge functions using the service role (which bypasses RLS) can.
--  * Candidate rows hold name, party, huboid and short 경력 only. No address, birth date,
--    criminal record. Preliminary candidates are purged after their election.
--  * No rankings, scores or evaluative labels anywhere in the schema.

create extension if not exists pg_cron;
create extension if not exists pg_net;

-- A source URL must be http(s) and must not carry an API credential.
create or replace function public.is_presentable_source_url(u text)
returns boolean language sql immutable as $$
  select u ~ '^https?://[^/]+' and u !~* '[?&](KEY|ServiceKey|confmKey|apikey|api_key)='
$$;

-- ------------------------------------------------------------------ raw

create table public.raw_assembly (
  id bigint generated always as identity primary key,
  service text not null,
  request_key text not null,           -- canonical params, credential-free
  page int not null,
  payload jsonb not null,
  source_url text not null check (public.is_presentable_source_url(source_url)),
  fetched_at timestamptz not null,
  unique (service, request_key, page)
);

create table public.raw_nec (
  id bigint generated always as identity primary key,
  service text not null,
  request_key text not null,
  page int not null,
  payload jsonb not null,              -- person fields redacted before insert
  source_url text not null check (public.is_presentable_source_url(source_url)),
  fetched_at timestamptz not null,
  unique (service, request_key, page)
);

-- ------------------------------------------------------------------ elections / districts

create table public.elections (
  sg_id text not null,
  sg_typecode int not null,
  sg_name text not null,
  vote_date date,
  term int,                            -- 제N대 for general 국회의원 elections, else null
  -- Set by a human while a count is in progress; the BFF then emits an `ongoing` row
  -- and serves no figures for that election.
  count_status text not null default 'none' check (count_status in ('none', 'counting', 'final')),
  source_url text not null check (public.is_presentable_source_url(source_url)),
  publisher text not null,
  fetched_at timestamptz not null,
  primary key (sg_id, sg_typecode)
);

-- 22대 국회의원 지역구 (sgId 20240410, sgTypecode 2). id = 'nec-' || sgg_code.
create table public.districts (
  id text primary key check (id ~ '^nec-[0-9a-z]+$'),
  sg_id text not null,
  sg_typecode int not null,
  sgg_code text not null,
  sd_name text not null,
  wiw_name text,
  sgg_name text not null,
  display_name text not null,          -- "서울 마포구 을"
  name_key text not null,              -- "서울마포구을" (join key with Assembly ORIG_NM, NEC names)
  sgg_jungsu int,
  s_order int,
  source_url text not null check (public.is_presentable_source_url(source_url)),
  publisher text not null,
  fetched_at timestamptz not null,
  unique (sg_id, sgg_code),
  unique (sg_id, name_key)
);

-- 행정동 → 선거구 per election, generated from 공직선거법 [별표2] (scripts/import_district_areas.ts).
-- hdong_code is a 10-digit 행정동 code, or a 5-digit 시군구 code when the whole 시군구
-- belongs to one 선거구.
create table public.district_areas (
  election_sg_id text not null,
  hdong_code text not null check (hdong_code ~ '^([0-9]{5}|[0-9]{10})$'),
  sgg_code text not null,
  hdong_name text,
  sigungu_code text not null check (sigungu_code ~ '^[0-9]{5}$'),
  source_url text not null check (public.is_presentable_source_url(source_url)),
  fetched_at timestamptz not null,
  primary key (election_sg_id, hdong_code)
);
create index on public.district_areas (election_sg_id, sigungu_code);

-- 법정동 → 행정동 bridge (many-to-many), from 행정안전부 행정동·법정동 mapping.
create table public.bjdong_hdong (
  bjd_code text not null check (bjd_code ~ '^[0-9]{10}$'),
  hdong_code text not null check (hdong_code ~ '^[0-9]{10}$'),
  hdong_name text,
  source_url text not null check (public.is_presentable_source_url(source_url)),
  fetched_at timestamptz not null,
  primary key (bjd_code, hdong_code)
);

-- Curated: which past-election 선거구 (by name key) a current district continues,
-- when redistricting renamed it. Absent rows = same name_key.
create table public.district_lineage (
  district_id text not null references public.districts (id) on delete cascade,
  sg_id text not null,
  name_key text not null,
  note text,
  primary key (district_id, sg_id, name_key)
);

-- Optional 22대 boundary shapes (scripts/import_geojson.ts). License must be recorded.
create table public.district_shapes (
  district_id text primary key references public.districts (id) on delete cascade,
  geojson jsonb not null,
  license_note text not null,
  source_url text not null check (public.is_presentable_source_url(source_url)),
  fetched_at timestamptz not null
);

-- ------------------------------------------------------------------ Assembly

create table public.members (
  mona_cd text primary key,
  name text not null,
  party text,
  orig_nm text,
  district_key text,
  district_id text references public.districts (id) on delete set null,
  elect_gbn text,
  reele_gbn text,
  units text,
  committees text,
  photo_url text,                      -- assembly.go.kr URL only; never re-hosted
  is_current boolean not null default true,
  source_url text not null check (public.is_presentable_source_url(source_url)),
  publisher text not null,
  fetched_at timestamptz not null
);
create index on public.members (district_id) where is_current;

-- Curated fix-ups when ORIG_NM does not match a 22대 district name (e.g. after a 시도 merger).
create table public.member_district_overrides (
  mona_cd text primary key,
  district_id text not null references public.districts (id) on delete cascade,
  note text
);

create table public.bills (
  bill_id text primary key,
  bill_no text,
  age int not null,
  bill_name text not null,
  proposer text,
  rst_mona_cd text,                    -- 대표발의자
  propose_dt date,
  committee text,
  committee_dt date,
  cmt_proc_dt date,
  proc_result text,
  proc_dt date,
  detail_link text,
  source_url text not null check (public.is_presentable_source_url(source_url)),
  publisher text not null,
  fetched_at timestamptz not null
);
create index on public.bills (rst_mona_cd, age, propose_dt desc);
create index on public.bills (age, proc_dt desc) where proc_result is not null;

create table public.bill_votes (
  bill_id text not null,
  mona_cd text not null,
  result text not null check (result in ('찬성', '반대', '기권', '불참')),
  vote_at timestamptz not null,
  age int not null,
  source_url text not null check (public.is_presentable_source_url(source_url)),
  publisher text not null,
  fetched_at timestamptz not null,
  primary key (bill_id, mona_cd)
);
create index on public.bill_votes (mona_cd, vote_at);

create table public.vote_fetch_log (
  bill_id text primary key,
  row_count int not null,
  checked_at timestamptz not null
);

-- Imported from the Assembly's plenary attendance file dataset (scripts/import_attendance.ts).
create table public.plenary_attendance (
  mona_cd text not null,
  meeting_date date not null,
  meeting_label text not null,         -- e.g. "제418회 제3차"
  status text not null,                -- source wording: 출석 / 결석 / 청가 / 출장 ...
  source_url text not null check (public.is_presentable_source_url(source_url)),
  publisher text not null,
  fetched_at timestamptz not null,
  primary key (mona_cd, meeting_date, meeting_label)
);

-- ------------------------------------------------------------------ NEC results / candidates

create table public.election_results (
  sg_id text not null,
  sg_typecode int not null,
  huboid text not null,
  sd_name text not null,
  sgg_name text not null,
  name_key text not null,
  name text not null,
  party text,
  votes numeric,
  share numeric,                       -- dugyul, percent
  is_winner boolean not null default true,
  source_url text not null check (public.is_presentable_source_url(source_url)),
  publisher text not null,
  fetched_at timestamptz not null,
  primary key (sg_id, sg_typecode, huboid)
);
create index on public.election_results (name_key);

create table public.candidates (
  sg_id text not null,
  sg_typecode int not null,
  huboid text not null,
  kind text not null check (kind in ('preliminary', 'final')),
  sd_name text not null,
  sgg_name text not null,
  name_key text not null,
  name text not null,
  party text,
  status text,                         -- 등록 / 사퇴 / 사망 / 등록무효
  career1 text check (char_length(career1) <= 60),
  career2 text check (char_length(career2) <= 60),
  source_url text not null check (public.is_presentable_source_url(source_url)),
  publisher text not null,
  fetched_at timestamptz not null,
  primary key (sg_id, sg_typecode, huboid, kind)
);
create index on public.candidates (name_key, sg_id);

-- ------------------------------------------------------------------ curated

create table public.region_timelines (
  district_id text primary key references public.districts (id) on delete cascade,
  source_url text not null check (public.is_presentable_source_url(source_url)),
  publisher text not null,
  fetched_at timestamptz not null
);

create table public.region_events (
  id bigint generated always as identity primary key,
  district_id text not null references public.region_timelines (district_id) on delete cascade,
  year int,                            -- null = date not confirmed
  title text not null check (title <> ''),
  detail text,
  sort int not null default 0,
  source_url text not null check (public.is_presentable_source_url(source_url)),
  publisher text not null,
  fetched_at timestamptz not null
);

create table public.pledge_boards (
  district_id text primary key references public.districts (id) on delete cascade,
  source_url text not null check (public.is_presentable_source_url(source_url)),
  publisher text not null,
  fetched_at timestamptz not null
);

create table public.pledges (
  id text primary key,
  district_id text not null references public.pledge_boards (district_id) on delete cascade,
  mona_cd text,
  title text not null check (title <> ''),
  category text,
  status text not null check (status in ('fulfilled', 'inProgress', 'unfulfilled', 'reversed')),
  evidence_url text,
  bill_ids text[] not null default '{}', -- evidence links to bills
  judgement jsonb,                     -- {steps:[{actor,detail,stamp}], source:{sourceUrl,fetchedAt}}
  sort int not null default 0,
  source_url text not null check (public.is_presentable_source_url(source_url)),
  publisher text not null,
  fetched_at timestamptz not null,
  check (status <> 'reversed' or evidence_url is not null)
);

-- ------------------------------------------------------------------ RLS: deny all

do $$
declare t text;
begin
  foreach t in array array[
    'raw_assembly','raw_nec','elections','districts','district_areas','bjdong_hdong',
    'district_lineage','district_shapes','members','member_district_overrides','bills',
    'bill_votes','vote_fetch_log','plenary_attendance','election_results','candidates',
    'region_timelines','region_events','pledge_boards','pledges'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
  end loop;
end $$;

-- ------------------------------------------------------------------ BFF / ingest helpers

create or replace function public.bff_bill_count(p_mona_cd text, p_age int)
returns table (count int, fetched_at timestamptz)
language sql stable as $$
  select
    (select count(*)::int from public.bills where rst_mona_cd = p_mona_cd and age = p_age),
    coalesce(
      (select max(b.fetched_at) from public.bills b where b.rst_mona_cd = p_mona_cd and b.age = p_age),
      (select max(b.fetched_at) from public.bills b where b.age = p_age)
    )
$$;

-- Monthly plenary vote participation: votes other than 불참 / all recorded votes.
create or replace function public.bff_monthly_vote_participation(p_mona_cd text, p_months int)
returns table (month text, numerator int, denominator int, source_url text, fetched_at timestamptz)
language sql stable as $$
  select * from (
    select to_char(vote_at at time zone 'Asia/Seoul', 'YYYY-MM') as month,
           count(*) filter (where result <> '불참')::int,
           count(*)::int,
           min(source_url),
           max(fetched_at)
    from public.bill_votes
    where mona_cd = p_mona_cd
    group by 1
    order by 1 desc
    limit p_months
  ) m order by month
$$;

-- Monthly plenary attendance: meetings with status 출석 / all meetings on record.
create or replace function public.bff_monthly_attendance(p_mona_cd text, p_months int)
returns table (month text, numerator int, denominator int, source_url text, fetched_at timestamptz)
language sql stable as $$
  select * from (
    select to_char(meeting_date, 'YYYY-MM') as month,
           count(*) filter (where status = '출석')::int,
           count(*)::int,
           min(source_url),
           max(fetched_at)
    from public.plenary_attendance
    where mona_cd = p_mona_cd
    group by 1
    order by 1 desc
    limit p_months
  ) m order by month
$$;

create or replace function public.bff_attendance_since(p_mona_cd text, p_since date)
returns table (month text, numerator int, denominator int, source_url text, fetched_at timestamptz)
language sql stable as $$
  select to_char(p_since, 'YYYY-MM'),
         count(*) filter (where status = '출석')::int,
         count(*)::int,
         min(source_url),
         max(fetched_at)
  from public.plenary_attendance
  where mona_cd = p_mona_cd and meeting_date >= p_since
$$;

create or replace function public.bills_needing_votes(
  p_age int, p_results text[], p_retry_since date, p_limit int
) returns table (bill_id text)
language sql stable as $$
  select b.bill_id
  from public.bills b
  left join public.vote_fetch_log l on l.bill_id = b.bill_id
  where b.age = p_age
    and b.proc_result = any (p_results)
    and b.proc_dt is not null
    and (l.bill_id is null or (l.row_count = 0 and b.proc_dt >= p_retry_since))
  order by b.proc_dt desc
  limit p_limit
$$;

-- Deletes preliminary candidates (예비후보자) once their election day has passed,
-- plus their raw pages. Registered-candidate rows are kept as the election record.
create or replace function public.purge_preliminary_candidates()
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  delete from public.candidates c
  using public.elections e
  where c.kind = 'preliminary'
    and e.sg_id = c.sg_id and e.sg_typecode = c.sg_typecode
    and e.vote_date < (now() at time zone 'Asia/Seoul')::date;
  get diagnostics n = row_count;
  delete from public.raw_nec r
  using public.elections e
  where r.service like '%getPoelpcddRegistSttusInfoInqire'
    and r.request_key like '%sgId=' || e.sg_id || '%'
    and e.vote_date < (now() at time zone 'Asia/Seoul')::date;
  return n;
end $$;

-- Raw retention: vote pages are bulky and fully represented in bill_votes.
create or replace function public.purge_raw()
returns void language sql security definer set search_path = public as $$
  delete from public.raw_assembly where service = 'nojepdqqaweusdfbi' and fetched_at < now() - interval '14 days';
  delete from public.raw_assembly where fetched_at < now() - interval '90 days';
  delete from public.raw_nec where fetched_at < now() - interval '180 days';
$$;

do $$
declare f text;
begin
  foreach f in array array[
    'bff_bill_count(text,int)', 'bff_monthly_vote_participation(text,int)',
    'bff_monthly_attendance(text,int)', 'bff_attendance_since(text,date)',
    'bills_needing_votes(int,text[],date,int)', 'purge_preliminary_candidates()', 'purge_raw()'
  ] loop
    execute format('revoke execute on function public.%s from public, anon, authenticated', f);
  end loop;
end $$;

-- ------------------------------------------------------------------ cron
-- Needs two Vault secrets (see README):  project_url  and  ingest_secret.
-- Secrets are read at run time, so this migration applies before they exist.

create or replace function public.call_ingest(p_function text, p_query text)
returns bigint language sql security definer set search_path = public as $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url')
           || '/functions/v1/' || p_function || '?' || p_query,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-ingest-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'ingest_secret')
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 300000
  )
$$;
revoke execute on function public.call_ingest(text, text) from public, anon, authenticated;

-- Times are UTC. 18:10 UTC = 03:10 KST.
select cron.schedule('ingest-assembly-members',  '10 18 * * *',  $$select public.call_ingest('ingest-assembly', 'mode=members')$$);
select cron.schedule('ingest-assembly-bills',    '20 */6 * * *', $$select public.call_ingest('ingest-assembly', 'mode=bills_votes')$$);
-- Extra vote batches between bill runs to work through the 22대 backlog.
select cron.schedule('ingest-assembly-votes',    '50 * * * *',   $$select public.call_ingest('ingest-assembly', 'mode=votes')$$);
select cron.schedule('ingest-nec-codes',         '30 18 * * 1',  $$select public.call_ingest('ingest-nec', 'mode=codes')$$);
-- Weekly in normal times. In an election period switch to hourly:
--   select cron.alter_job((select jobid from cron.job where jobname = 'ingest-nec-candidates'), schedule := '5 * * * *');
select cron.schedule('ingest-nec-candidates',    '40 18 * * 1',  $$select public.call_ingest('ingest-nec', 'mode=candidates')$$);
select cron.schedule('purge-preliminary',        '0 19 * * *',   $$select public.purge_preliminary_candidates()$$);
select cron.schedule('purge-raw',                '15 19 * * 0',  $$select public.purge_raw()$$);
-- Historical winners are a one-off:  select public.call_ingest('ingest-nec', 'mode=backfill');
