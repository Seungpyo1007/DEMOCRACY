-- The district channel (지역 채팅), live: every new or deleted message is broadcast to the
-- channel's readers through Supabase Realtime, sent from the database.
--
-- Principles (same as the community migration)
--  * Nothing about the tables changes. They stay RLS on, no policies, no grants: no client
--    reads them, and they are not added to any publication, so postgres_changes has
--    nothing to stream. What leaves is only what the trigger below composes.
--  * The payload is the message as GET /districts/{id}/community shows it, minus `mine`:
--      {id, author, body, verifiedResident, createdAt}
--    author is the 활동명, 「익명 주민」 when the author chose anonymous, or 「탈퇴한 주민」
--    when the account is gone -- the same rule as authorOf in bff/community.ts. author_id
--    and the anonymous flag never leave the database. A deletion sends {id, deleted: true}.
--  * Topic 'district-chat:<district_id>', public (realtime.send's last argument false).
--    The channel is readable by anyone through the BFF already, so a public topic reveals
--    nothing new; joining it needs the anon key and no policy on realtime.messages.
--  * A broadcast is a courtesy, never a gate. realtime.send already turns its own failures
--    into warnings; the trigger also catches the case where Realtime is not installed
--    (a bare local database), so a post never fails because nobody could be told.
--  * The trigger runs as its owner (security definer, search_path ''), because the BFF's
--    role is not granted realtime.send; nothing else about the caller is trusted.

-- The broadcast form of one message. Same author rule as bff/community.ts authorOf, and
-- createdAt in the BFF's form (UTC, milliseconds, 'Z').
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
    'body', p_message.body,
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
begin
  if tg_op = 'DELETE' then
    msg := old;
    payload := jsonb_build_object('id', old.id, 'deleted', true);
  else
    msg := new;
    payload := public.channel_message_payload(new);
  end if;
  begin
    perform realtime.send(
      payload,
      case when tg_op = 'DELETE' then 'delete' else 'message' end,
      'district-chat:' || msg.district_id,
      false
    );
  exception when undefined_function or invalid_schema_name then
    -- No Realtime in this database; readers see the change on their next fetch.
    null;
  end;
  return null;
end $$;

create trigger community_messages_broadcast
  after insert or delete on public.community_messages
  for each row execute function public.broadcast_channel_message();

do $$
declare f text;
begin
  foreach f in array array[
    'channel_message_payload(public.community_messages)',
    'broadcast_channel_message()'
  ] loop
    execute format('revoke execute on function public.%s from public, anon, authenticated', f);
  end loop;
end $$;
