import { assert, assertEquals, assertRejects } from "@std/assert";
import { MemoryPostgrest } from "../_shared/memory_postgrest.ts";
import {
  DEFAULT_BACKFILL_SG_IDS,
  ingestCandidates,
  ingestCodes,
  ingestWinners,
  runNecIngest,
} from "./ingest.ts";
import { fakeUpstream } from "../../../testdata/fake_upstream.ts";
import { MAPO_B, NOW } from "../../../testdata/pipeline.ts";

const now = () => NOW;
function deps() {
  const db = new MemoryPostgrest();
  const up = fakeUpstream();
  return {
    up,
    d: {
      db,
      fetch: up.fetch,
      serviceKey: "NEC+KEY/==",
      now,
      retry: { retries: 0 },
      minDistricts: 1,
    },
  };
}

Deno.test("codes: elections + 22대 districts with fixed-contract ids", async () => {
  const { d, up } = deps();
  assertEquals(await ingestCodes(d), { elections: 5, districts: 4 });
  const mapo = d.db.rows("districts").find((r) => r.id === MAPO_B)!;
  assertEquals(mapo.display_name, "서울 마포구 을");
  // The decoded key is URL-encoded exactly once.
  assert(up.requests.every((u) => u.includes("ServiceKey=NEC%2BKEY%2F%3D%3D")));
  assert(!JSON.stringify(d.db.rows("raw_nec")).includes("NEC+KEY"));
});

Deno.test("codes: a manual count_status survives re-ingest", async () => {
  const { d } = deps();
  await ingestCodes(d);
  await d.db.update("elections", { sg_id: "eq.20280412", sg_typecode: "eq.2" }, {
    count_status: "counting",
  });
  await ingestCodes(d);
  assertEquals(
    d.db.rows("elections").find((e) => e.sg_id === "20280412" && e.sg_typecode === 2)!.count_status,
    "counting",
  );
});

Deno.test("codes: a short district list is not applied", async () => {
  const { d } = deps();
  await assertRejects(() => ingestCodes({ ...d, minDistricts: 250 }), Error, "not applied");
  assertEquals(d.db.rows("districts").length, 0);
});

Deno.test("backfill: winners for 20·21·22대, single-object responses handled, idempotent", async () => {
  const { d } = deps();
  const r = await ingestWinners(d, DEFAULT_BACKFILL_SG_IDS);
  assertEquals(r.winners, { "20160413": 1, "20200415": 1, "20240410": 2 });
  await ingestWinners(d, DEFAULT_BACKFILL_SG_IDS);
  assertEquals(d.db.rows("election_results").length, 4);
  assertEquals(d.db.rows("elections").map((e) => e.term).sort(), [20, 21, 22]);
  const raw = JSON.stringify(d.db.rows("raw_nec"));
  assert(!raw.includes("birthday") && !raw.includes("addr"));
  await assertRejects(
    () => runNecIngest("backfill", d, new URL("https://x/?sgIds=2024")),
    RangeError,
  );
});

Deno.test("candidates: only for upcoming elections, minimal personal data", async () => {
  const { d } = deps();
  await ingestCodes(d);
  const r = await ingestCandidates(d);
  assertEquals(r.elections, 1); // 20280412 only
  const [c] = d.db.rows("candidates");
  assertEquals([c.kind, c.name, c.status], ["final", "가상 후보 가", "등록"]);
  for (const banned of ["addr", "birthday", "age", "gender", "edu", "job"]) {
    assert(!(banned in c), banned);
  }
});
