import { assert, assertEquals, assertRejects } from "@std/assert";
import { MemoryPostgrest } from "../_shared/memory_postgrest.ts";
import { ingestHandler } from "../_shared/ingest_common.ts";
import { ingestCodes } from "../ingest-nec/ingest.ts";
import {
  ingestBills,
  ingestBillsBackfill,
  ingestMembers,
  ingestVotes,
  runAssemblyIngest,
} from "./ingest.ts";
import { fakeUpstream } from "../../../testdata/fake_upstream.ts";
import { MAPO_A, MAPO_B, NOW, withRpcs } from "../../../testdata/pipeline.ts";

const now = () => NOW;

async function setup() {
  const db = withRpcs(new MemoryPostgrest());
  const up = fakeUpstream();
  await ingestCodes({
    db,
    fetch: up.fetch,
    serviceKey: "N",
    now,
    retry: { retries: 0 },
    minDistricts: 1,
  });
  return {
    db,
    up,
    deps: { db, fetch: up.fetch, key: "A-KEY", now, retry: { retries: 0 }, minMembers: 1 },
  };
}

Deno.test("members: normalized, mapped to districts, portraits linked, raw redacted", async () => {
  const { db, deps } = await setup();
  const summary = await ingestMembers(deps);
  assertEquals(summary.members, 3);
  const members = db.rows("members");
  const incumbent = members.find((m) => m.mona_cd === "FAKE0001")!;
  assertEquals(incumbent.district_id, MAPO_B);
  assertEquals(members.find((m) => m.mona_cd === "FAKE0003")!.district_id, MAPO_A);
  assertEquals(members.find((m) => m.mona_cd === "FAKE0002")!.district_id, null); // 비례대표
  assert(String(incumbent.photo_url).startsWith("https://www.assembly.go.kr/"));
  assertEquals(summary.unmatchedDistricts, []);

  const raw = JSON.stringify(db.rows("raw_assembly"));
  assert(!raw.includes("BTH_DATE") && !raw.includes("가상 보좌관"));
  assert(!raw.includes("A-KEY"), "raw rows never store the key");
});

Deno.test("members: idempotent, and members who left are retired", async () => {
  const { db, deps } = await setup();
  await db.upsert("members", [{
    mona_cd: "GONE0001",
    name: "이전 의원",
    is_current: true,
    source_url: "https://open.assembly.go.kr/",
    fetched_at: NOW.toISOString(),
  }], "mona_cd");
  await ingestMembers(deps);
  await ingestMembers(deps);
  assertEquals(db.rows("members").length, 4);
  assertEquals(db.rows("members").find((m) => m.mona_cd === "GONE0001")!.is_current, false);
  assertEquals(db.rows("raw_assembly").length, 2); // one page per service, upserted
});

Deno.test("members: a short response is not applied", async () => {
  const { db, deps } = await setup();
  await assertRejects(() => ingestMembers({ ...deps, minMembers: 250 }), Error, "not applied");
  assertEquals(db.rows("members").length, 0);
});

Deno.test("bills then votes: only plenary-decided bills, logged, not refetched", async () => {
  const { db, up, deps } = await setup();
  await ingestBills(deps);
  assertEquals(db.rows("bills").length, 4);
  const first = await ingestVotes(deps);
  assertEquals(first, { billsChecked: 1, votes: 3 });
  assertEquals(db.rows("bill_votes").length, 3);
  assertEquals(db.rows("vote_fetch_log")[0].row_count, 3);
  const before = up.requests.length;
  assertEquals(await ingestVotes(deps), { billsChecked: 0, votes: 0 });
  assertEquals(up.requests.length, before);
});

Deno.test("bills backfill: an earlier term, sitting members' bills only", async () => {
  const { db, up, deps } = await setup();
  await ingestMembers(deps);
  await ingestBills(deps);
  const summary = await ingestBillsBackfill(deps, { age: 21 });
  assertEquals(summary, {
    age: 21,
    pages: [1, 1],
    fetched: 6,
    kept: 5, // GONE0021 no longer sits
    total: 6,
    done: true,
    nextPage: null,
  });
  const bills = db.rows("bills");
  assertEquals(bills.filter((b) => b.age === 22).length, 4, "the current term is untouched");
  assertEquals(
    bills.filter((b) => b.age === 21).map((b) => b.rst_mona_cd).sort(),
    ["FAKE0001", "FAKE0001", "FAKE0001", "FAKE0001", "FAKE0003"],
  );
  assert(up.requests.some((u) => new URL(u).searchParams.get("AGE") === "21"));
  // The unassigned bill is kept as it came; the direction view decides what to do with it.
  assertEquals(bills.find((b) => b.bill_id === "PRC_FAKE2104")!.committee, null);
});

