# DEMOCRACY server

The backend is a Supabase project: Postgres, Deno Edge Functions and pg_cron. It collects
public-sector data on a schedule and serves it to the app through one API, the `bff` function.
Reading needs no account; the account routes need a Supabase Auth sign-in.

```
[열린국회정보 / 선관위(data.go.kr)] ──pg_cron→pg_net──▶ ingest-assembly / ingest-nec
        ──▶ raw_* (payload minus personal fields) ──▶ normalized tables (source_url, fetched_at)
                                                     ──▶ bff (GET) ──▶ app
[juso.go.kr / V-World] ◀── proxied live by bff (query never logged or stored)
[Supabase Auth: Apple / Kakao / Google / email] ──user JWT──▶ bff /me ──▶ profiles, consents
[공직선거법 [별표 1], 출결 file, curated pledges/region] ──scripts/*.ts──▶ SQL ──▶ tables
```

## Layout

| Path                                                     | What                                                                                                                      |
| -------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| `supabase/migrations/20260924000000_init.sql`            | Schema, RLS, BFF SQL helpers, purge functions, cron schedules                                                             |
| `supabase/migrations/20260926000000_accounts.sql`        | Profiles, consents, 활동명 offers, residency; account SQL functions; orphan-login purge                                   |
| `supabase/migrations/20260927120000_district_counts.sql` | Final 개표 per 선거구 per election (`district_counts`)                                                                    |
| `supabase/seed.sql`                                      | **Sample** 마포구 갑/을 + 종로구 district mapping, generated from `testdata/`. Not verified against [별표 1].             |
| `supabase/functions/_shared/`                            | API clients, normalizers (one per source), envelope, provenance, PostgREST client                                         |
| `supabase/functions/ingest-assembly/`                    | Members (daily), bills and plenary votes (every 6 h)                                                                      |
| `supabase/functions/ingest-nec/`                         | Election and district codes and candidates (weekly), historical winners (`?mode=backfill`), final counts (`?mode=counts`) |
| `supabase/functions/bff/`                                | The API. `contract.ts` mirrors the app's Dart parsers. `account.ts`, `residency.ts`: signed-in.                           |
| `scripts/`                                               | One-off importers that write SQL to stdout; `build_district_areas.ts` builds the mapping CSV                              |
| `data/`                                                  | Generated inputs kept in git: the 22대 district mapping                                                                   |
| `testdata/`                                              | Hand-written API samples and district-mapping samples. See `testdata/README.md`.                                          |

## Develop

```sh
brew install deno
deno task ci      # fmt --check, lint, check, test (offline; 80 tests)
```

## BFF contract (fixed; the app is built against it)

Base URL: `https://<ref>.supabase.co/functions/v1/bff`. Send `apikey: <anon>` and
`Authorization: Bearer <anon>`, or `Bearer <user access token>` once signed in.

A success is `200 {"servedAt": ISO-UTC, "data": {...}}`. An error is non-2xx
`{"servedAt", "error": {"code", "message"}}`. The error codes are `not_found`, `no_match`,
`not_curated`, `bad_request`, `upstream`, `internal`, `unauthorized` (401), `forbidden` (403),
`consent_required` (403), `conflict` (409) and `too_soon` (429, with `error.availableAt`).

| Route                              | data                                                                                     |
| ---------------------------------- | ---------------------------------------------------------------------------------------- |
| `GET /districts/{id}/profile`      | DistrictProfile. Cached 300 s.                                                           |
| `GET /districts/{id}/history`      | HistoryRecord. Cached 300 s.                                                             |
| `GET /districts/{id}/pledges`      | PledgeBoard, or `404 not_curated`                                                        |
| `GET /address/search?q=`           | `{suggestions:[{address, district:{id, displayName}}]}`. Unmapped addresses are dropped. |
| `GET /location/district?lat=&lng=` | `{district:{id, displayName}}`, or `404 no_match`                                        |

- **District ids** have the form `nec-<sggCode>`.
  - NEC's `getCommonSggCodeList` has **no code field**. It returns only sggName, sdName, wiwName,
    sggJungsu and sOrder.
  - So `sggCode` is derived: FNV-1a 32-bit hex of `"<sdName>|<sggName>"` for 22대 (`20240410`, type
    2). For example, 서울 마포구 을 = `nec-24863648` and 서울 마포구 갑 = `nec-313502f4`.
  - The function is `necSggCode()` in `_shared/district_names.ts`.
