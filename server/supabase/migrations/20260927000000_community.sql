-- Resident reviews (주민 평가), the district channel (지역 채팅) and discussion threads (정책 토론).
--
-- Principles (docs/ELECTION_LAW.md)
--  * Posts carry an author id and nothing else about the person. What other residents see
--    is the author's 활동명, or 「익명 주민」 when the author chose anonymous (the default in
--    the app), or 「탈퇴한 주민」 once the account is gone. No real name exists to show.
--  * author_id references profiles on delete set null, as the accounts migration asked:
--    DELETE /me?posts=keep leaves the posts with a null author; posts=delete removes them
--    before the profile goes.
--  * Only a resident with an unexpired residency row for the same district may write. The
--    write functions check it under the same transaction as the insert, and store the fact
--    as verified_resident so a later expiry does not rewrite history.
--  * Bodies are checked by the BFF before they arrive (content rules, length). The length
--    limits are repeated here as CHECKs so no other path can store an oversized post.
--  * Threads are not started by residents. They are opened from sourced events: today a
--    bill the district's incumbent sponsored (대표발의), linked to its bill page, so no one
--    owns a topic's framing by posting first.
--  * Same access model as init and accounts: RLS on, no policies, no grants; only the
--    `bff` function (service role) reads and writes.

-- One review per resident per district. A second review replaces the first.
-- The four axes are the app's ReviewDraft.axes: 소통, 공약이행, 지역발전, 도덕성.
create table public.reviews (
  id uuid primary key default gen_random_uuid(),
  district_id text not null references public.districts (id) on delete cascade,
  author_id uuid references public.profiles (user_id) on delete set null,
  communication smallint not null check (communication between 1 and 5),
  pledges smallint not null check (pledges between 1 and 5),
  development smallint not null check (development between 1 and 5),
  integrity smallint not null check (integrity between 1 and 5),
  score numeric(3, 2) generated always as
    ((communication + pledges + development + integrity) / 4.0) stored,
  body text not null check (char_length(body) between 10 and 500),
  anonymous boolean not null default true,
  verified_resident boolean not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- Nulls are distinct, so reviews left by deleted accounts never collide.
  unique (district_id, author_id)
);

create table public.community_messages (
  id uuid primary key default gen_random_uuid(),
  district_id text not null references public.districts (id) on delete cascade,
  author_id uuid references public.profiles (user_id) on delete set null,
  body text not null check (char_length(body) between 1 and 300),
  anonymous boolean not null default true,
  verified_resident boolean not null,
  created_at timestamptz not null default now()
);

-- A thread per sourced event. id is derived from the event ('bill-<bill_id>'), so the
-- sync below is idempotent and a thread keeps its id across runs.
create table public.community_threads (
  id text primary key,
  district_id text not null references public.districts (id) on delete cascade,
  origin text not null check (origin in ('bill')),
  bill_id text references public.bills (bill_id) on delete cascade,
  title text not null,
  source_url text not null check (public.is_presentable_source_url(source_url)),
  opened_at timestamptz not null,
  created_at timestamptz not null default now(),
  check (origin <> 'bill' or bill_id is not null),
  unique (district_id, bill_id)
);

create table public.thread_replies (
  id uuid primary key default gen_random_uuid(),
  thread_id text not null references public.community_threads (id) on delete cascade,
  author_id uuid references public.profiles (user_id) on delete set null,
  body text not null check (char_length(body) between 1 and 500),
  anonymous boolean not null default true,
  verified_resident boolean not null,
  created_at timestamptz not null default now()
);

-- Foreign keys and the read paths: newest posts per district, a user's posts (rate limit,
-- export, delete-me), replies per thread.
create index on public.reviews (district_id, updated_at desc);
create index on public.reviews (author_id, updated_at);
create index on public.community_messages (district_id, created_at desc);
create index on public.community_messages (author_id, created_at);
create index on public.community_threads (district_id, opened_at desc);
create index on public.community_threads (bill_id);
create index on public.thread_replies (thread_id, created_at);
create index on public.thread_replies (author_id, created_at);

-- ------------------------------------------------------------------ RLS: deny all

do $$
declare t text;
begin
  foreach t in array array['reviews', 'community_messages', 'community_threads', 'thread_replies']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
  end loop;
end $$;

-- ------------------------------------------------------------------ write functions
-- Each raises a bare code as its message (P0001), mapped by the BFF:
--   consent_required    no profile                                  → 403
--   residency_required  no unexpired residency for this district    → 403
--   rate_limited        more than 5 posts in the last minute        → 429

-- Shared checks for every write. Returns nothing; raises on failure. Locks the profile
-- row so two concurrent posts from one user are counted one after the other.
create or replace function public.community_write_check(p_user_id uuid, p_district_id text)
returns void
language plpgsql set search_path = '' as $$
declare recent int;
begin
  perform 1 from public.profiles p where p.user_id = p_user_id for update;
  if not found then
    raise exception 'consent_required';
  end if;
  if not exists (
    select 1 from public.residency_verifications r
    where r.user_id = p_user_id and r.district_id = p_district_id and r.expires_at > now()
  ) then
    raise exception 'residency_required';
  end if;
  select
    (select count(*) from public.reviews v
      where v.author_id = p_user_id and v.updated_at > now() - interval '1 minute')
    + (select count(*) from public.community_messages m
      where m.author_id = p_user_id and m.created_at > now() - interval '1 minute')
    + (select count(*) from public.thread_replies t
      where t.author_id = p_user_id and t.created_at > now() - interval '1 minute')
  into recent;
  if recent >= 5 then
    raise exception 'rate_limited';
  end if;
