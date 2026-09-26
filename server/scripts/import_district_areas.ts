// 공직선거법 [별표2] → district_areas (행정동 → 선거구), as SQL on stdout.
//
// Input CSV (UTF-8, header row; lines starting with # are comments):
//   election_sg_id,sd_name,sgg_name,sigungu_code,hdong_code,hdong_name
//   20240410,서울특별시,마포구갑,11440,1144055500,아현동
//   20240410,서울특별시,종로구,11110,,
// * sd_name / sgg_name exactly as NEC's getCommonSggCodeList spells them
//   ("서울특별시", "마포구갑") — the district id is derived from these.
// * hdong_code blank = the whole 시군구 belongs to this 선거구 (one row per 시군구;
//   a 선거구 spanning several 시군구 has one row per 시군구).
// * hdong_code = 10-digit 행정동 code (행정기관코드), for 시군구 split across 선거구.
//
// Usage:
//   deno run --allow-read scripts/import_district_areas.ts areas.csv \
//     --source-url "https://www.law.go.kr/법령/공직선거법" --fetched-at 2026-09-24 > areas.sql

import { districtIdFor, necSggCode } from "../supabase/functions/_shared/district_names.ts";
import { parseCsvObjects } from "./lib/csv.ts";
import { parseFlags, requireHttpUrl, type SqlValue, upsertSql } from "./lib/sql.ts";

export interface AreaInput {
  sourceUrl: string;
  fetchedAt: string;
}

export function parseDistrictAreas(
  csv: string,
  opts: AreaInput,
): { rows: Record<string, SqlValue>[]; districts: Map<string, string> } {
  const rows = parseCsvObjects(csv);
  const errors: string[] = [];
  const out: Record<string, SqlValue>[] = [];
  const districts = new Map<string, string>(); // id -> "sd sgg"
  const kindBySigungu = new Map<string, "whole" | "split">();
  const seen = new Set<string>();

  rows.forEach((r, i) => {
    const line = i + 2;
    const {
      election_sg_id: sg,
      sd_name: sd,
      sgg_name: sgg,
      sigungu_code: sig,
      hdong_code: hd,
      hdong_name: hn,
    } = r;
    if (!/^\d{8}$/.test(sg ?? "")) return errors.push(`line ${line}: election_sg_id`);
    if (!sd || !sgg) return errors.push(`line ${line}: sd_name/sgg_name required`);
    if (!/^\d{5}$/.test(sig ?? "")) {
      return errors.push(`line ${line}: sigungu_code must be 5 digits`);
    }
    if (hd && (!/^\d{10}$/.test(hd) || !hd.startsWith(sig))) {
      return errors.push(`line ${line}: hdong_code must be 10 digits starting with sigungu_code`);
    }
    const kind = hd ? "split" : "whole";
    const prev = kindBySigungu.get(`${sg}|${sig}`);
    if (prev && prev !== kind) {
      return errors.push(`line ${line}: 시군구 ${sig} mixes whole-시군구 and per-행정동 rows`);
    }
    kindBySigungu.set(`${sg}|${sig}`, kind);
    const areaCode = hd || sig;
    if (seen.has(`${sg}|${areaCode}`)) {
      return errors.push(`line ${line}: duplicate area ${areaCode}`);
    }
    seen.add(`${sg}|${areaCode}`);

    const code = necSggCode(sd, sgg);
    districts.set(districtIdFor(code), `${sd} ${sgg}`);
    out.push({
      election_sg_id: sg,
      hdong_code: areaCode,
      sgg_code: code,
      hdong_name: hn || null,
      sigungu_code: sig,
      source_url: opts.sourceUrl,
      fetched_at: opts.fetchedAt,
    });
  });
  if (errors.length) throw new Error(`district areas CSV invalid:\n${errors.join("\n")}`);
  return { rows: out, districts };
}

export function districtAreasToSql(
  csv: string,
  opts: AreaInput,
): { sql: string; districts: Map<string, string> } {
  const { rows, districts } = parseDistrictAreas(csv, opts);
  return { sql: upsertSql("district_areas", rows, ["election_sg_id", "hdong_code"]), districts };
}

if (import.meta.main) {
  const { flags, positional } = parseFlags(Deno.args);
  const csv = await Deno.readTextFile(positional[0]);
  const { sql, districts } = districtAreasToSql(csv, {
    sourceUrl: requireHttpUrl(flags["source-url"], "--source-url"),
    fetchedAt: new Date(flags["fetched-at"] ?? Date.now()).toISOString(),
  });
  console.log(`-- district_areas for ${districts.size} districts`);
  for (const [id, name] of districts) console.log(`--   ${id}  ${name}`);
  console.log(sql);
}
