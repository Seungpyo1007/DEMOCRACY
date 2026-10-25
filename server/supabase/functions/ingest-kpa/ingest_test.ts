import { assertEquals, assertRejects, assertThrows } from "@std/assert";
import { MemoryPostgrest } from "../_shared/memory_postgrest.ts";
import {
  KPA_REPO,
  pickColor,
  publisherFor,
  runKpaIngest,
  sha256Hex,
  toApplyArgs,
} from "./ingest.ts";

type J = Record<string, unknown>;

const TAG = "v2026.10.22.3";
const MAPO_B = "nec-2111302";
const NOW = new Date("2026-10-25T03:00:00Z");
const NEC_PDF = "https://policy.nec.go.kr/policy_pdf/20240410/PDF/mapo-b.pdf";

function dump(): Record<string, J[]> {
  return {
    "parties.json": [
      {
        id: "gungminui-him",
        name: "국민의힘",
        predecessor: null,
        colors: [{
          hex: "#E61E2B",
          from: null,
          source_urls: ["https://www.peoplepowerparty.kr/about/logo"],
          checked_at: "2026-10-07",
        }],
        note: "주조색",
      },
      { id: "saenuridang-2020", name: "새누리당", predecessor: null, colors: [] },
      { id: "saenuridang", name: "새누리당", predecessor: null, colors: [] },
      { id: "jayu-hangukdang", name: "자유한국당", predecessor: "saenuridang", colors: [] },
    ],
    "ruling_periods.json": [
      {
        starts_on: "2022-05-10",
        ends_on: "2025-04-04",
        party_id: "gungminui-him",
        president: "윤석열",
        source_urls: ["https://www.pa.go.kr/"],
      },
      {
        starts_on: "2025-04-04",
        ends_on: "2025-06-04",
        party_id: null,
        president: "한덕수 (대통령 권한대행)",
        acting: true,
        source_urls: ["https://v.daum.net/v/20250404170046206"],
      },
    ],
    "pledges.json": [{
      election_id: "20240410",
      office: `assembly/${MAPO_B}`,
      candidate: { name: "가상", person_id: "ga-sang-1970" },
      pledges: [
        { id: "mapo-b-01", title: "환승 개선", page: 3 },
        { id: "mapo-b-03", title: "도서관 신설", page: null },
      ],
      source_urls: [NEC_PDF],
      checked_at: "2026-09-27",
    }],
    "photos.json": [
      {
        person_id: "ga-sang-1970",
        source_url: "https://www.assembly.go.kr/photo/a.jpg",
        license: "permitted",
        attribution: "국회",
        decision: "운영자 결정",
        checked_at: "2026-10-07",
      },
      {
        person_id: "no-portrait-1980",
        license: "permitted",
        attribution: "국회",
        decision: "운영자 결정",
        checked_at: "2026-10-07",
      },
    ],
    "people.json": [
      { id: "ga-sang-1970", external_ids: { assembly_mona_cd: "FAKE0001" } },
      { id: "no-portrait-1980", external_ids: { assembly_mona_cd: "FAKE0009" } },
    ],
    "offices.json": [],
  };
}

async function fakeRelease(files: Record<string, J[]>, edit?: (m: J) => void) {
  const bodies: Record<string, Uint8Array> = {};
  const entries: Record<string, { records: number; sha256: string }> = {};
  for (const [name, rows] of Object.entries(files)) {
    bodies[name] = new TextEncoder().encode(JSON.stringify(rows));
    entries[name] = { records: rows.length, sha256: await sha256Hex(bodies[name]) };
  }
  const manifest: J = { tag: TAG, schema_version: 1, license: "CC-BY-4.0", files: entries };
  edit?.(manifest);
  bodies["manifest.json"] = new TextEncoder().encode(JSON.stringify(manifest));
  const asset = (name: string) => `https://github.com/${KPA_REPO}/releases/download/${TAG}/${name}`;
  const requests: string[] = [];
  const fetch = (input: string | URL | Request) => {
    const url = String(input);
    requests.push(url);
    if (url === `https://api.github.com/repos/${KPA_REPO}/releases/latest`) {
      const assets = Object.keys(bodies).map((name) => ({
        name,
        browser_download_url: asset(name),
      }));
      return Promise.resolve(Response.json({ tag_name: TAG, assets }));
    }
    const name = Object.keys(bodies).find((n) => asset(n) === url);
    if (!name) return Promise.resolve(new Response("not found", { status: 404 }));
    return Promise.resolve(new Response(bodies[name] as BufferSource));
  };
  return { fetch, requests };
}

