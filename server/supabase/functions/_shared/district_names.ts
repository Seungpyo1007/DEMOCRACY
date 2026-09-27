// District identity and display names. One place, tested.

/** The election whose 선거구 define district ids (제22대 국회의원선거). */
export const CURRENT_DISTRICT_SG_ID = "20240410";
/** sgTypecode 2 = 국회의원 지역구. */
export const SG_TYPE_ASSEMBLY_CONSTITUENCY = 2;

const SIDO_SHORT: Record<string, string> = {
  "서울특별시": "서울",
  "부산광역시": "부산",
  "대구광역시": "대구",
  "인천광역시": "인천",
  "광주광역시": "광주",
  "대전광역시": "대전",
  "울산광역시": "울산",
  "세종특별자치시": "세종",
  "경기도": "경기",
  "강원도": "강원",
  "강원특별자치도": "강원",
  "충청북도": "충북",
  "충청남도": "충남",
  "전라북도": "전북",
  "전북특별자치도": "전북",
  "전라남도": "전남",
  "경상북도": "경북",
  "경상남도": "경남",
  "제주특별자치도": "제주",
};

/** "서울특별시" → "서울". Unknown names (e.g. a newly created 시도) pass through. */
export function sidoShortName(sdName: string): string {
  const trimmed = sdName.trim();
  return SIDO_SHORT[trimmed] ?? trimmed;
}

/**
 * "마포구을" → "마포구 을", "용인시정" → "용인시 정", "동구군위군을" → "동구군위군 을".
 * Only a trailing 갑/을/병/정/무 directly after 시/군/구 is a split marker.
 */
export function spaceSplitSuffix(sggName: string): string {
  const compact = sggName.replace(/\s+/g, "");
  return compact.replace(/([시군구])([갑을병정무])$/u, "$1 $2");
}

/** "서울특별시" + "마포구을" → "서울 마포구 을". */
export function formatDistrictDisplayName(sdName: string, sggName: string): string {
  return `${sidoShortName(sdName)} ${spaceSplitSuffix(sggName)}`;
}

/**
 * Whitespace-free join key shared by NEC rows ("서울특별시"+"마포구을") and the
 * Assembly's ORIG_NM ("서울 마포구을"): both become "서울마포구을".
 */
export function districtNameKey(sdName: string, sggName: string): string {
  return `${sidoShortName(sdName)}${sggName}`.replace(/\s+/g, "");
}

/**
 * The 22대 광주 선거구, by name. The Assembly now files members from the
 * merged 전남광주통합특별시, while NEC's 22대 선거구 keep 광주광역시 and
 * 전라남도; these are the ones that were in 광주.
 */
const GWANGJU_SGG = /^(동구남구|서구|북구|광산구)[갑을]?$/u;

/**
 * ORIG_NM "서울 마포구을" → "서울마포구을"; "비례대표" → null.
 *
 * Two spellings do not follow "<시도> <선거구>":
 * - 세종 is one token, "세종특별자치시을", while NEC's 선거구 is named
 *   "세종특별자치시을" inside 시도 세종특별자치시 -- so the key keeps it whole.
 * - "전남광주통합특별시 <선거구>" is the merged 시도; it maps back to 광주 or
 *   전남 by the 선거구 name, since the 22대 districts predate the merger.
 */
export function assemblyOrigKey(origNm: string | null | undefined): string | null {
  if (!origNm) return null;
  const trimmed = origNm.trim();
  if (trimmed === "" || trimmed === "비례대표") return null;
  const [first, ...rest] = trimmed.split(/\s+/);
  const sgg = rest.join("");
  if (sgg === "" && first.startsWith("세종특별자치시")) {
    return `${sidoShortName("세종특별자치시")}${first}`;
  }
  if (first === "전남광주통합특별시") {
    return `${GWANGJU_SGG.test(sgg) ? "광주" : "전남"}${sgg}`;
  }
  return `${sidoShortName(first)}${sgg}`;
}

/**
 * NEC's 선거구 code list has no code column (fields: sgId, sgTypecode,
 * sggName, sdName, wiwName, sggJungsu, sOrder). The district code is therefore
 * derived deterministically from what identifies a 선거구 within the 22대
 * election: its 시도 and 선거구 name. FNV-1a 32-bit, 8 lowercase hex digits.
 * sOrder is deliberately not used: it is a display order, not an identity.
 */
export function necSggCode(sdName: string, sggName: string): string {
  const input = `${sdName.trim()}|${sggName.replace(/\s+/g, "")}`;
  let hash = 0x811c9dc5;
  for (const byte of new TextEncoder().encode(input)) {
    hash ^= byte;
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash.toString(16).padStart(8, "0");
}

export function districtIdFor(sggCode: string): string {
  return `nec-${sggCode}`;
}

const DISTRICT_ID = /^nec-[0-9a-z]{1,32}$/;

export function isDistrictId(id: string): boolean {
  return DISTRICT_ID.test(id);
}

/** "망원제1동" and "망원1동" name the same 행정동. */
export function normalizeHdongName(name: string): string {
  return name.replace(/\s+/g, "").replace(/제(\d)/g, "$1");
}