- **Person ids.** An incumbent is `assembly-<MONA_CD>`. A past winner or candidate is
  `nec-<sgId>-<huboid>`. A past winner who has the incumbent's name in the same district gets the
  incumbent's id, so the app's `firstWinYear` works.
- **What the BFF drops or omits:**
  - Any figure without a presentable `sourceUrl` and `fetchedAt` is dropped.
  - `record.attendance` and `record.votes` are omitted when there is no data. `record.bills` is
    always present with `record`.
  - A district with no sourced incumbent gets `404 not_found`, never a partial payload.
  - Every response is checked for keyed URLs (`KEY=`, `ServiceKey=`, `confmKey=`) before it is sent.
- **Figures.** Every figure is descriptive:
  - 출석률 = meetings with status 출석 ÷ meetings on record since 2024-05-30.
  - votes = monthly share of the member's recorded plenary votes that are not 불참.
  - 발의 법안 = bills where the member is 대표발의자 (`RST_MONA_CD`).
  - 공약 이행 = fulfilled ÷ curated pledges. It appears only when curated pledges exist.
  - There are no rankings, scores or labels.

### Account routes

Account routes need a user access token; the anon key alone is `401 unauthorized`. They are never
cached (`no-store`). "Me" below is `{profile|null, consents, residency|null}`:

- profile:
  `{userId, handle, provider, email, notify, handleChangedAt, handleChangeAvailableAt, createdAt}`
- consents: `[{kind, version, granted, at}]`, kind one of `age14`, `terms`, `privacy`, `notify`

| Route                           | Body → data                                                                                         |
| ------------------------------- | --------------------------------------------------------------------------------------------------- |
| `GET /me`                       | Me. `profile: null` means the consent screen comes next.                                            |
| `GET /me/handle/options`        | `{handles:[5], expiresAt}`. Only these can be picked, for 30 minutes. `429` in the cooldown.        |
| `POST /me/consent`              | `{age14, terms, privacy, notify, handle}` → Me. The first three must be `true` (`400`).             |
| `POST /me/under14`              | → `{deleted:true}`. Deletes the login; nothing is kept. `409` once a profile exists.                |
| `POST /me/handle`               | `{handle}` → Me. Not offered `403`, taken `409`, second change within 30 days `429`.                |
| `PATCH /me`                     | `{notify}` → Me. Recorded as a `notify` consent row.                                                |
| `GET /me/export`                | `{exportedAt, account, profile, consents, residency}`. No token hash; no address exists.            |
| `DELETE /me?posts=keep\|delete` | → `{deleted:true, posts}`. Removes the profile rows, then the auth user.                            |
| `POST /residency/verify`        | `{roadAddress}` or `{lat, lng}` → `{token, districtId, displayName, method, verifiedAt, expiresAt}` |
| `DELETE /residency`             | → `{deleted:true}`                                                                                  |

