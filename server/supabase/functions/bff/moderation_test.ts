import { assert, assertEquals } from "@std/assert";
import { MemoryAccountStore } from "./account_store.ts";
import { HIDDEN_BODY } from "./community.ts";
import { memoryAuthorTag, MemoryCommunityStore, REPORTS_PER_DAY } from "./community_store.ts";
import { validateCommunity, validateEnvelope, validateReviewBoard } from "./contract.ts";
import { createHandler } from "./handler.ts";
import { MemoryStore } from "./store.ts";
import { ANON_KEY, fakeGotrue, seededBytes, SUPABASE_URL } from "../../../testdata/fake_auth.ts";
import { fakeUpstream } from "../../../testdata/fake_upstream.ts";
import { MAPO_B, NOW, runPipeline, toTables } from "../../../testdata/pipeline.ts";

const DAY = 86_400_000;
const users = ["1", "2", "3", "4", "5"].map((n) => ({
  id: `00000000-0000-4000-8000-00000000000${n}`,
  token: `user-jwt-${n}`,
}));
const [AUTHOR, A, B, C, D] = users;

async function setup() {
  const { db } = await runPipeline();
  let clock = NOW;
  const now = () => clock;
  const gotrue = fakeGotrue(
    Object.fromEntries(users.map((u) => [u.token, { id: u.id, email: null, provider: "email" }])),
  );
  const accounts = new MemoryAccountStore(undefined, now);
  const community = new MemoryCommunityStore(accounts.t, toTables(db), undefined, now);
  const h = createHandler({
    store: new MemoryStore(toTables(db)),
    fetch: fakeUpstream().fetch,
    jusoKey: "J",
    vworldKey: "V",
    accounts,
    community,
    auth: gotrue.auth,
    randomBytes: seededBytes(11),
    now,
  });
  const call = async (
    method: string,
    path: string,
    opts: { as?: { token: string } | null; body?: unknown } = {},
  ) => {
    const who = opts.as === undefined ? A : opts.as;
    const res = await h(
      new Request(`${SUPABASE_URL}/functions/v1/bff${path}`, {
        method,
        headers: { apikey: ANON_KEY, Authorization: `Bearer ${who?.token ?? ANON_KEY}` },
        body: opts.body === undefined ? undefined : JSON.stringify(opts.body),
      }),
    );
    const body = await res.json();
    assertEquals(validateEnvelope(body, !res.ok), [], `${method} ${path}`);
    return { status: res.status, body };
  };
  for (const u of users) {
    const opts = await call("GET", "/me/handle/options", { as: u });
    await call("POST", "/me/consent", {
      as: u,
      body: {
        age14: true,
        terms: true,
        privacy: true,
        notify: false,
        handle: opts.body.data.handles[0],
      },
    });
  }
  accounts.t.residency.push({
    user_id: AUTHOR.id,
    district_id: MAPO_B,
    method: "address_self_declared",
    token_hash: "a".repeat(64),
    verified_at: NOW.toISOString(),
    expires_at: new Date(NOW.getTime() + 180 * DAY).toISOString(),
  });
  const post = async (anonymous = true) => {
    const r = await call("POST", `/districts/${MAPO_B}/messages`, {
      as: AUTHOR,
      body: { body: "오늘 구청 앞 공사 언제 끝나나요", anonymous },
    });
    return r.body.data.message.id as string;
  };
  const report = (
    as: { token: string },
    targetId: string,
    reason = "spam",
    targetType = "message",
  ) => call("POST", "/reports", { as, body: { targetType, targetId, reason } });
  const advance = (ms: number) => {
    clock = new Date(clock.getTime() + ms);
  };
  return { call, post, report, advance, community, now };
}

Deno.test("reports: signed in only, never your own, once each", async () => {
  const { call, post, report } = await setup();
  const id = await post();

  assertEquals((await report(null as unknown as { token: string }, id)).status, 401);
  const own = await report(AUTHOR, id);
  assertEquals([own.status, own.body.error.code], [400, "bad_request"]);

  const first = await report(A, id);
  assertEquals(first.body.data, { reported: true, hidden: false });
  const again = await report(A, id);
  assertEquals([again.status, again.body.error.code], [409, "conflict"]);

  const missing = await report(A, "00000000-0000-4000-9000-999999999999");
  assertEquals(missing.status, 404);
  const bad = await call("POST", "/reports", {
    body: { targetType: "message", targetId: id, reason: "boring" },
  });
  assertEquals(bad.status, 400);
});

Deno.test("reports: three readers hide a post; its body never leaves again", async () => {
  const { call, post, report } = await setup();
  const id = await post();

  assertEquals((await report(A, id, "hate")).body.data.hidden, false);
  assertEquals((await report(B, id, "spam")).body.data.hidden, false);
  assertEquals((await report(C, id, "other")).body.data.hidden, true);

  const read = await call("GET", `/districts/${MAPO_B}/community`, { as: null });
  assertEquals(validateCommunity(read.body.data), []);
  const msg = read.body.data.messages.find((m: { id: string }) => m.id === id);
  assertEquals([msg.body, msg.hidden], [HIDDEN_BODY, true]);
  assert(!JSON.stringify(read.body).includes("공사"));
});

Deno.test("reports: personal information hides at once; false claims alone never do", async () => {
  const { post, report } = await setup();
  const leaked = await post();
  assertEquals((await report(A, leaked, "privacy")).body.data.hidden, true);

  const disputed = await post();
  assertEquals((await report(A, disputed, "false")).body.data.hidden, false);
  assertEquals((await report(B, disputed, "false")).body.data.hidden, false);
});

