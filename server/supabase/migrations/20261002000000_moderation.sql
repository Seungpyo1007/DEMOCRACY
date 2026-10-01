-- Moderation: reports (신고), blocks (차단), hiding, and the staff who resolve reports.
--
-- Principles
--  * Both stores require that residents can report a post and block its author from
--    inside the app. This is that, and the least the staff side needs to act on it.
--  * A report hides a post on its own only when waiting would do harm: one report of
--    exposed personal information, or three readers reporting the same post. A report of a
--    false claim never hides anything by itself -- a count of reports cannot tell a false
--    claim from an unwelcome one, and deciding which is a person's job.
--  * Hidden is not deleted. The post stays, readers see 「신고로 가려진 글입니다」 in its
--    place, and staff either restore it, keep it hidden or delete it.
--  * Blocking works without the reader ever learning who wrote a post: they name a post,
--    the database finds its author. Lists come back with the blocked authors' posts left
--    out. The live channel cannot be filtered per reader, so each broadcast carries an
--    author tag -- an HMAC of the author id and today's date (KST) under a key only this
--    database holds -- and GET /me/blocks hands the reader today's tags of the people they
--    blocked. Tags change at midnight, so even anonymous posts can be linked to each other
--    only within a day.
--  * Staff are added by hand (SQL), never through the app. Everything they do is written
--    to staff_actions with the reason.
--  * Same access model as before: RLS on, no policies, no grants; only the BFF reads and
--    writes, through the functions below.

-- ------------------------------------------------------------------ staff

create table public.staff (
  user_id uuid primary key references auth.users (id) on delete cascade,
  role text not null check (role in ('moderator', 'admin')),
  added_at timestamptz not null default now(),
  note text
);

create table public.staff_actions (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid references public.staff (user_id) on delete set null,
  action text not null check (action in ('keep', 'hide', 'delete')),
  target_type text not null check (target_type in ('review', 'message', 'reply')),
  target_id uuid not null,
  reason text not null check (char_length(reason) between 1 and 300),
  at timestamptz not null default now()
);
create index on public.staff_actions (staff_id);
create index on public.staff_actions (target_type, target_id);

-- ------------------------------------------------------------------ hiding

alter table public.reviews
  add column hidden_at timestamptz,
  add column hidden_reason text;
alter table public.community_messages
  add column hidden_at timestamptz,
  add column hidden_reason text;
alter table public.thread_replies
  add column hidden_at timestamptz,
  add column hidden_reason text;

-- ------------------------------------------------------------------ reports

create table public.reports (
  id uuid primary key default gen_random_uuid(),
  target_type text not null check (target_type in ('review', 'message', 'reply')),
  target_id uuid not null,
  -- Who reported is kept so one reader cannot count three times; a deleted account
  -- leaves its reports standing with no reporter.
  reporter_id uuid references public.profiles (user_id) on delete set null,
  reason text not null check (reason in ('hate', 'privacy', 'false', 'spam', 'other')),
  note text check (note is null or char_length(note) <= 200),
  status text not null default 'open' check (status in ('open', 'kept', 'hidden', 'deleted')),
  created_at timestamptz not null default now(),
  resolved_by uuid references public.staff (user_id) on delete set null,
  resolved_at timestamptz,
  unique (target_type, target_id, reporter_id)
);
create index on public.reports (status, created_at);
create index on public.reports (target_type, target_id);
create index on public.reports (reporter_id, created_at);
create index on public.reports (resolved_by);

-- ------------------------------------------------------------------ blocks

