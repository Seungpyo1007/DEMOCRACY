import { assert, assertEquals } from "@std/assert";
import { BILL_FIELDS, COMMITTEE_FIELDS, fieldForCommittee } from "./bill_fields.ts";

// The standing committees both terms opened with. Each must land in the field
// the table documents, by exact name.
const STANDING: [string, string][] = [
  ["국회운영위원회", "법사·행정"],
  ["법제사법위원회", "법사·행정"],
  ["행정안전위원회", "법사·행정"],
  ["정무위원회", "경제·산업"],
  ["기획재정위원회", "경제·산업"],
  ["산업통상자원중소벤처기업위원회", "경제·산업"],
  ["과학기술정보방송통신위원회", "과학·방송"],
  ["보건복지위원회", "복지·보건"],
  ["여성가족위원회", "복지·보건"],
  ["교육위원회", "교육·문화"],
  ["문화체육관광위원회", "교육·문화"],
  ["국토교통위원회", "국토·교통"],
  ["농림축산식품해양수산위원회", "농림·해양"],
  ["환경노동위원회", "환경·노동"],
  ["외교통일위원회", "외교·안보"],
  ["국방위원회", "외교·안보"],
  ["정보위원회", "외교·안보"],
];

Deno.test("bill fields: every standing committee of the 21대 and 22대", () => {
  for (const [committee, field] of STANDING) {
    assertEquals(fieldForCommittee(committee), field, committee);
  }
});

Deno.test("bill fields: a renamed committee stays in its field", () => {
  // In the table…
  assertEquals(fieldForCommittee("기후에너지환경노동위원회"), "환경·노동");
  assertEquals(fieldForCommittee("성평등가족위원회"), "복지·보건");
  assertEquals(fieldForCommittee("재정경제기획위원회"), "경제·산업");
  // …and by stem when a name is not.
  assertEquals(fieldForCommittee("산업통상에너지중소벤처기업위원회"), "경제·산업");
  assertEquals(fieldForCommittee("과학기술정보방송미디어통신위원회"), "과학·방송");
  assertEquals(fieldForCommittee("교육문화위원회"), "교육·문화");
});

Deno.test("bill fields: no committee is no field; an unknown one is 기타", () => {
  assertEquals(fieldForCommittee(null), null);
  assertEquals(fieldForCommittee(""), null);
  assertEquals(fieldForCommittee("  "), null);
  assertEquals(fieldForCommittee("예산결산특별위원회"), "기타");
  assertEquals(fieldForCommittee("인사청문특별위원회"), "기타");
  // Whitespace in the source value does not matter.
  assertEquals(fieldForCommittee(" 국토교통 위원회 "), "국토·교통");
});

Deno.test("bill fields: the table only names fields that exist", () => {
  for (const field of Object.values(COMMITTEE_FIELDS)) {
    assert((BILL_FIELDS as readonly string[]).includes(field), field);
  }
});