Deno.test("bills backfill: runs in page windows and says where to resume", async () => {
  const { db, deps } = await setup();
  await ingestMembers(deps);
  const pages: number[] = [];
  const row = (i: number) => ({
    BILL_ID: `B${i}`,
    BILL_NAME: `법안 ${i}`,
    AGE: "21",
    RST_MONA_CD: "FAKE0001",
    COMMITTEE: "국토교통위원회",
  });
  const fetch = (input: RequestInfo | URL) => {
    const p = Number(new URL(String(input)).searchParams.get("pIndex"));
    pages.push(p);
    const data = p < 3 ? [row(p * 2 - 1), row(p * 2)] : [row(5)];
    return Promise.resolve(Response.json({
      nzmimeepazxkubdpn: [
        { head: [{ list_total_count: 5 }, { RESULT: { CODE: "INFO-000" } }] },
        { row: data },
      ],
    }));
  };
  const windowed = { ...deps, fetch, pageSize: 2 };
  const first = await ingestBillsBackfill(windowed, { age: 21, pages: 2 });
  assertEquals([first.pages, first.done, first.nextPage], [[1, 2], false, 3]);
  const second = await ingestBillsBackfill(windowed, { age: 21, page: 3, pages: 2 });
  assertEquals([second.pages, second.done, second.nextPage], [[3, 3], true, null]);
  assertEquals(pages, [1, 2, 3]);
  assertEquals(db.rows("bills").length, 5);
});

Deno.test("bills backfill: refuses the current term and needs members first", async () => {
  const { deps } = await setup();
  await assertRejects(() => ingestBillsBackfill(deps, { age: 21 }), Error, "mode=members");
  await ingestMembers(deps);
  await assertRejects(() => ingestBillsBackfill(deps, { age: 22 }), RangeError, "earlier term");
  await assertRejects(
    () => ingestBillsBackfill(deps, { age: 21, page: 0 }),
    RangeError,
    "positive",
  );
});

Deno.test("retries upstream 5xx during ingest", async () => {
  const db = withRpcs(new MemoryPostgrest());
  let failures = 0;
  const up = fakeUpstream({
    "nzmimeepazxkubdpn": () => {
      if (failures++ < 2) return new Response("busy", { status: 503 });
      return new Response(
        Deno.readTextFileSync(new URL("../../../testdata/assembly_bills.json", import.meta.url)),
      );
    },
  });
  const r = await ingestBills({
    db,
    fetch: up.fetch,
    key: "K",
    now,
    retry: { retries: 3, sleep: () => Promise.resolve() },
  });
  assertEquals(r.bills, 4);
  assertEquals(failures, 3);
});

Deno.test("ingest handler: secret required, mode validated", async () => {
  const { deps } = await setup();
  const handler = ingestHandler("s3cret", (mode) => runAssemblyIngest(mode, deps));
  const post = (headers: Record<string, string>, q = "mode=bills") =>
    handler(
      new Request(`https://x.supabase.co/functions/v1/ingest-assembly?${q}`, {
        method: "POST",
        headers,
      }),
    );
  assertEquals((await post({})).status, 401);
  assertEquals((await post({ "x-ingest-secret": "wrong!" })).status, 401);
  assertEquals((await handler(new Request("https://x/ingest-assembly?mode=bills"))).status, 405);
  assertEquals((await post({ "x-ingest-secret": "s3cret" }, "mode=nope")).status, 400);
  const ok = await post({ "x-ingest-secret": "s3cret" });
  assertEquals(ok.status, 200);
  assertEquals((await ok.json()).summary, { bills: 4 });
  // The backfill reads its term from the query; a missing or malformed one is a 400.
  const backfill = ingestHandler(
    "s3cret",
    (mode, url) => runAssemblyIngest(mode, deps, url.searchParams),
  );
  const call = (q: string) =>
    backfill(
      new Request(`https://x.supabase.co/functions/v1/ingest-assembly?${q}`, {
        method: "POST",
        headers: { "x-ingest-secret": "s3cret" },
      }),
    );
  assertEquals((await call("mode=bills_backfill")).status, 400);
  assertEquals((await call("mode=bills_backfill&age=2x")).status, 400);
  await ingestMembers(deps);
  const done = await call("mode=bills_backfill&age=21");
  assertEquals(done.status, 200);
  assertEquals((await done.json()).summary.kept, 5);
  // An unset secret locks the function rather than opening it.
  const open = ingestHandler("", () => Promise.resolve({}));
  assertEquals(
    (await open(
      new Request("https://x/?mode=bills", { method: "POST", headers: { "x-ingest-secret": "" } }),
    )).status,
    401,
  );
});
