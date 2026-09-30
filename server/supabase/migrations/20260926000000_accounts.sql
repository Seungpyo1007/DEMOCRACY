-- Accounts, consents, activity names (활동명) and resident verification.
--
-- Principles (docs/ELECTION_LAW.md)
--  * No real name, no phone number, no birth date. An account is an OAuth or email login
--    plus a server-drawn 활동명; nothing here identifies a person to other residents.
--  * An account is not a residence. Residency is a separate, expiring row that says only
--    which 선거구 and how it was checked. There is NO address or coordinate column
--    anywhere: the BFF maps the address to a district and throws the input away.
--  * Only the token's SHA-256 is stored. The raw token lives on the device.
--  * Same access model as init: RLS on with no policies, anon/authenticated have no
--    grants and cannot execute the functions. Only the `bff` function (service role)
--    reads or writes, after verifying the user's JWT with GoTrue.
--
-- Future posts table (not created here). Its author column must be
--     author_id uuid references public.profiles (user_id) on delete set null
-- so a deleted account leaves its posts (when the user chose DELETE /me?posts=keep)
-- with a null author, which the app shows as 「탈퇴한 주민」. posts=delete removes them
-- before the profile goes.

create table public.profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  provider text not null check (provider in ('apple', 'kakao', 'google', 'email')),
  -- Only what the provider gave; kept for account recovery and export, never shown.
  email text,
  handle text not null unique check (handle ~ '^[가-힣]{2,5} [1-9][0-9]$'),
  -- Null until the first change after sign-up; the 30-day rule counts from here.
  handle_changed_at timestamptz,
  notify boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.consents (
  user_id uuid not null references public.profiles (user_id) on delete cascade,
  kind text not null check (kind in ('age14', 'terms', 'privacy', 'notify')),
  version text not null,
  granted boolean not null,
  at timestamptz not null default now(),
  primary key (user_id, kind, version)
);

-- 활동명 are drawn by the server; a user can only pick one that was offered to them.
-- Keyed to auth.users because offers precede the profile (the consent screen shows them).
create table public.handle_offers (
  user_id uuid not null references auth.users (id) on delete cascade,
  handle text not null,
  expires_at timestamptz not null,
  primary key (user_id, handle)
);

create table public.residency_verifications (
  user_id uuid primary key references public.profiles (user_id) on delete cascade,
  district_id text not null references public.districts (id) on delete cascade,
  -- How the district was established. Self-declared address today; the column exists so
  -- a stronger method can replace it without a schema change.
  method text not null check (method in ('address_self_declared')),
  token_hash text not null unique check (token_hash ~ '^[0-9a-f]{64}$'),
  verified_at timestamptz not null,
  expires_at timestamptz not null,
  check (expires_at > verified_at)
);

-- Every other foreign key leads its table's primary key, which already indexes it.
create index on public.residency_verifications (district_id);
create index on public.handle_offers (expires_at);

-- ------------------------------------------------------------------ RLS: deny all