/** A stand-in for kpa_apply covering what the tests check: pledges and photos. */
function withKpaApply(db: MemoryPostgrest): MemoryPostgrest {
  db.rpcs.set("kpa_apply", (args, self) => {
    const boards = args.p_boards as J[];
    for (const b of boards) {
      if (!self.rows("districts").some((d) => d.id === b.district_id)) {
        throw new Error(`kpa_unknown_district: ${b.district_id}`);
      }
    }
    const incoming = new Set(boards.flatMap((b) => (b.pledges as J[]).map((p) => p.id)));
    const districts = new Set(boards.map((b) => b.district_id));
    const stale = self.rows("pledges").filter((p) =>
      districts.has(p.district_id) && !incoming.has(p.id)
    );
    const judgedKept = stale.filter((p) => p.status !== "notJudged").map((p) => p.id);
    self.tables.set(
      "pledges",
      self.rows("pledges").filter((p) => !stale.includes(p) || p.status !== "notJudged"),
    );
    for (const b of boards) {
      for (const p of b.pledges as J[]) {
        const fields = {
          title: p.title,
          sort: p.sort,
          page: p.page,
          source_url: b.source_url,
          publisher: b.publisher,
          fetched_at: b.fetched_at,
        };
        const have = self.rows("pledges").find((r) => r.id === p.id);
        if (have) Object.assign(have, fields);
        else {
          self.rows("pledges").push({
            id: p.id,
            district_id: b.district_id,
            status: "notJudged",
            ...fields,
          });
        }
      }
    }
    let photos = 0;
    const photosUnmatched: unknown[] = [];
    for (const ph of args.p_photos as J[]) {
      const row = self.rows("portraits").find((r) => r.mona_cd === ph.mona_cd);
      if (!row) {
        photosUnmatched.push(ph.person_id);
        continue;
      }
      Object.assign(row, {
        license: ph.license,
        attribution: ph.attribution,
        license_checked_at: ph.license_checked_at,
        license_note: ph.license_note,
      });
      photos++;
    }
    self.rows("kpa_imports").push({ tag: args.p_tag, files: args.p_files });
    return { judgedKept, photos, photosUnmatched };
  });
  return db;
}

function setup() {
  const db = withKpaApply(new MemoryPostgrest());
  db.rows("districts").push({ id: MAPO_B });
  db.rows("pledges").push(
    {
      id: "mapo-b-01",
      district_id: MAPO_B,
      title: "옛 제목",
      status: "fulfilled",
      evidence_url: "https://likms.assembly.go.kr/bill/1",
      sort: 5,
    },
    { id: "mapo-b-02", district_id: MAPO_B, title: "빠진 공약", status: "notJudged" },
    { id: "mapo-b-09", district_id: MAPO_B, title: "판정된 빠진 공약", status: "inProgress" },
  );
  db.rows("portraits").push({
    mona_cd: "FAKE0001",
    storage_path: "FAKE0001/abc.jpg",
    sha256: "abc",
    license: "unconfirmed",
  });
  return db;
}

const latest = new URL("http://localhost/ingest-kpa?mode=latest");
const now = () => NOW;

