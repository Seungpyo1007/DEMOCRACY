-- Member portraits (의원 사진), kept in our own Storage with their licence.
--
-- Principles
--  * The Assembly opens only what it made or wholly owns under 공공누리 제1유형; whether
--    the official member portraits are among them is not stated anywhere (#31). So every
--    portrait is copied in but starts 'unconfirmed', and the BFF sends a portrait only once
--    a person has recorded a licence for it. Approving is one UPDATE; no app release.
--  * Copied rather than linked: the app does not depend on the Assembly site's paths or
--    on it allowing other apps to load its images, and the copy is what was checked.
--  * The original is kept untouched. Grayscale is applied by the app when drawing, as the
--    design rule says, never baked into the file.
--  * Storage bucket 'portraits' is public read: an approved portrait is a public record
--    image. An unapproved one sits at an unlisted path and is never handed out by the BFF.
--  * Same access model as before for the table: RLS on, no policies, no grants.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('portraits', 'portraits', true, 2097152, array['image/jpeg', 'image/png'])
on conflict (id) do nothing;

create table public.portraits (
  mona_cd text primary key references public.members (mona_cd) on delete cascade,
  storage_path text not null,
  -- Where the copy came from; a new URL means a new photo and a new copy.
  source_url text not null check (public.is_presentable_source_url(source_url)),
  content_type text not null check (content_type in ('image/jpeg', 'image/png')),
  bytes int not null check (bytes > 0),
  sha256 text not null,
  license text not null default 'unconfirmed'
    check (license in ('unconfirmed', 'kogl-1', 'permitted')),
  -- Shown with the photo once approved, e.g. 「사진: 국회사무처 (공공누리 제1유형)」.
  attribution text,
  license_checked_at timestamptz,
  license_note text,
  fetched_at timestamptz not null,
  check (license = 'unconfirmed' or (attribution is not null and license_checked_at is not null))
);

alter table public.portraits enable row level security;
revoke all on public.portraits from anon, authenticated;

-- Copied once a day after the member list (ingest-assembly-members runs at 18:10 UTC).
select cron.schedule('ingest-assembly-portraits', '40 18 * * *',
  $$select public.call_ingest('ingest-assembly', 'mode=portraits')$$);

-- Approving, by hand, once the licence is confirmed (all at once or one member):
--   update public.portraits set license = 'kogl-1',
--     attribution = '사진: 국회사무처 (공공누리 제1유형)',
--     license_checked_at = now(), license_note = '<who confirmed, how>'
--   where license = 'unconfirmed';