create table public.blocks (
  id uuid primary key default gen_random_uuid(),
  blocker_id uuid not null references public.profiles (user_id) on delete cascade,
  blocked_id uuid not null references public.profiles (user_id) on delete cascade,
  -- How the blocker saw the author when they blocked: the 활동명, or 「익명 주민」. The
  -- list shows this, never the account.
  label text not null,
  created_at timestamptz not null default now(),
  unique (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);
create index on public.blocks (blocked_id);

-- ------------------------------------------------------------------ author tags

-- One random key, made here and never read out. An HMAC under it cannot be reversed to
-- an author id without it.
create table public.moderation_key (
  id boolean primary key default true check (id),
  key bytea not null default extensions.gen_random_bytes(32)
);
insert into public.moderation_key default values;

create or replace function public.author_tag(p_author uuid)
returns text
language sql stable set search_path = '' as $$
  select case when p_author is null then null else
    left(encode(extensions.hmac(
      convert_to(p_author::text || ':' || ((now() at time zone 'Asia/Seoul')::date)::text, 'UTF8'),
      (select k.key from public.moderation_key k),
      'sha256'
    ), 'hex'), 24)
  end
$$;

do $$
declare t text;
begin
  foreach t in array array['staff', 'staff_actions', 'reports', 'blocks', 'moderation_key']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
  end loop;
end $$;

-- ------------------------------------------------------------------ functions
-- Raise a bare code as the message (P0001), mapped by the BFF:
--   consent_required   no profile                                  → 403
--   not_found          no such post                                → 404
--   own_post           reporting or blocking yourself              → 400
--   no_author          the author's account is gone                → 400
--   already_reported   this reader already reported this post      → 409
--   rate_limited       more than 20 reports in a day               → 429
--   not_staff          resolving without a staff row               → 403

-- The author of a post, or not_found.
create or replace function public.post_author(p_type text, p_id uuid, out author uuid, out anonymous boolean)
language plpgsql stable set search_path = '' as $$
begin
  if p_type = 'review' then
    select v.author_id, v.anonymous into author, anonymous from public.reviews v where v.id = p_id;
  elsif p_type = 'message' then
    select m.author_id, m.anonymous into author, anonymous
      from public.community_messages m where m.id = p_id;
  elsif p_type = 'reply' then
    select r.author_id, r.anonymous into author, anonymous
      from public.thread_replies r where r.id = p_id;
  end if;
  if not found then
    raise exception 'not_found';
  end if;
end $$;

create or replace function public.set_post_hidden(p_type text, p_id uuid, p_reason text)
returns void
language plpgsql set search_path = '' as $$
begin
  if p_type = 'review' then
    update public.reviews set hidden_at = case when p_reason is null then null else now() end,
      hidden_reason = p_reason where id = p_id;
  elsif p_type = 'message' then
    update public.community_messages
      set hidden_at = case when p_reason is null then null else now() end,
      hidden_reason = p_reason where id = p_id;
  elsif p_type = 'reply' then
    update public.thread_replies
      set hidden_at = case when p_reason is null then null else now() end,
      hidden_reason = p_reason where id = p_id;
  end if;
end $$;

-- Files a report and hides the post when the rule says so. Returns whether the post is
-- hidden now.
create or replace function public.report_post(
  p_reporter uuid, p_type text, p_id uuid, p_reason text, p_note text
) returns boolean
language plpgsql set search_path = '' as $$
declare
  a record;
  today int;
  reporters int;
begin
  perform 1 from public.profiles p where p.user_id = p_reporter for update;
  if not found then
    raise exception 'consent_required';
  end if;
  select * into a from public.post_author(p_type, p_id);
  if a.author = p_reporter then
    raise exception 'own_post';
  end if;
  select count(*) into today from public.reports r
    where r.reporter_id = p_reporter and r.created_at > now() - interval '1 day';
  if today >= 20 then
    raise exception 'rate_limited';
  end if;
  insert into public.reports (target_type, target_id, reporter_id, reason, note)
    values (p_type, p_id, p_reporter, p_reason, nullif(btrim(p_note), ''))
    on conflict (target_type, target_id, reporter_id) do nothing;
  if not found then
    raise exception 'already_reported';
  end if;
  select count(distinct r.reporter_id) into reporters from public.reports r
    where r.target_type = p_type and r.target_id = p_id and r.status = 'open';
  if p_reason = 'privacy' or reporters >= 3 then
    perform public.set_post_hidden(p_type, p_id,
      case when p_reason = 'privacy' then 'privacy' else 'reports' end);
    return true;
  end if;
  return false;
end $$;

-- Blocks the author of a post. Returns the block.
create or replace function public.block_author(p_blocker uuid, p_type text, p_id uuid)
returns setof public.blocks
language plpgsql set search_path = '' as $$
declare
  a record;
  shown text;
begin
  if not exists (select 1 from public.profiles p where p.user_id = p_blocker) then
    raise exception 'consent_required';
  end if;
  select * into a from public.post_author(p_type, p_id);
  if a.author is null then
    raise exception 'no_author';
  end if;
  if a.author = p_blocker then
    raise exception 'own_post';
  end if;
  shown := case when a.anonymous then '익명 주민'
    else coalesce((select p.handle from public.profiles p where p.user_id = a.author), '익명 주민')
  end;
  return query insert into public.blocks (blocker_id, blocked_id, label)
    values (p_blocker, a.author, shown)
    on conflict (blocker_id, blocked_id) do update set label = public.blocks.label
    returning *;
end $$;

-- A reader's blocks, newest first, with today's tag of each blocked author.
create or replace function public.bff_my_blocks(p_user uuid)
returns table (id uuid, label text, created_at timestamptz, author_tag text)
language sql stable set search_path = '' as $$
  select b.id, b.label, b.created_at, public.author_tag(b.blocked_id)
  from public.blocks b
  where b.blocker_id = p_user
  order by b.created_at desc
$$;

-- The authors a reader blocked, for leaving their posts out of a list.
create or replace function public.bff_blocked_authors(p_user uuid)
returns setof uuid
language sql stable set search_path = '' as $$
  select b.blocked_id from public.blocks b where b.blocker_id = p_user
$$;

-- Staff: resolves every open report on the post the report names, and logs it.
--   keep    the post is shown again
--   hide    stays hidden (or is hidden now)
--   delete  the post is removed; the reports stay, marked deleted
create or replace function public.resolve_report(
  p_staff uuid, p_report uuid, p_action text, p_reason text
) returns void
language plpgsql set search_path = '' as $$
declare r record;
begin
  if not exists (select 1 from public.staff s where s.user_id = p_staff) then
    raise exception 'not_staff';
  end if;
  select * into r from public.reports where id = p_report;
  if not found then
    raise exception 'not_found';
  end if;
  if p_action = 'keep' then
    perform public.set_post_hidden(r.target_type, r.target_id, null);
  elsif p_action = 'hide' then
    perform public.set_post_hidden(r.target_type, r.target_id, 'staff');
  elsif p_action = 'delete' then
    if r.target_type = 'review' then
      delete from public.reviews where id = r.target_id;
    elsif r.target_type = 'message' then
      delete from public.community_messages where id = r.target_id;
    else
      delete from public.thread_replies where id = r.target_id;
    end if;
  else
    raise exception 'bad_action';
  end if;
  update public.reports set
    status = case p_action when 'keep' then 'kept' when 'hide' then 'hidden' else 'deleted' end,
    resolved_by = p_staff,
    resolved_at = now()
  where target_type = r.target_type and target_id = r.target_id and status = 'open';
  insert into public.staff_actions (staff_id, action, target_type, target_id, reason)
    values (p_staff, p_action, r.target_type, r.target_id, p_reason);
end $$;

-- Staff: open reports grouped by post, oldest first, with the post as it reads now.
create or replace function public.staff_open_reports(p_limit int)
returns table (
  report_id uuid, target_type text, target_id uuid, district_id text, body text,
  hidden boolean, reasons text[], reports int, first_at timestamptz
)
language sql stable set search_path = '' as $$
  with grouped as (
    select r.target_type, r.target_id,
           (array_agg(r.id order by r.created_at))[1] as report_id,
           array_agg(distinct r.reason) as reasons,
           count(*)::int as reports,
           min(r.created_at) as first_at
    from public.reports r
    where r.status = 'open'
    group by r.target_type, r.target_id
  )
  select o.report_id, o.target_type, o.target_id,
         coalesce(v.district_id, m.district_id, t.district_id),
         coalesce(v.body, m.body, p.body),
         coalesce(v.hidden_at, m.hidden_at, p.hidden_at) is not null,
         o.reasons, o.reports, o.first_at
  from grouped o
  left join public.reviews v on o.target_type = 'review' and v.id = o.target_id
  left join public.community_messages m on o.target_type = 'message' and m.id = o.target_id
  left join public.thread_replies p on o.target_type = 'reply' and p.id = o.target_id
  left join public.community_threads t on t.id = p.thread_id
  order by o.first_at
  limit p_limit
$$;

-- A hidden review no longer counts toward the district's score.
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
  where v.district_id = p_district_id and v.hidden_at is null
$$;

-- ------------------------------------------------------------------ broadcast
-- The channel payload gains the author tag, and a post hidden or shown again is
-- broadcast like an edit: {id, hidden: true|false}. Readers drop or restore it.

create or replace function public.channel_message_payload(p_message public.community_messages)
returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'id', p_message.id,
    'author', case
      when p_message.author_id is null then '탈퇴한 주민'
      when p_message.anonymous then '익명 주민'
      else coalesce(
        (select p.handle from public.profiles p where p.user_id = p_message.author_id),
        '탈퇴한 주민'
      )
    end,
    'authorTag', public.author_tag(p_message.author_id),
    'body', case when p_message.hidden_at is null then p_message.body
      else '신고로 가려진 글입니다.' end,
    'hidden', p_message.hidden_at is not null,
    'verifiedResident', p_message.verified_resident,
    'createdAt', to_char(p_message.created_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
  )
$$;

create or replace function public.broadcast_channel_message()
returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  msg public.community_messages;
  payload jsonb;
  event text;
begin
  if tg_op = 'DELETE' then
    msg := old;
    payload := jsonb_build_object('id', old.id, 'deleted', true);
    event := 'delete';
  elsif tg_op = 'UPDATE' then
    if new.hidden_at is not distinct from old.hidden_at then
      return null;
    end if;
    msg := new;
    payload := public.channel_message_payload(new);
    event := 'hidden';
  else
    msg := new;
    payload := public.channel_message_payload(new);
    event := 'message';
  end if;
  begin
    perform realtime.send(payload, event, 'district-chat:' || msg.district_id, false);
  exception when undefined_function or invalid_schema_name then
    null;
  end;
  return null;
end $$;

drop trigger community_messages_broadcast on public.community_messages;
create trigger community_messages_broadcast
  after insert or delete or update of hidden_at on public.community_messages
  for each row execute function public.broadcast_channel_message();

do $$
declare f text;
begin
  foreach f in array array[
    'author_tag(uuid)',
    'post_author(text,uuid)',
    'set_post_hidden(text,uuid,text)',
    'report_post(uuid,text,uuid,text,text)',
    'block_author(uuid,text,uuid)',
    'bff_my_blocks(uuid)',
    'bff_blocked_authors(uuid)',
    'resolve_report(uuid,uuid,text,text)',
    'staff_open_reports(int)',
    'channel_message_payload(public.community_messages)',
    'broadcast_channel_message()'
  ] loop
    execute format('revoke execute on function public.%s from public, anon, authenticated', f);
  end loop;
end $$;