end $$;

-- Posts or replaces the user's review of a district.
create or replace function public.post_review(
  p_user_id uuid, p_district_id text, p_communication int, p_pledges int,
  p_development int, p_integrity int, p_body text, p_anonymous boolean
) returns setof public.reviews
language plpgsql set search_path = '' as $$
begin
  perform public.community_write_check(p_user_id, p_district_id);
  insert into public.reviews (
    district_id, author_id, communication, pledges, development, integrity,
    body, anonymous, verified_resident
  ) values (
    p_district_id, p_user_id, p_communication, p_pledges, p_development, p_integrity,
    p_body, p_anonymous, true
  )
  on conflict (district_id, author_id) do update set
    communication = excluded.communication,
    pledges = excluded.pledges,
    development = excluded.development,
    integrity = excluded.integrity,
    body = excluded.body,
    anonymous = excluded.anonymous,
    verified_resident = excluded.verified_resident,
    updated_at = now();
  return query select * from public.reviews v
    where v.district_id = p_district_id and v.author_id = p_user_id;
end $$;

create or replace function public.post_message(
  p_user_id uuid, p_district_id text, p_body text, p_anonymous boolean
) returns setof public.community_messages
language plpgsql set search_path = '' as $$
begin
  perform public.community_write_check(p_user_id, p_district_id);
  return query insert into public.community_messages
    (district_id, author_id, body, anonymous, verified_resident)
    values (p_district_id, p_user_id, p_body, p_anonymous, true)
    returning *;
end $$;

-- ------------------------------------------------------------------ read functions

-- The review summary for a district: mean score, respondents, and the mean of each axis.
-- Zero reviews yields respondents 0 and null means; the BFF sends that as the empty board.
create or replace function public.bff_review_summary(p_district_id text)
returns table (
  respondents int, average numeric, communication numeric, pledges numeric,
  development numeric, integrity numeric
)
language sql stable set search_path = '' as $$
  select count(*)::int,
         round(avg(v.score), 2),
         round(avg(v.communication), 2),
         round(avg(v.pledges), 2),
         round(avg(v.development), 2),
         round(avg(v.integrity), 2)
  from public.reviews v
  where v.district_id = p_district_id
$$;

-- A district's threads, newest event first, with their reply counts.
create or replace function public.bff_district_threads(p_district_id text, p_limit int)
returns table (id text, title text, origin text, source_url text, opened_at timestamptz, replies int)
language sql stable set search_path = '' as $$
  select t.id, t.title, t.origin, t.source_url, t.opened_at,
         (select count(*)::int from public.thread_replies r where r.thread_id = t.id)
  from public.community_threads t
  where t.district_id = p_district_id
  order by t.opened_at desc, t.id desc
  limit p_limit
$$;

-- ------------------------------------------------------------------ bill threads
-- Opens a thread for every bill of the current term whose 대표발의자 is a district's
-- current member. Idempotent: existing threads are left alone (on conflict do nothing),
-- so a thread's id and replies survive every run. The link is the bill's own page when
-- the Assembly gave one, else the dataset page the row came from.
create or replace function public.sync_bill_threads()
returns int language plpgsql set search_path = '' as $$
declare n int;
begin
  insert into public.community_threads (id, district_id, origin, bill_id, title, source_url, opened_at)
  select 'bill-' || b.bill_id,
         m.district_id,
         'bill',
         b.bill_id,
         b.bill_name,
         case when b.detail_link is not null and public.is_presentable_source_url(b.detail_link)
              then b.detail_link else b.source_url end,
         coalesce(b.propose_dt::timestamptz, b.fetched_at)
  from public.bills b
  join public.members m on m.mona_cd = b.rst_mona_cd and m.is_current and m.district_id is not null
  where b.age = (select max(x.age) from public.bills x)
  on conflict do nothing;
  get diagnostics n = row_count;
  return n;
end $$;

do $$
declare f text;
begin
  foreach f in array array[
    'community_write_check(uuid,text)',
    'post_review(uuid,text,int,int,int,int,text,boolean)',
    'post_message(uuid,text,text,boolean)',
    'bff_review_summary(text)',
    'bff_district_threads(text,int)',
    'sync_bill_threads()'
  ] loop
    execute format('revoke execute on function public.%s from public, anon, authenticated', f);
  end loop;
end $$;

-- ------------------------------------------------------------------ cron
-- 15 minutes after each ingest-assembly-bills run ('20 */6 * * *').
select cron.schedule('sync-bill-threads', '35 */6 * * *', $$select public.sync_bill_threads()$$);
