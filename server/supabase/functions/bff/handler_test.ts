import { assert, assertEquals } from "@std/assert";
import { validateEnvelope } from "./contract.ts";
import { createHandler } from "./handler.ts";
import { resolveSggCode } from "./mapping.ts";
import { emptyTables, MemoryStore } from "./store.ts";
import { signedOut } from "../../../testdata/fake_auth.ts";
import { fakeUpstream } from "../../../testdata/fake_upstream.ts";
import { MAPO_B, NOW, runPipeline, toTables } from "../../../testdata/pipeline.ts";

async function handlerWith(overrides: Record<string, () => Response> = {}, logs: string[] = []) {
  const { db } = await runPipeline();
  return createHandler({
    store: new MemoryStore(toTables(db)),
    fetch: fakeUpstream(overrides).fetch,
    jusoKey: "J",
    kakaoKey: "K",
    now: () => NOW,
    ...signedOut(),
    logError: (m) => logs.push(m),
  });
}

const call = async (h: (r: Request) => Promise<Response>, path: string, init?: RequestInit) => {
  const res = await h(new Request(`https://ref.supabase.co/functions/v1/bff${path}`, init));
  return {
    status: res.status,
    body: res.status === 204 ? null : await res.json(),
    headers: res.headers,
  };
};

Deno.test("error envelope and codes", async () => {
  const h = await handlerWith();
  const cases: [string, number, string][] = [
    ["/districts/nec-00000000/profile", 404, "not_found"],
    ["/districts/fixture-seoul-mapo-b/profile", 400, "bad_request"],
    ["/districts/nec-00000000/pledges", 404, "not_found"],
    ["/nope", 404, "not_found"],
    ["/address/search", 400, "bad_request"],
    ["/address/search?q=a", 400, "bad_request"],
    ["/location/district?lat=abc&lng=127", 400, "bad_request"],
    ["/location/district?lat=10&lng=127", 400, "bad_request"],
  ];
  for (const [path, status, code] of cases) {
    const r = await call(h, path);
    assertEquals([path, r.status, r.body.error.code], [path, status, code]);
    assertEquals(validateEnvelope(r.body, true), []);
    assertEquals(r.headers.get("Cache-Control"), "no-store");
  }
  assertEquals((await call(h, `/districts/${MAPO_B}/profile`, { method: "POST" })).status, 400);
  assertEquals((await call(h, "/x", { method: "OPTIONS" })).status, 204);
});

Deno.test("district without a sourced incumbent is not_found (never a half payload)", async () => {
  const { db } = await runPipeline();
  const t = toTables(db);
  t.members = t.members.map((m) => ({ ...m, source_url: null }));
  const h = createHandler({
    store: new MemoryStore(t),
    fetch: fakeUpstream().fetch,
    jusoKey: "",
    kakaoKey: "",
    now: () => NOW,
    ...signedOut(),
  });
  const r = await call(h, `/districts/${MAPO_B}/profile`);
  assertEquals([r.status, r.body.error.code], [404, "not_found"]);
});

Deno.test("location outside any mapped district → 404 no_match", async () => {
  const h = await handlerWith({
    "dapi.kakao.com": () =>
      Response.json({
        documents: [{ region_type: "H", code: "2611051000", region_3depth_name: "가상동" }],
      }),
  });
  const r = await call(h, "/location/district?lat=35.1&lng=129.03");
  assertEquals([r.status, r.body.error.code], [404, "no_match"]);
});

Deno.test("upstream failure → 502 upstream; the query never reaches logs", async () => {
  const logs: string[] = [];
  const h = await handlerWith({
    "business.juso.go.kr": () => new Response("down", { status: 500 }),
  }, logs);
  const q = "서울 마포구 비밀주소 123";
  const r = await call(h, `/address/search?q=${encodeURIComponent(q)}`);
  assertEquals([r.status, r.body.error.code], [502, "upstream"]);
  assert(logs.length > 0);
  for (const line of logs) {
    assert(!line.includes("비밀주소") && !line.includes(encodeURIComponent("비밀주소")), line);
    assert(!line.includes("confmKey"), line);
  }
  assert(!JSON.stringify(r.body).includes("비밀주소"));
});

Deno.test("resolveSggCode: whole 시군구, exact 행정동, name, bridge, ambiguity", () => {
  const areas = [
    {
      election_sg_id: "20240410",
      sgg_code: "A",
      hdong_code: "1144055500",
      hdong_name: "아현동",
      sigungu_code: "11440",
    },
    {
      election_sg_id: "20240410",
      sgg_code: "B",
      hdong_code: "1144069000",
      hdong_name: "망원1동",
      sigungu_code: "11440",
    },
    {
      election_sg_id: "20240410",
      sgg_code: "B",
      hdong_code: "1144070000",
      hdong_name: "망원2동",
      sigungu_code: "11440",
    },
  ];
  assertEquals(resolveSggCode(areas, "11440", { hdongCode: "1144055500" }), "A");
  assertEquals(resolveSggCode(areas, "11440", { hdongName: "망원제1동" }), "B");
  const bridge = [
    { bjd_code: "1144012300", hdong_code: "1144069000" },
    { bjd_code: "1144012300", hdong_code: "1144070000" },
    { bjd_code: "1144010200", hdong_code: "1144055500" },
    { bjd_code: "1144010200", hdong_code: "1144069000" },
  ];
  assertEquals(resolveSggCode(areas, "11440", { bjdCode: "1144012300" }, bridge), "B");
  assertEquals(resolveSggCode(areas, "11440", { bjdCode: "1144010200" }, bridge), null);
  const whole = [{
    election_sg_id: "20240410",
    sgg_code: "J",
    hdong_code: "11110",
    hdong_name: null,
    sigungu_code: "11110",
  }];
  assertEquals(resolveSggCode(whole, "11110", {}), "J");
  assertEquals(resolveSggCode([], "11110", {}), null);
});

Deno.test("empty database: every district route is a clean 404", async () => {
  const h = createHandler({
    store: new MemoryStore(emptyTables()),
    fetch: fakeUpstream().fetch,
    jusoKey: "",
    kakaoKey: "",
    now: () => NOW,
    ...signedOut(),
  });
  for (const what of ["profile", "history", "pledges"]) {
    const r = await call(h, `/districts/${MAPO_B}/${what}`);
    assertEquals(r.status, 404);
  }
  const s = await call(h, "/address/search?q=마포구");
  assertEquals(s.body.data, { suggestions: [] });
});