Deno.test("kpa: applies a release, keeping verdicts and portrait files", async () => {
  const db = setup();
  const up = await fakeRelease(dump());
  const summary = await runKpaIngest("latest", { db, fetch: up.fetch, now }, latest) as J;

  assertEquals(summary.tag, TAG);
  assertEquals(summary.judgedKept, ["mapo-b-09"]);
  assertEquals(summary.photosUnmatched, ["no-portrait-1980"]);
  assertEquals(summary.partiesSharingName, [{
    name: "새누리당",
    kpaIds: ["saenuridang", "saenuridang-2020"],
  }]);

  const pledges = new Map(db.rows("pledges").map((p) => [p.id, p]));
  assertEquals([...pledges.keys()].sort(), ["mapo-b-01", "mapo-b-03", "mapo-b-09"]);
  const judged = pledges.get("mapo-b-01")!;
  assertEquals(judged.title, "환승 개선");
  assertEquals(judged.status, "fulfilled");
  assertEquals(judged.evidence_url, "https://likms.assembly.go.kr/bill/1");
  assertEquals([judged.sort, judged.page], [0, 3]);
  assertEquals(judged.publisher, "중앙선거관리위원회");
  assertEquals(judged.fetched_at, "2026-09-27T00:00:00+09:00");
  assertEquals(pledges.get("mapo-b-03")!.status, "notJudged");

  const portrait = db.rows("portraits")[0];
  assertEquals(portrait.license, "permitted");
  assertEquals(portrait.attribution, "국회");
  assertEquals(portrait.license_note, "운영자 결정");
  assertEquals(portrait.storage_path, "FAKE0001/abc.jpg");
  assertEquals(portrait.sha256, "abc");

  // offices.json is ignored, so it is never downloaded.
  assertEquals(up.requests.some((u) => u.endsWith("/offices.json")), false);
  assertEquals(db.rows("kpa_imports").map((r) => r.tag), [TAG]);
});

Deno.test("kpa: an applied tag is skipped unless forced", async () => {
  const db = setup();
  db.rows("kpa_imports").push({ tag: TAG });
  const up = await fakeRelease(dump());
  const summary = await runKpaIngest("latest", { db, fetch: up.fetch, now }, latest);
  assertEquals(summary, { tag: TAG, skipped: "already applied" });
  assertEquals(up.requests.length, 1);
  assertEquals(db.calls.includes("rpc kpa_apply"), false);

  const forced = new URL("http://localhost/ingest-kpa?mode=latest&force=1");
  await runKpaIngest("latest", { db, fetch: up.fetch, now }, forced);
  assertEquals(db.calls.includes("rpc kpa_apply"), true);
});

async function assertRefused(
  edit: (files: Record<string, J[]>, m: J) => void,
  message: string,
  db = setup(),
) {
  const files = dump();
  const up = await fakeRelease(files, (m) => edit(files, m));
  await assertRejects(
    () => runKpaIngest("latest", { db, fetch: up.fetch, now }, latest),
    Error,
    message,
  );
  assertEquals(db.calls.includes("rpc kpa_apply"), false);
  assertEquals(db.rows("pledges").find((p) => p.id === "mapo-b-02")?.title, "빠진 공약");
}

Deno.test("kpa: a sha256 that does not match refuses the release", async () => {
  await assertRefused((_, m) => {
    (m.files as J)["photos.json"] = { records: 2, sha256: "0".repeat(64) };
  }, "photos.json: sha256");
});

Deno.test("kpa: a wrong record count refuses the release", async () => {
  await assertRefused((_, m) => {
    ((m.files as J)["pledges.json"] as J).records = 2;
  }, "pledges.json: 1 records, the manifest says 2");
});

Deno.test("kpa: another schema_version refuses the release", async () => {
  await assertRefused((_, m) => {
    m.schema_version = 2;
  }, "schema_version 2, this function reads 1");
});