do $$
declare t text;
begin
  foreach t in array array['profiles', 'consents', 'handle_offers', 'residency_verifications'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
  end loop;
end $$;

-- ------------------------------------------------------------------ account functions
-- Each raises a bare code as its message (P0001) so the BFF can map it to an API error:
--   consent_required  no profile yet          → 403
--   not_offered       handle was not offered  → 403
--   too_soon          handle changed < 30 d   → 429, hint = next allowed instant (ISO)
-- A taken handle surfaces as unique_violation (23505) → 409.

-- Creates the profile with the chosen 활동명 and records each consent. Calling it again
-- for an existing profile only re-records the consents (a new terms version, a retried
-- request) and leaves the handle alone.
create or replace function public.accept_consent(
  p_user_id uuid, p_provider text, p_email text, p_handle text, p_notify boolean, p_version text
) returns setof public.profiles
language plpgsql set search_path = '' as $$
begin
  if not exists (select 1 from public.profiles p where p.user_id = p_user_id) then
    if not exists (
      select 1 from public.handle_offers o
      where o.user_id = p_user_id and o.handle = p_handle and o.expires_at > now()
    ) then
      raise exception 'not_offered';
    end if;
    insert into public.profiles (user_id, provider, email, handle, notify)
    values (p_user_id, p_provider, p_email, p_handle, p_notify);
    delete from public.handle_offers o where o.user_id = p_user_id;
  else
    update public.profiles p set notify = p_notify where p.user_id = p_user_id;
  end if;

  insert into public.consents (user_id, kind, version, granted, at)
  values (p_user_id, 'age14', p_version, true, now()),
         (p_user_id, 'terms', p_version, true, now()),
         (p_user_id, 'privacy', p_version, true, now()),
         (p_user_id, 'notify', p_version, p_notify, now())
  on conflict (user_id, kind, version) do update set granted = excluded.granted, at = excluded.at;

  return query select * from public.profiles p where p.user_id = p_user_id;
end $$;

-- Changes the 활동명. The first change after sign-up is free; after that, once per 30 days.
create or replace function public.claim_handle(p_user_id uuid, p_handle text)
returns setof public.profiles
language plpgsql set search_path = '' as $$
declare
  changed timestamptz;
begin
  select p.handle_changed_at into changed
  from public.profiles p where p.user_id = p_user_id for update;
  if not found then
    raise exception 'consent_required';
  end if;
  if changed is not null and changed > now() - interval '30 days' then
    raise exception 'too_soon' using hint = to_char(
      (changed + interval '30 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'
    );
  end if;
  if not exists (
    select 1 from public.handle_offers o
    where o.user_id = p_user_id and o.handle = p_handle and o.expires_at > now()
  ) then
    raise exception 'not_offered';
  end if;

  update public.profiles p set handle = p_handle, handle_changed_at = now()
  where p.user_id = p_user_id;
  delete from public.handle_offers o where o.user_id = p_user_id;
  return query select * from public.profiles p where p.user_id = p_user_id;
end $$;

-- Records a verified district, replacing any earlier one. The caller has already mapped
-- the address and discarded it; only the district, method and token hash arrive here.
create or replace function public.issue_residency(
  p_user_id uuid, p_district_id text, p_method text, p_token_hash text,
  p_verified_at timestamptz, p_expires_at timestamptz
) returns setof public.residency_verifications
language plpgsql set search_path = '' as $$
begin
  if not exists (select 1 from public.profiles p where p.user_id = p_user_id) then
    raise exception 'consent_required';
  end if;
  insert into public.residency_verifications
    (user_id, district_id, method, token_hash, verified_at, expires_at)
  values (p_user_id, p_district_id, p_method, p_token_hash, p_verified_at, p_expires_at)
  on conflict (user_id) do update set
    district_id = excluded.district_id,
    method = excluded.method,
    token_hash = excluded.token_hash,
    verified_at = excluded.verified_at,
    expires_at = excluded.expires_at;
  return query select * from public.residency_verifications r where r.user_id = p_user_id;
end $$;

-- A provider login creates an auth.users row before the app can ask the age question.
-- Anyone who never reached a profile within a day (declined, abandoned, or under 14 and
-- the immediate delete failed) is removed. Also drops expired handle offers.
create or replace function public.purge_orphan_auth_users()
returns int language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  delete from auth.users u
  where u.created_at < now() - interval '24 hours'
    and not exists (select 1 from public.profiles p where p.user_id = u.id);
  get diagnostics n = row_count;
  delete from public.handle_offers o where o.expires_at < now();
  return n;
end $$;

do $$
declare f text;
begin
  foreach f in array array[
    'accept_consent(uuid,text,text,text,boolean,text)', 'claim_handle(uuid,text)',
    'issue_residency(uuid,text,text,text,timestamptz,timestamptz)', 'purge_orphan_auth_users()'
  ] loop
    execute format('revoke execute on function public.%s from public, anon, authenticated', f);
  end loop;
end $$;

-- ------------------------------------------------------------------ cron
-- 19:30 UTC = 04:30 KST, after the ingest and purge jobs.
select cron.schedule('purge-orphan-auth-users', '30 19 * * *', $$select public.purge_orphan_auth_users()$$);