- **주민 인증** (`/residency/verify`) needs a profile (`403 consent_required`).
  - The server derives the district itself: juso plus the [별표 1] mapping for an address, V-World
    plus the mapping for coordinates. It never accepts a district id from the client. An address
    must equal one juso `roadAddr` (or be juso's only result) and map to exactly one district;
    anything ambiguous or unmapped is `404 no_match`.
  - The token is 32 random bytes (base64url). Only its SHA-256 is stored, with the district, the
    method (`address_self_declared`) and an expiry 180 days out (`RESIDENCY_TTL_DAYS`). Verifying
    again replaces the old row and token.
  - This is a self-declared address, not proof of residence; the app must not call it 실거주 증명.

- **활동명** (handle) is a neutral nature word, a space and two digits (`솔숲 42`), drawn by the
  server from `_shared/handles.ts`. The list excludes surname-like words, party names, party colours
  and place names; users cannot type their own.
- A sign-in that never reaches a profile (declined consent, under 14, abandoned) is deleted after 24
  hours by the `purge-orphan-auth-users` cron job.

## Go live: steps for a person

1. **Get the keys.** None of these exist yet.
   - `ASSEMBLY_API_KEY`: open.assembly.go.kr → 마이페이지 → 인증키 발급.
   - `DATA_GO_KR_KEY`: data.go.kr. Apply for 활용신청 on all four datasets: 15000897 (코드),
     15000864 (당선인), 15000908 (후보자) and 15000900 (투개표). Use the **Decoding** key.
   - `JUSO_API_KEY`: business.juso.go.kr → 도로명주소 검색 API. The key is for the operating domain.
   - `VWORLD_KEY`: vworld.kr → 오픈API → 인증키 발급 (지오코더 API). Coordinates → 행정동 for 「현재
     위치로 찾기」. If the key was issued for a service URL, also set `VWORLD_DOMAIN` to it.
   - `INGEST_SECRET`: generate one with `openssl rand -hex 32`.
   - `SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` are provided to every
     function by the platform. Do not set them.
2. **Set up the project.**
   ```sh
   cd server
   supabase login && supabase link --project-ref <ref>
   supabase db push                                   # migrations: schema, RLS, functions, cron jobs
   supabase secrets set ASSEMBLY_API_KEY=... DATA_GO_KR_KEY=... JUSO_API_KEY=... \
                        VWORLD_KEY=... INGEST_SECRET=...
   supabase functions deploy bff
   supabase functions deploy ingest-assembly --no-verify-jwt
   supabase functions deploy ingest-nec --no-verify-jwt
   ```
   - pg_cron and pg_net must be enabled. The migration runs `create extension`. If the dashboard
     requires it, enable both under Database → Extensions.
   - If the app uses the new `sb_publishable_...` key instead of the legacy anon JWT, deploy `bff`
     with `--no-verify-jwt`. That key is not a JWT.
3. **Set up Supabase Auth** (Dashboard → Authentication).
   - Providers: enable Apple, Kakao (with OpenID Connect on in Kakao Developers) and Google, each
     with its client id and secret; add the iOS/Android client ids so `signInWithIdToken` works.
     Request no profile, phone or birthday scopes.
   - Email: enable OTP sign-in and change the magic-link template to send the 6-digit
     `{{ .Token }}`. Turn on rate limits and CAPTCHA.
   - Leave anonymous sign-ins off. The BFF treats them as signed out anyway.
4. **Add the Vault secrets that cron reads.** Run in the SQL editor:
   ```sql
   select vault.create_secret('https://<ref>.supabase.co', 'project_url');
   select vault.create_secret('<INGEST_SECRET>', 'ingest_secret');
   ```
5. **Seed data, in this order:**
   ```sql
   select public.call_ingest('ingest-nec', 'mode=codes');       -- districts first (check: 254 rows)
   select public.call_ingest('ingest-nec', 'mode=backfill');    -- 20·21·22대 winners
   select public.call_ingest('ingest-nec', 'mode=counts&sgIds=20240410'); -- 22대 final counts
   select public.call_ingest('ingest-nec', 'mode=counts&sgIds=20200415');
   select public.call_ingest('ingest-nec', 'mode=counts&sgIds=20160413');
   select public.call_ingest('ingest-assembly', 'mode=members'); -- check: ~300 rows, summary.unmatchedDistricts
   select public.call_ingest('ingest-assembly', 'mode=bills_votes');
   ```
   - Check the result of each call with
     `select * from net._http_response order by id desc limit 5;`.
   - Votes backfill 40 bills per call. The hourly `ingest-assembly-votes` job works through the 22대
     backlog.
   - Row-count guards refuse to apply fewer than 250 members, 250 districts or counts for fewer than
     250 선거구.
   - `mode=counts` asks each 시도 once and asks by 선거구 name for whatever that leaves out, so one
     election per call keeps it inside the function's time limit. Its summary says how many were
     asked by name (`askedByName`; about 254 means the API wants `sggName`) and which 22대 rows
     found no district (`unmatchedDistricts`, expected empty). It refuses an election whose day has
     not passed: only finished counts are stored.
6. **Load the district mapping.** `data/district_areas_20240410.csv` is the 22대 mapping, already
   built. Rebuild it only when 행안부 publishes new 행정동 codes or for a new election.
   - Inputs, all public:
     - 공직선거법 as in force on the election day, from law.go.kr's API (22대: `MST=261101`, 법률
       제20370호). Its [별표 1] is the 구역표. The current text renames 광주/전남 to
       전남광주통합특별시 but keeps the same 254 구역.
     - 행안부 `jscode<date>(말소코드포함).zip` (KIKcd_H, KIKmix), from the 「행정기관(행정동) 및
       관할구역(법정동) 변경내역」 posts on mois.go.kr.
   - `scripts/build_district_areas.ts` reads the 구역표 against the 행정동 of the election day and
     carries each to today's code: same code, then the same 동 name in the 시군구 it came from, then
     법정동 overlap. It stops on anything it cannot place. When a 시도 or 시군구 is renamed again,
     add it to `SIDO_BEFORE` or `SGG_BEFORE`.
   ```sh
   curl -o law.json 'https://www.law.go.kr/DRF/lawService.do?OC=test&target=law&MST=261101&type=JSON'
   deno run --allow-read scripts/build_district_areas.ts --law law.json \
     --codes KIKcd_H.20260720 --mix KIKmix.20260720 > data/district_areas_20240410.csv
   deno run --allow-read scripts/build_district_areas.ts --emit bridge --mix KIKmix.20260720 > bridge.csv
   deno run --allow-read scripts/import_district_areas.ts data/district_areas_20240410.csv \
     --source-url 'https://www.law.go.kr/LSW/lsInfoP.do?lsiSeq=261101' > areas.sql
   deno run --allow-read scripts/import_bjdong_hdong.ts bridge.csv --source-url <mois post> > bridge.sql
   psql "$SUPABASE_DB_URL" -f areas.sql -f bridge.sql
   ```
   - Rows are upserts. After new 행정동 codes, clear both tables first so retired codes go.
   - Check that every `districts.sgg_code` appears in `district_areas`.
   - Spot-check addresses in split 구 (마포, 강서, 광주 서구, 화성 동탄구, 인천 영종구).
   - Do **not** push `seed.sql` to production. It is an unverified sample.
