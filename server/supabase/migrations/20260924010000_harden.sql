-- Clears the database advisor warnings raised on the first deploy.
--
--  * Pin search_path on the helpers that did not set one. Every body already
--    schema-qualifies its tables, so an empty path changes nothing but closes the
--    search_path hijack the linter flags.
--  * pg_net was created in public. It does not support ALTER EXTENSION ... SET SCHEMA,
--    so it is recreated in `extensions`; its functions stay under `net.*`, which is all
--    call_ingest uses. The drop discards only pending/finished request rows.
--  * Cover the three foreign keys that had no index.
-- RLS-without-policies on every table is intentional (deny all; see init) and stays.

alter function public.is_presentable_source_url(text) set search_path = '';
alter function public.bff_bill_count(text, int) set search_path = '';
alter function public.bff_monthly_vote_participation(text, int) set search_path = '';
alter function public.bff_monthly_attendance(text, int) set search_path = '';
alter function public.bff_attendance_since(text, date) set search_path = '';
alter function public.bills_needing_votes(int, text[], date, int) set search_path = '';

drop extension if exists pg_net;
create extension pg_net with schema extensions;

create index on public.member_district_overrides (district_id);
create index on public.pledges (district_id);
create index on public.region_events (district_id);
