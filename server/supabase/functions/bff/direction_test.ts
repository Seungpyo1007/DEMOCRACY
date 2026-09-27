import { assertEquals } from "@std/assert";
import { fieldTrend, tallyTerm, trendSummary } from "./direction.ts";

const bills = (...committees: (string | null)[]) =>
  committees.map((committee) => ({ committee, fetched_at: "2026-09-24T03:00:00Z" }));
const source = {
  sourceUrl: "https://open.assembly.go.kr/portal/data/service/selectAPIServicePage.do/x",
  fetchedAt: "2026-09-24T03:00:00.000Z",
};

Deno.test("direction summary: the same field leads both terms", () => {
  const from = tallyTerm(bills("국토교통위원회", "국토교통위원회", "보건복지위원회"));
  const to = tallyTerm(bills("국토교통위원회"));
  assertEquals(
    trendSummary(from, to, "21대", "22대"),
    "21대와 22대 모두 국토·교통 분야 법안 비중이 가장 큽니다(21대 67%, 22대 100%).",
  );
});

Deno.test("direction summary: a tie names every leading field, in table order", () => {
  const from = tallyTerm(bills("환경노동위원회", "법제사법위원회"));
  const to = tallyTerm(bills("국방위원회"));
  assertEquals(
    trendSummary(from, to, "21대", "22대"),
    "21대에는 법사·행정, 환경·노동 분야 법안 비중이 가장 컸고(50%), " +
      "22대에는 외교·안보 분야 비중이 가장 큽니다(100%).",
  );
});

Deno.test("direction trend: unassigned bills are left out and counted apart", () => {
  const trend = fieldTrend(
    "가상 의원",
    tallyTerm(bills(null, null)),
    tallyTerm(bills("교육위원회", null, "문화체육관광위원회", "정무위원회")),
    source,
  )!;
  assertEquals([trend.billCount, trend.fromCount, trend.toCount, trend.excludedCount], [
    3,
    0,
    3,
    3,
  ]);
  assertEquals(trend.fields, [
    { label: "경제·산업", from: null, to: 33.3 },
    { label: "교육·문화", from: null, to: 66.7 },
  ]);
  assertEquals(
    trend.summary,
    "22대에는 교육·문화 분야 법안 비중이 가장 큽니다(67%). 21대에는 집계된 대표발의 법안이 없습니다.",
  );
});

Deno.test("direction trend: nothing to split is no trend", () => {
  assertEquals(fieldTrend("가상 의원", tallyTerm([]), tallyTerm(bills(null)), source), null);
});
