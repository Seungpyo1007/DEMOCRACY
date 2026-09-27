// 소관위원회 → policy field, for the direction view's term comparison.
//
// A bill's field is the standing committee it was referred to (the
// Assembly's own COMMITTEE value), read through a fixed table. Nothing reads
// the bill's title or text, and nothing here is a model: the same committee
// always lands in the same field, and the table below is the whole rule.
//
// Fields are coarse on purpose. Several committees share one field where a
// reader would not tell them apart (정무 and 기획재정 are both 경제·산업), and
// the list is short enough to draw as one slope chart.
//
// Bills with no committee yet (접수 only, not referred) are not assigned a
// field; the direction builder leaves them out and says how many it left out.

export const BILL_FIELDS = [
  "법사·행정",
  "경제·산업",
  "과학·방송",
  "복지·보건",
  "교육·문화",
  "국토·교통",
  "농림·해양",
  "환경·노동",
  "외교·안보",
  "기타",
] as const;

export type BillField = typeof BILL_FIELDS[number];

/**
 * Standing and special committees of the 21대 and the 22대, by exact name.
 *
 * The 21대 and 22대 opened with the same standing committees. The 2025
 * reorganisation of ministries renamed some 22대 committees mid-term; the
 * names recorded here for those are from the amended 국회법 as understood when
 * this was written and have not been checked against a live bill row, which
 * is why [KEYWORDS] also catches them by stem.
 */
export const COMMITTEE_FIELDS: Readonly<Record<string, BillField>> = {
  // 법사·행정: the Assembly itself, the courts and prosecution, government administration.
  "국회운영위원회": "법사·행정",
  "법제사법위원회": "법사·행정",
  "행정안전위원회": "법사·행정",
  // 경제·산업: finance, the budget ministry, trade, industry and small business.
  "정무위원회": "경제·산업",
  "기획재정위원회": "경제·산업",
  "재정경제기획위원회": "경제·산업", // 22대, after 기획재정부 was split
  "산업통상자원중소벤처기업위원회": "경제·산업",
  "산업통상중소벤처기업위원회": "경제·산업", // 22대, after energy left 산업통상자원부
  // 과학·방송: science, ICT and broadcasting.
  "과학기술정보방송통신위원회": "과학·방송",
  // 복지·보건: health, welfare, family.
  "보건복지위원회": "복지·보건",
  "여성가족위원회": "복지·보건",
  "성평등가족위원회": "복지·보건", // 22대, after 여성가족부 was renamed
  // 교육·문화
  "교육위원회": "교육·문화",
  "문화체육관광위원회": "교육·문화",
  // 국토·교통
  "국토교통위원회": "국토·교통",
  // 농림·해양
  "농림축산식품해양수산위원회": "농림·해양",
  // 환경·노동
  "환경노동위원회": "환경·노동",
  "기후에너지환경노동위원회": "환경·노동", // 22대, after 기후에너지환경부 was created
  // 외교·안보
  "외교통일위원회": "외교·안보",
  "국방위원회": "외교·안보",
  "정보위원회": "외교·안보",
  // 기타: special committees a bill is sometimes referred to.
  "예산결산특별위원회": "기타",
  "윤리특별위원회": "기타",
};

/**
 * Stems for a committee name the table does not list, checked in order: a
 * committee renamed again keeps the words its remit is named by. 정보 is not a
 * stem, because 과학기술정보방송통신 contains it; 정보위원회 is matched only
 * by its exact name.
 */
const KEYWORDS: readonly [string, BillField][] = [
  ["법제사법", "법사·행정"],
  ["국회운영", "법사·행정"],
  ["행정안전", "법사·행정"],
  ["과학기술", "과학·방송"],
  ["방송", "과학·방송"],
  ["정무", "경제·산업"],
  ["재정", "경제·산업"],
  ["산업통상", "경제·산업"],
  ["중소벤처", "경제·산업"],
  ["보건복지", "복지·보건"],
  ["가족", "복지·보건"],
  ["교육", "교육·문화"],
  ["문화체육", "교육·문화"],
  ["국토교통", "국토·교통"],
  ["농림", "농림·해양"],
  ["해양수산", "농림·해양"],
  ["노동", "환경·노동"],
  ["환경", "환경·노동"],
  ["외교", "외교·안보"],
  ["통일", "외교·안보"],
  ["국방", "외교·안보"],
];

/**
 * The field a bill's committee belongs to, or null for a bill that has no
 * committee yet. A named committee the table and stems do not know is 기타,
 * never dropped: it is still one of the member's bills.
 */
export function fieldForCommittee(committee: string | null | undefined): BillField | null {
  const name = (committee ?? "").replace(/\s+/g, "");
  if (name === "") return null;
  const exact = COMMITTEE_FIELDS[name];
  if (exact) return exact;
  for (const [stem, field] of KEYWORDS) {
    if (name.includes(stem)) return field;
  }
  return "기타";
}