Deno.test("kpa: a file missing from the manifest refuses the release", async () => {
  await assertRefused((_, m) => {
    delete (m.files as J)["people.json"];
  }, "people.json: not in the manifest");
});

Deno.test("kpa: an unknown district refuses the release", async () => {
  const db = setup();
  db.tables.set("districts", []);
  const up = await fakeRelease(dump());
  await assertRejects(
    () => runKpaIngest("latest", { db, fetch: up.fetch, now }, latest),
    Error,
    `kpa_unknown_district: ${MAPO_B}`,
  );
  assertEquals(db.rows("kpa_imports"), []);
});

Deno.test("kpa: a bad tag or mode is a 400", async () => {
  const db = setup();
  const up = await fakeRelease(dump());
  await assertRejects(
    () => runKpaIngest("", { db, fetch: up.fetch }, new URL("http://x/?tag=../latest")),
    RangeError,
  );
  await assertRejects(
    () => runKpaIngest("", { db, fetch: up.fetch }, new URL("http://x/")),
    RangeError,
  );
});

Deno.test("pickColor: the entry valid today", () => {
  const colors = [
    { hex: "#000001", from: null },
    { hex: "#000002", from: "2020-02-01" },
    { hex: "#000003", from: "2026-11-01" },
  ];
  assertEquals(pickColor(colors, "2026-10-25")?.hex, "#000002");
  assertEquals(pickColor(colors, "2020-01-31")?.hex, "#000001");
  assertEquals(pickColor(colors, "2026-11-01")?.hex, "#000003");
  assertEquals(pickColor([{ hex: "#000003", from: "2026-11-01" }], "2026-10-25"), null);
  assertEquals(pickColor([], "2026-10-25"), null);
});

Deno.test("publisherFor: from the source domain", () => {
  assertEquals(publisherFor(NEC_PDF), "중앙선거관리위원회");
  assertEquals(publisherFor("https://info.nec.go.kr/x"), "중앙선거관리위원회");
  assertEquals(publisherFor("https://open.assembly.go.kr/portal"), "국회사무처");
  assertEquals(publisherFor("https://www.example.or.kr/a"), "example.or.kr");
  assertEquals(publisherFor("https://notnec.go.kr/a"), "notnec.go.kr");
});

Deno.test("toApplyArgs: parties, periods and the photo join", () => {
  const f = dump();
  const args = toApplyArgs({
    parties: f["parties.json"],
    rulingPeriods: f["ruling_periods.json"],
    pledges: f["pledges.json"],
    photos: f["photos.json"],
    people: [{ id: "ga-sang-1970", external_ids: { assembly_mona_cd: "FAKE0001" } }],
  }, "2026-10-25");

  const ppp = args.parties.find((p) => p.name === "국민의힘")!;
  assertEquals(ppp.color, "#E61E2B");
  assertEquals(ppp.color_source_url, "https://www.peoplepowerparty.kr/about/logo");
  assertEquals(ppp.color_checked_at, "2026-10-07");
  assertEquals(args.parties.filter((p) => p.name === "새누리당").map((p) => p.kpa_id), [
    "saenuridang",
  ]);
  assertEquals(args.parties.find((p) => p.name === "자유한국당")!.predecessor, "새누리당");
  assertEquals(args.rulingPeriods.map((r) => r.party_name), ["국민의힘", null]);
  assertEquals(args.photos.map((p) => p.mona_cd), ["FAKE0001", null]);
});

Deno.test("toApplyArgs: an unknown ruling party refuses", () => {
  const f = dump();
  f["ruling_periods.json"][0].party_id = "no-such-party";
  assertThrows(
    () =>
      toApplyArgs({
        parties: f["parties.json"],
        rulingPeriods: f["ruling_periods.json"],
        pledges: f["pledges.json"],
        photos: [],
        people: [],
      }, "2026-10-25"),
    Error,
    "ruling_periods 2022-05-10: party no-such-party unknown",
  );
});