7. **Run the other imports as needed.** Each prints SQL. Apply it with psql.
   - `import_attendance.ts`: 본회의 출결. This is a file dataset: convert it to the documented CSV
     and pass `--source-url` with the dataset page.
   - `import_historical_results.ts`: older results from CSV.
   - `import_geojson.ts`: 22대 boundaries. Confirm the OhmyNews `2024_22_elec_map` license first;
     `--license` is required.
   - `import_curated.ts --kind pledges|region`: pilot districts only.
8. **Handle election periods.** Switch candidates to hourly:
   `select cron.alter_job((select jobid from cron.job where jobname='ingest-nec-candidates'), schedule := '5 * * * *');`
   - While a count runs, set
     `update elections set count_status='counting' where sg_id=... and sg_typecode=2;`. History then
     shows an `ongoing` row and no figures.
   - Set `count_status` to `'final'` after the count.
   - Preliminary candidates are purged automatically the day after the election
     (`purge-preliminary`).
9. **Complete the open human tasks.**
   - 국회사무처 (02-6788-3853): ask about the license for member photos. Until then the app links
     the Assembly URL and never re-hosts it.
   - Review the OhmyNews GeoJSON license.
   - Legal review before any live-count or nesdc scraping (phase 2).

## Privacy and neutrality

- All tables have RLS on with no policies. anon and authenticated have no grants. Only functions
  using the service role read data.
- Candidates keep only name, party, huboid, status and ≤60-character 경력1/2.
  - Address, birth date, age, gender, education and job are dropped before the raw payload is
    stored.
  - Staff names and birth dates are removed from raw member pages.
- `/address/search`, `/location/district` and `/residency/verify` never log or store the query,
  address or coordinates. Logs carry only the route and the upstream status. The residency table has
  no address or coordinate column.
- `source_url` columns have a CHECK that rejects keyed URLs.
- Accounts hold no real name, phone number or birth date. `email` is only what the provider gave,
  kept for export and recovery and never shown. The BFF checks each user token with Supabase Auth
  (`GET /auth/v1/user`) and scopes every account query to that user id.
- Attribution: "출처: 열린국회정보" (공공누리 제1유형) and "출처: 중앙선거관리위원회,
  공공데이터포털". The strings are in `_shared/provenance.ts`, in `SOURCES`.
