# testdata

Offline inputs for `deno task test`. No test touches the network.

## API response samples (`assembly_*.json`, `nec_*.json`, `juso_search.json`, `vworld_address.json`)

**Hand-written.** No API keys existed when these were made. All people, parties, bills and addresses
are fictional ("가상 의원", "가나당", `FAKE0001`).

How far each shape is verified:

| Source                                                                                      | Field names                                                                                                                                                                                                                     | Envelope                                                                                                                                                           |
| ------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 열린국회정보 (`nwvrqwxyaytdsfvhu`, `ALLNAMEMBER`, `nzmimeepazxkubdpn`, `nojepdqqaweusdfbi`) | Checked against live keyless calls on 2026-09-24. Keyless calls return real data capped at 5 rows.                                                                                                                              | Checked, including `INFO-200` and `ERROR-300`.                                                                                                                     |
| 선관위 on data.go.kr (코드, 당선인, 후보자)                                                 | Taken from the NEC open-data portal docs (data.nec.go.kr) and the data.go.kr dataset pages. **Not yet checked against a keyed call.**                                                                                           | `resultCode` values `INFO-00` and `INFO-03`, and the single-object `item`, are from memory of these APIs. The XML gateway error is the standard data.go.kr format. |
| juso 검색 API                                                                               | `roadAddr`, `admCd`, `siNm`, `sggNm`, `emdNm` are documented. `hemdNm` (with `addInfoYn=Y`) checked live 2026-09-27: the whole name ("서울특별시 마포구 서교동"), several 행정동 joined by "," for a building in more than one. | `results.common.errorCode`                                                                                                                                         |
| V-World 지오코더 2.0 `getAddress`                                                           | From the vworld.kr reverse-geocoding reference: `response.status`, `result[].structure.level4AC` (행정동 code, road entries only), `level4LC` (법정동 code). **Not yet checked against a keyed call.**                          | `status` "OK" / "NOT_FOUND" / "ERROR" with `error.code`                                                                                                            |

Field mapping lives in one normalizer per source
(`supabase/functions/_shared/normalize_assembly.ts`, `normalize_nec.ts`, `geo.ts`). If a live call
differs, fix it there, then update the sample here.

## District mapping samples

- `district_areas_sample.csv`: **SAMPLE, NOT VERIFIED AGAINST 공직선거법 [별표 1].**
  - 마포구 을 (22대) = 서강·서교·합정·망원1·망원2·연남·성산1·성산2·상암. The source is the
    ko.wikipedia article "마포구 을".
  - 마포구 갑 = the other 7 행정동.
  - The 행정동 codes come from `vuski/admdongkor` ver20250101 (`adm_cd2`).
  - 종로구 is included as a whole-시군구 선거구.
- `byeolpyo1_sample.txt`, `kikcd_h_sample.cp949`, `kikmix_sample.cp949`: inputs for
  `scripts/build_district_areas.ts`, in the real layouts (law.go.kr box table; 행안부 fixed-width
  CP949). The content is cut down: 마포 갑/을 with a 행정동 born after the election, 광주 서구
  re-coded under 전남광주통합특별시, and a 출장소.
- `bjdong_hdong_sample.csv`: 마포구 법정동 → 행정동.
  - Which 법정동 each 행정동 covers comes from mapo.go.kr's 행정동별 관할 법정동 일람표.
  - The 법정동 codes come from the 법정동코드 전체자료 list.
  - It includes real cross-district straddles: 노고산동 (대흥동/갑 and 서교동/을) and 신정동
    (신수동/갑 and 서강동/을).
- `attendance_sample.csv`: fictional attendance for `FAKE0001`.

`supabase/seed.sql` is generated from these files, so it carries the same caveat.

## Helpers

- `fake_upstream.ts` serves these files as a fake `fetch` and records every requested URL.
- `pipeline.ts` runs the real ingest functions and importers into an in-memory DB. The BFF contract
  tests read from that DB.
