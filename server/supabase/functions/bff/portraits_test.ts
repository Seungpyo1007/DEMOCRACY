import { assert, assertEquals } from "@std/assert";
import { ingestPortraits, type PortraitStorage } from "../ingest-assembly/ingest.ts";
import { MemoryAccountStore } from "./account_store.ts";
import { MemoryCommunityStore } from "./community_store.ts";
import { validateDistrictProfile } from "./contract.ts";
import { createHandler } from "./handler.ts";
import { MemoryStore } from "./store.ts";
import { ANON_KEY, fakeGotrue, SUPABASE_URL } from "../../../testdata/fake_auth.ts";
import { fakeUpstream } from "../../../testdata/fake_upstream.ts";
import { MAPO_B, NOW, runPipeline, toTables } from "../../../testdata/pipeline.ts";

const BASE = `${SUPABASE_URL}/storage/v1/object/public/portraits/`;
const JPEG = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3, 4]);

function images(opts: { type?: string; status?: number } = {}) {
  const requested: string[] = [];
  const fetch = (input: string | URL | Request) => {
    const url = typeof input === "string" ? input : input instanceof URL ? input.href : input.url;
    requested.push(url);
    return Promise.resolve(
      new Response(JPEG, {
        status: opts.status ?? 200,
        headers: { "content-type": opts.type ?? "image/jpeg" },
      }),
    );
  };
  return { fetch, requested };
}

function bucket() {
  const files = new Map<string, Uint8Array>();
  const storage: PortraitStorage = {
    upload(path, bytes) {
      files.set(path, bytes);
      return Promise.resolve();
    },
  };
  return { storage, files };
}

async function profile(tables: ReturnType<typeof toTables>) {
  const accounts = new MemoryAccountStore();
  const h = createHandler({
    store: new MemoryStore(tables, BASE),
    fetch: fakeUpstream().fetch,
    jusoKey: "J",
    vworldKey: "V",
    accounts,
    community: new MemoryCommunityStore(accounts.t, tables),
    auth: fakeGotrue().auth,
    now: () => NOW,
  });
  const res = await h(
    new Request(`${SUPABASE_URL}/functions/v1/bff/districts/${MAPO_B}/profile`, {
      headers: { apikey: ANON_KEY, Authorization: `Bearer ${ANON_KEY}` },
    }),
  );
  return (await res.json()).data;
}

Deno.test("portraits: copied into Storage, by content hash, and only once", async () => {
  const { db } = await runPipeline();
  const up = images();
  const { storage, files } = bucket();
  const deps = { db, fetch: up.fetch, key: "K", now: () => NOW, storage };

  const first = await ingestPortraits(deps);
  assert(first.copied > 0);
  assertEquals(first.failed, 0);
  assert(up.requested.every((u) => u.startsWith("https://www.assembly.go.kr/")));
  const [row] = db.rows("portraits") as { storage_path: string; source_url: string }[];
  assert(/^members\/.+-[0-9a-f]{16}\.jpg$/.test(row.storage_path));
  assert(files.has(row.storage_path));

  // Nothing new upstream: nothing fetched again.
  const again = await ingestPortraits(deps);
  assertEquals([again.candidates, again.copied], [0, 0]);
});

Deno.test("portraits: a non-image answer is skipped and tried again later", async () => {
  const { db } = await runPipeline();
  const { storage, files } = bucket();
  const result = await ingestPortraits({
    db,
    fetch: images({ type: "text/html" }).fetch,
    key: "K",
    storage,
  });
  assertEquals(result.copied, 0);
  assert(result.failed > 0);
  assertEquals(files.size, 0);
  assertEquals(db.rows("portraits").length, 0);
});

Deno.test("portraits: none leave until a licence is recorded, then with credit", async () => {
  const { db } = await runPipeline();
  await ingestPortraits({ db, fetch: images().fetch, key: "K", storage: bucket().storage });

  const before = await profile(toTables(db));
  assertEquals(before.incumbent.portraitUrl, undefined);

  for (const row of db.rows("portraits") as Record<string, unknown>[]) {
    Object.assign(row, {
      license: "kogl-1",
      attribution: "사진: 국회사무처 (공공누리 제1유형)",
      license_checked_at: NOW.toISOString(),
    });
  }
  const after = await profile(toTables(db));
  assertEquals(validateDistrictProfile(after), []);
  assert(after.incumbent.portraitUrl.startsWith(BASE + "members/"));
  assertEquals(after.incumbent.portraitCredit, "사진: 국회사무처 (공공누리 제1유형)");
});
