-- Replies on discussion threads (정책 토론 답글): opening a thread, writing a reply, and the
-- live topic a thread's readers listen on.
--
-- Principles (same as the community and moderation migrations)
--  * No new table. thread_replies has been there since the community migration, with its
--    length CHECK, the hidden columns and its place in the rate limit, export and delete-me.
--  * Writing goes through community_write_check with the thread's district: the same
--    consent, residency and five-a-minute rules as reviews and the channel.
--  * One level only. A reply cannot answer a reply, and nothing ranks replies; they are
--    read oldest first, paged by (created_at, id).
--  * bff_district_threads already counts replies (the community migration), so the list and
--    the thread read the same number.
--  * Broadcasts follow the channel: topic 'thread:<thread_id>', public, composed here with
--    the same author rule and author tag, never author_id or the anonymous flag.

-- A thread with its bill, for GET /threads/{id}. bill_* are null when the bill row is gone
-- or the thread was not opened from a bill.
create or replace function public.bff_thread(p_thread_id text)
returns table (
  id text, district_id text, title text, origin text, bill_id text, source_url text,
  opened_at timestamptz, created_at timestamptz, replies int,
  bill_proposer text, bill_committee text, bill_propose_dt date, bill_committee_dt date,
  bill_cmt_proc_dt date, bill_proc_result text, bill_fetched_at timestamptz
)
language sql stable set search_path = '' as $$
  select t.id, t.district_id, t.title, t.origin, t.bill_id, t.source_url,
         t.opened_at, t.created_at,
         (select count(*)::int from public.thread_replies r where r.thread_id = t.id),
         b.proposer, b.committee, b.propose_dt, b.committee_dt,
         b.cmt_proc_dt, b.proc_result, b.fetched_at
  from public.community_threads t
  left join public.bills b on b.bill_id = t.bill_id
  where t.id = p_thread_id
$$;

-- One page of a thread's replies, oldest first, after the (created_at, id) cursor when
-- one is given. author_handle is null for a deleted account.
create or replace function public.bff_thread_replies(
  p_thread_id text, p_after_at timestamptz, p_after_id uuid, p_limit int
) returns table (
  id uuid, thread_id text, author_id uuid, body text, anonymous boolean,
  verified_resident boolean, created_at timestamptz, hidden_at timestamptz,
  author_handle text
)
language sql stable set search_path = '' as $$
  select r.id, r.thread_id, r.author_id, r.body, r.anonymous, r.verified_resident,
         r.created_at, r.hidden_at, p.handle
  from public.thread_replies r
  left join public.profiles p on p.user_id = r.author_id
  where r.thread_id = p_thread_id
    and (p_after_at is null or (r.created_at, r.id) > (p_after_at, p_after_id))
  order by r.created_at, r.id
  limit p_limit
$$;

-- Raises not_found for an unknown thread, then whatever community_write_check raises.
create or replace function public.post_thread_reply(
  p_user_id uuid, p_thread_id text, p_body text, p_anonymous boolean
) returns setof public.thread_replies
language plpgsql set search_path = '' as $$
declare d text;
begin
  select t.district_id into d from public.community_threads t where t.id = p_thread_id;
  if d is null then
    raise exception 'not_found';
  end if;
  perform public.community_write_check(p_user_id, d);
  return query insert into public.thread_replies
    (thread_id, author_id, body, anonymous, verified_resident)
    values (p_thread_id, p_user_id, p_body, p_anonymous, true)
    returning *;
end $$;

-- ------------------------------------------------------------------ broadcast

-- The reply as GET /threads/{id} shows it, minus `mine`, plus the author tag.
create or replace function public.thread_reply_payload(p_reply public.thread_replies)
returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'id', p_reply.id,
    'author', case
      when p_reply.author_id is null then '탈퇴한 주민'
      when p_reply.anonymous then '익명 주민'
      else coalesce(
        (select p.handle from public.profiles p where p.user_id = p_reply.author_id),
        '탈퇴한 주민'
      )
    end,
    'authorTag', public.author_tag(p_reply.author_id),
    'body', case when p_reply.hidden_at is null then p_reply.body
      else '신고로 가려진 글입니다.' end,
    'hidden', p_reply.hidden_at is not null,
    'verifiedResident', p_reply.verified_resident,
    'createdAt', to_char(p_reply.created_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
  )
$$;

create or replace function public.broadcast_thread_reply()
returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  reply public.thread_replies;
  payload jsonb;
  event text;
begin
  if tg_op = 'DELETE' then
    reply := old;
    payload := jsonb_build_object('id', old.id, 'deleted', true);
    event := 'delete';
  elsif tg_op = 'UPDATE' then
    if new.hidden_at is not distinct from old.hidden_at then
      return null;
    end if;
    reply := new;
    payload := public.thread_reply_payload(new);
    event := 'hidden';
  else
    reply := new;
    payload := public.thread_reply_payload(new);
    event := 'reply';
  end if;
  begin
    perform realtime.send(payload, event, 'thread:' || reply.thread_id, false);
  exception when undefined_function or invalid_schema_name then
    null;
  end;
  return null;
end $$;

create trigger thread_replies_broadcast
  after insert or delete or update of hidden_at on public.thread_replies
  for each row execute function public.broadcast_thread_reply();

do $$
declare f text;
begin
  foreach f in array array[
    'bff_thread(text)',
    'bff_thread_replies(text,timestamptz,uuid,int)',
    'post_thread_reply(uuid,text,text,boolean)',
    'thread_reply_payload(public.thread_replies)',
    'broadcast_thread_reply()'
  ] loop
    execute format('revoke execute on function public.%s from public, anon, authenticated', f);
  end loop;
end $$;
