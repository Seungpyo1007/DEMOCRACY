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
                                                 ──user JWT──▶ bff posts ──▶ reviews, community_*
[공직선거법 [별표 1], 출결 file, curated pledges/region] ──scripts/*.ts──▶ SQL ──▶ tables
```

## Layout

| Path                                                       | What                                                                                                                      |
| ---------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| `supabase/migrations/20260924000000_init.sql`              | Schema, RLS, BFF SQL helpers, purge functions, cron schedules                                                             |
| `supabase/migrations/20260926000000_accounts.sql`          | Profiles, consents, 활동명 offers, residency; account SQL functions; orphan-login purge                                   |
| `supabase/migrations/20260927000000_community.sql`         | Reviews, channel messages, bill threads and replies; write functions (residency, rate limit); thread sync                 |
| `supabase/migrations/20260927120000_district_counts.sql`   | Final 개표 per 선거구 per election (`district_counts`)                                                                    |
| `supabase/migrations/20260927130000_pledge_not_judged.sql` | Pledge status `notJudged` (「판정 전」), which may carry no evidence, judgement or bills                                  |
| `supabase/seed.sql`                                        | **Sample** 마포구 갑/을 + 종로구 district mapping, generated from `testdata/`. Not verified against [별표 1].             |
| `supabase/functions/_shared/`                              | API clients, normalizers (one per source), envelope, provenance, PostgREST client                                         |
| `supabase/functions/ingest-assembly/`                      | Members (daily), bills and plenary votes (every 6 h), 21대 bills (`?mode=bills_backfill&age=21`)                          |
| `supabase/functions/ingest-nec/`                           | Election and district codes and candidates (weekly), historical winners (`?mode=backfill`), final counts (`?mode=counts`) |
| `supabase/functions/bff/`                                  | The API. `contract.ts` mirrors the app's Dart parsers. `account.ts`, `residency.ts`: signed-in. `community.ts`: posts.    |
| `scripts/`                                                 | One-off importers that write SQL to stdout; `build_district_*.ts` build the mapping and 선거구 변천 data                  |
| `data/`                                                    | Inputs kept in git: the 22대 district mapping; `pledges_22/`, pilot pledge lists; `region_22/` + lineage, 선거구 변천     |
| `testdata/`                                                | Hand-written API samples and district-mapping samples. See `testdata/README.md`.                                          |

## Develop

```sh
brew install deno
deno task ci      # fmt --check, lint, check, test (offline)
```

## BFF contract (fixed; the app is built against it)

Base URL: `https://<ref>.supabase.co/functions/v1/bff`. Send `apikey: <anon>` and
`Authorization: Bearer <anon>`, or `Bearer <user access token>` once signed in.

A success is `200 {"servedAt": ISO-UTC, "data": {...}}`. An error is non-2xx
`{"servedAt", "error": {"code", "message"}}`. The error codes are `not_found`, `no_match`,
`not_curated`, `bad_request`, `upstream`, `internal`, `unauthorized` (401), `forbidden` (403),
`consent_required` (403), `conflict` (409), `too_soon` (429, with `error.availableAt`),
`residency_required` (403), `content_rejected` (422, with `error.reason`: `hate`, never the matched
text) and `rate_limited` (429).

| Route                              | data                                                                                        |
| ---------------------------------- | ------------------------------------------------------------------------------------------- |
| `GET /districts/{id}/profile`      | DistrictProfile. Cached 300 s.                                                              |
| `GET /districts/{id}/history`      | HistoryRecord. Cached 300 s.                                                                |
| `GET /districts/{id}/pledges`      | PledgeBoard, or `404 not_curated`                                                           |
| `GET /districts/{id}/results`      | RawElectionResults: the 22대 final count. Cached 300 s.                                     |
| `GET /districts/{id}/direction`    | DirectionReport: `trend` only (or `null`); `stances`, `issues` always `null`. Cached 300 s. |
| `GET /address/search?q=`           | `{suggestions:[{address, district:{id, displayName}}]}`. Unmapped addresses are dropped.    |
| `GET /location/district?lat=&lng=` | `{district:{id, displayName}}`, or `404 no_match`                                           |

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
  - A seat with no current member is **vacant** only when the stored Assembly member list was read
    and every 지역구 member in it was placed in a district; the source is that list.
    - profile: `{district, source, incumbent: null, vacant: true, candidates}`.
    - history: `legislator: {vacant: true, source}`; region and elections as usual.
    - direction: every block `null`.
  - With no sourced incumbent and no such certainty (a member the list names matched no district),
    profile is `404 not_found` and history has `legislator: null`: nothing is said about the seat,
    and the place and its elections still show.
  - A region event read from another document than its timeline (the 공직선거법 version that made a
    선거구 change) carries its own `source`.
  - Every response is checked for keyed URLs (`KEY=`, `ServiceKey=`, `confmKey=`) before it is sent.
- **Figures.** Every figure is descriptive:
  - 출석률 = meetings with status 출석 ÷ meetings on record since 2024-05-30.
  - votes = monthly share of the member's recorded plenary votes that are not 불참.
  - 발의 법안 = bills where the member is 대표발의자 (`RST_MONA_CD`).
  - 공약 이행 = fulfilled ÷ judged pledges. A `notJudged` (「판정 전」) pledge counts on neither
    side, and a board with no judged pledge shows no 공약 이행 at all.
  - 개표 share = a candidate's votes ÷ the 선거구's valid votes (유효투표수), to one decimal.
    `historical` is the winner's share per election for the same 선거구 (by name or curated
    lineage); a year that does not match is left out.
  - direction `trend` = the incumbent's 대표발의 bills in the 21대 and in the 22대, each term split
    into fields by the bill's 소관위원회 (`COMMITTEE`) through the fixed table in
    `bff/bill_fields.ts`. Shares are percent of that term's bills that have a committee. Bills not
    yet referred to a committee are left out and counted in `excludedCount`.
    - `{legislatorName, fromTerm:"21대", toTerm:"22대", billCount, fromCount, toCount,
      excludedCount, fields:[{label, from, to}], summary, source}`.
      A term with no counted bills has `from` (or `to`) `null`: no point, not 0%.
    - `summary` is a template over the numbers: which field had the largest share in each term.
    - `trend` is `null` until the 21대 backfill has run (no 21대 rows at all), or when neither term
      has a counted bill.
    - No model is involved. `stances` and `issues` would need one and are not served; the app shows
      them as 준비 중.
  - There are no rankings, scores or labels.
- **Results** (`/results`) is RawElectionResults:
  - `live: false` and `overallCountedShare: 100`; it is a final count.
  - `districts` holds every 22대 district with a sourced count, in NEC's order; the app selects its
    own. A district without one is `404 not_found`.
  - `electionSchedule` is `null`, which tells the app no election is pending. Past results are not
    restricted (docs/ELECTION_LAW.md). While a future election is pending the BFF must instead send
    the authoritative schedule (`pollsClose` with any NEC extension, and its source) and must not
    send that election's counts before `pollsClose`. That server-side block is the legal guarantee;
    the app's gate is defence in depth.
  - `polls` is always `[]`: 제108조제5항 needs a 심의위 registration behind each series, and nothing
    here verifies one yet.

Committee → field (`bff/bill_fields.ts`; exact name first, then a stem, else 기타):

| Field     | Committees                                                                     |
| --------- | ------------------------------------------------------------------------------ |
| 법사·행정 | 국회운영, 법제사법, 행정안전                                                   |
| 경제·산업 | 정무, 기획재정 (재정경제기획), 산업통상자원중소벤처기업 (산업통상중소벤처기업) |
| 과학·방송 | 과학기술정보방송통신                                                           |
| 복지·보건 | 보건복지, 여성가족 (성평등가족)                                                |
| 교육·문화 | 교육, 문화체육관광                                                             |
| 국토·교통 | 국토교통                                                                       |
| 농림·해양 | 농림축산식품해양수산                                                           |
| 환경·노동 | 환경노동 (기후에너지환경노동)                                                  |
| 외교·안보 | 외교통일, 국방, 정보                                                           |
| 기타      | 예산결산특별, 윤리특별, and any committee neither the table nor a stem places  |

Names in parentheses are the 22대 mid-term renames as recorded in the table. They are not yet
checked against a live bill row; the stems (재정, 산업통상, 가족, 노동, …) place them either way.

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
| `GET /me/export`                | `{exportedAt, account, profile, consents, residency, posts:{reviews, messages, threadReplies}}`.    |
| `DELETE /me?posts=keep\|delete` | → `{deleted:true, posts}`. `delete` removes the posts first; `keep` leaves them as 「탈퇴한 주민」. |
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

### Resident posts

Reading needs no account: signed-out reads are cached 15 s; a signed-in read is no-store because it
marks the reader's own posts (`mine`). Writing needs a user token **and** an unexpired residency for
that same district (`403 residency_required`), checked before the body and again inside the SQL
write function.

| Route                           | Body → data                                                                                                                       |
| ------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| `GET /districts/{id}/reviews`   | `{summary:{average, respondents, axes:[{label, score}]}, reviews:[{id, author, score, verifiedResident, body, mine, createdAt}]}` |
| `POST /districts/{id}/reviews`  | `{scores:{소통, 공약이행, 지역발전, 도덕성: 1-5}, body: 10-500 chars, anonymous?}` → the board as above                           |
| `DELETE /reviews/{id}`          | → `{deleted:true}`. Own only (`403 forbidden`).                                                                                   |
| `GET /districts/{id}/community` | `{messages:[{id, author, body, verifiedResident, mine, createdAt}], threads:[{id, title, origin, replies, sourceUrl, openedAt}]}` |
| `POST /districts/{id}/messages` | `{body: 1-300 chars, anonymous?}` → `{message}`                                                                                   |
| `DELETE /messages/{id}`         | → `{deleted:true}`. Own only.                                                                                                     |

- **No reviews yet** is `summary: {average: 0, respondents: 0, axes: []}`; the app shows it as an
  empty board, not a zero rating.
- **Author** is the 활동명, 「익명 주민」 when the post is anonymous, 「탈퇴한 주민」 once the
  account is deleted. `anonymous` defaults to `true` when omitted. `verifiedResident` is stored at
  post time.
- **One review per resident per district.** A second POST replaces the first. The average and axes
  are computed on the server (`bff_review_summary`).
- **Content rules** (`_shared/content_guard.ts`): the server refuses the app's `ContentGuard`
  **hate** list, so editing the app does not bypass it, and the app treats it as a hard stop. The
  app's **claim** list (possible misinformation) stays a client-side warning the author may send
  past: a keyword cannot tell a false claim from a true one or a quote, and refusing it would be the
  app deciding what residents may say about a politician. Both lists are stand-ins for a real
  classifier.
- **Rate limit:** 5 posts a minute per user across reviews, messages and replies (`429`).
- **Threads** are never started by residents. `sync_bill_threads()` (cron `sync-bill-threads`, 15
  minutes after each bills ingest) opens one per current-term bill sponsored (대표발의) by a
  district's current member, linked to the bill's likms page. Replies have a table and a count but
  no route yet; the app does not open threads.
- Post bodies are never logged.

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
   select public.sync_bill_threads();                            -- after bills land; cron repeats it
   ```
   - Check the result of each call with
     `select * from net._http_response order by id desc limit 5;`.
   - Votes backfill 40 bills per call. The hourly `ingest-assembly-votes` job works through the 22대
     backlog.
   - 21대 bills, for the direction view's term comparison, are a by-hand backfill. It runs after
     `mode=members`, keeps only bills led by a sitting member, and fetches 10 pages of 1000 per
     call. Repeat with the `nextPage` from each summary until `done` is `true` (about three calls):
     ```sql
     select public.call_ingest('ingest-assembly', 'mode=bills_backfill&age=21&page=1');
     select public.call_ingest('ingest-assembly', 'mode=bills_backfill&age=21&page=11');
     select public.call_ingest('ingest-assembly', 'mode=bills_backfill&age=21&page=21');
     ```
     The 6-hourly `bills_votes` job stays on the 22대 and never touches these rows. Re-run the
     backfill after a by-election brings in a member who also sat in the 21대.
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
   - `import_curated.ts --kind pledges|region`. The 22대 pilot pledge lists are in
     `data/pledges_22/`, one file per district, taken from each winner's 선거공보 and marked
     `notJudged`:
     `for f in data/pledges_22/*.json; do deno run --allow-read scripts/import_curated.ts --kind pledges "$f"; done > pledges_22.sql`
   - 선거구 변천 (history tab 「지역의 역사」, and past elections of renamed or split 선거구):
     `data/region_22/<districtId>.json` and `data/district_lineage_22.csv`, already built.
     ```sh
     for f in data/region_22/*.json; do deno run --allow-read scripts/import_curated.ts --kind region "$f"; done > region_22.sql
     deno run --allow-read scripts/import_district_lineage.ts data/district_lineage_22.csv > lineage_22.sql
     psql "$SUPABASE_DB_URL" -f region_22.sql -f lineage_22.sql
     ```
     - `scripts/build_district_lineage.ts` compares the 구역표 in force on each election day (20대
       `MST=181619`, 21대 `216091`, 22대 `261101`) on the 행정동 of the later day, with the same
       KIKcd_H / KIKmix as step 6. Events say only what the two tables show: 구역 변동 없음, 이름
       변경, 분할, 통합, 구역 변경 (by whole 구역표 items), 구역 재편 (what a newly named 선거구 is
       made of). Anything the tables do not settle, such as a 행정동 cut later or 봉담읍's 리 in
       2020, gets no event. Each event cites the version whose table made the change (2020:
       `215523`, 2024: `261101`; the versions between change only 가운뎃점 and 시도 names).
     - A lineage row says a 22대 선거구 lay wholly inside one earlier 선거구 of another name; the
       BFF then shows that 선거구's winner for that year. The rest keep matching by name.
     ```sh
     for m in 181619 216091 261101; do
       curl -o law_$m.json "https://www.law.go.kr/DRF/lawService.do?OC=test&target=law&MST=$m&type=JSON"
     done
     deno run --allow-read --allow-write scripts/build_district_lineage.ts \
       --law20 law_181619.json --law21 law_216091.json --law22 law_261101.json \
       --changed21 215523 --changed22 261101 --fetched-at 2026-09-28 \
       --codes KIKcd_H.20260720 --mix KIKmix.20260720 --out data
     ```
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
- Post bodies are never logged. A post stores its author id, never a real name; a deleted account
  leaves `author_id` null (「탈퇴한 주민」) or, with `posts=delete`, no post at all.
- `source_url` columns have a CHECK that rejects keyed URLs.
- Accounts hold no real name, phone number or birth date. `email` is only what the provider gave,
  kept for export and recovery and never shown. The BFF checks each user token with Supabase Auth
  (`GET /auth/v1/user`) and scopes every account query to that user id.
- Attribution: "출처: 열린국회정보" (공공누리 제1유형) and "출처: 중앙선거관리위원회,
  공공데이터포털". The strings are in `_shared/provenance.ts`, in `SOURCES`.