Deno.test("reports: a hidden review stops counting toward the score", async () => {
  const { call, report } = await setup();
  const posted = await call("POST", `/districts/${MAPO_B}/reviews`, {
    as: AUTHOR,
    body: {
      scores: { "소통": 1, "공약이행": 1, "지역발전": 1, "도덕성": 1 },
      body: "회의록과 예산서를 대조해 보았습니다.",
    },
  });
  const id = posted.body.data.reviews[0].id;
  assertEquals(posted.body.data.summary.respondents, 1);

  await report(A, id, "privacy", "review");
  const board = await call("GET", `/districts/${MAPO_B}/reviews`, { as: null });
  assertEquals(validateReviewBoard(board.body.data), []);
  assertEquals(board.body.data.summary.respondents, 0);
  assertEquals(board.body.data.reviews[0].body, HIDDEN_BODY);
});

Deno.test("reports: at most a day's worth per reader", async () => {
  const { post, report, advance } = await setup();
  for (let i = 0; i < REPORTS_PER_DAY; i++) {
    assertEquals((await report(A, await post(), "other")).status, 200);
    advance(13_000); // under the five-posts-a-minute limit
  }
  const over = await report(A, await post(), "other");
  assertEquals([over.status, over.body.error.code], [429, "rate_limited"]);
  advance(DAY);
  assertEquals((await report(A, await post(), "other")).status, 200);
});

Deno.test("blocks: by post, shown as the author showed, left out of lists", async () => {
  const { call, post, now } = await setup();
  const anon = await post(true);

  const blocked = await call("POST", "/blocks", {
    as: D,
    body: { targetType: "message", targetId: anon },
  });
  const block = blocked.body.data.block;
  assertEquals(block.label, "익명 주민");
  assertEquals(block.authorTag, memoryAuthorTag(AUTHOR.id, now()));
  assert(!JSON.stringify(blocked.body).includes(AUTHOR.id));

  // Gone for the blocker, there for everyone else.
  const mine = await call("GET", `/districts/${MAPO_B}/community`, { as: D });
  assertEquals(mine.body.data.messages.length, 0);
  const theirs = await call("GET", `/districts/${MAPO_B}/community`, { as: B });
  assertEquals(theirs.body.data.messages.length, 1);

  // A named post shows the 활동명; blocking the same author again keeps one block.
  const named = await post(false);
  const again = await call("POST", "/blocks", {
    as: D,
    body: { targetType: "message", targetId: named },
  });
  assertEquals(again.body.data.block.id, block.id);

  const list = await call("GET", "/blocks", { as: D });
  assertEquals(list.body.data.blocks.length, 1);

  // Someone else cannot lift it; the blocker can.
  assertEquals((await call("DELETE", `/blocks/${block.id}`, { as: B })).status, 404);
  assertEquals((await call("DELETE", `/blocks/${block.id}`, { as: D })).body.data, {
    deleted: true,
  });
  const after = await call("GET", `/districts/${MAPO_B}/community`, { as: D });
  assertEquals(after.body.data.messages.length, 2);
});

Deno.test("blocks: the tag changes with the KST date", async () => {
  const { call, post, advance } = await setup();
  const id = await post();
  await call("POST", "/blocks", { as: D, body: { targetType: "message", targetId: id } });
  const today = (await call("GET", "/blocks", { as: D })).body.data.blocks[0].authorTag;
  advance(DAY);
  const tomorrow = (await call("GET", "/blocks", { as: D })).body.data.blocks[0].authorTag;
  assert(today !== tomorrow);
});

Deno.test("blocks: not yourself, signed in only", async () => {
  const { call, post } = await setup();
  const id = await post();
  const own = await call("POST", "/blocks", {
    as: AUTHOR,
    body: { targetType: "message", targetId: id },
  });
  assertEquals(own.status, 400);
  assertEquals((await call("GET", "/blocks", { as: null })).status, 401);
});

Deno.test("staff: only staff list and resolve, and every action is logged", async () => {
  const { call, post, report, community } = await setup();
  const id = await post();
  await report(A, id, "privacy");

  assertEquals((await call("GET", "/staff/reports", { as: B })).status, 403);
  community.t.staff.push(B.id);

  const open = await call("GET", "/staff/reports", { as: B });
  const [row] = open.body.data.reports;
  assertEquals([row.targetId, row.hidden, row.reasons, row.reports], [id, true, ["privacy"], 1]);

  const noReason = await call("POST", `/staff/reports/${row.reportId}/resolve`, {
    as: B,
    body: { action: "keep" },
  });
  assertEquals(noReason.status, 400);

  await call("POST", `/staff/reports/${row.reportId}/resolve`, {
    as: B,
    body: { action: "keep", reason: "주소가 아니라 가게 이름" },
  });
  const shown = await call("GET", `/districts/${MAPO_B}/community`, { as: null });
  assertEquals(shown.body.data.messages[0].hidden, false);
  assertEquals((await call("GET", "/staff/reports", { as: B })).body.data.reports, []);
  assertEquals(community.t.staffActions.map((a) => [a.action, a.staff_id]), [["keep", B.id]]);

  // Deleting: the post goes, the reports stay marked.
  await report(C, id, "hate");
  const [next] = (await call("GET", "/staff/reports", { as: B })).body.data.reports;
  await call("POST", `/staff/reports/${next.reportId}/resolve`, {
    as: B,
    body: { action: "delete", reason: "혐오 표현" },
  });
  const gone = await call("GET", `/districts/${MAPO_B}/community`, { as: null });
  assertEquals(gone.body.data.messages, []);
  assertEquals(community.t.reports.map((r) => r.status), ["kept", "deleted"]);
});
