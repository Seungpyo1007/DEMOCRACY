import { assert, assertEquals, assertInstanceOf } from "@std/assert";
import { inspectContent } from "../_shared/content_guard.ts";
import { ApiError } from "../_shared/envelope.ts";
import { MemoryPostgrest } from "../_shared/memory_postgrest.ts";
import { MemoryAccountStore, raised } from "./account_store.ts";
import { ANONYMOUS_AUTHOR, communityError, DELETED_AUTHOR } from "./community.ts";
import { MemoryCommunityStore, PostgrestCommunityStore } from "./community_store.ts";
import { validateCommunity, validateEnvelope, validateReviewBoard } from "./contract.ts";
import { createHandler } from "./handler.ts";
import { MemoryStore } from "./store.ts";
import { ANON_KEY, fakeGotrue, seededBytes, SUPABASE_URL } from "../../../testdata/fake_auth.ts";
import { fakeUpstream } from "../../../testdata/fake_upstream.ts";
import { MAPO_A, MAPO_B, NOW, runPipeline, toTables } from "../../../testdata/pipeline.ts";

const USER = "00000000-0000-4000-8000-000000000001";
const OTHER = "00000000-0000-4000-8000-000000000002";
const TOKEN = "user-jwt-1";
const OTHER_TOKEN = "user-jwt-2";
const DAY = 86_400_000;

const GOOD_REVIEW = {
  scores: { "소통": 4, "공약이행": 3, "지역발전": 5, "도덕성": 4 },
  body: "회의록과 예산서를 대조해 보았습니다.",
};

async function setup() {
  const { db } = await runPipeline();
  let clock = NOW;
  const now = () => clock;
  const gotrue = fakeGotrue({
    [TOKEN]: { id: USER, email: "resident@example.com", provider: "kakao" },
    [OTHER_TOKEN]: { id: OTHER, email: null, provider: "apple" },
  });
  const accounts = new MemoryAccountStore(undefined, now);
  const tables = toTables(db);
  const community = new MemoryCommunityStore(accounts.t, tables, undefined, now);
  const logs: string[] = [];
  const h = createHandler({
    store: new MemoryStore(tables),
    fetch: fakeUpstream().fetch,
    jusoKey: "J",
    vworldKey: "V",
    accounts,
    community,
    auth: gotrue.auth,
    randomBytes: seededBytes(7),
    now,
    logError: (m) => logs.push(m),
  });
  const call = async (
    method: string,
    path: string,
    opts: { token?: string | null; body?: unknown } = {},
  ) => {
    const token = opts.token === undefined ? TOKEN : opts.token;
    const headers: Record<string, string> = { apikey: ANON_KEY };
    headers.Authorization = `Bearer ${token ?? ANON_KEY}`;
    const res = await h(
      new Request(`${SUPABASE_URL}/functions/v1/bff${path}`, {
        method,
        headers,
        body: opts.body === undefined ? undefined : JSON.stringify(opts.body),
      }),
    );
    const body = await res.json();
    assertEquals(validateEnvelope(body, !res.ok), [], `${method} ${path}`);
    return { status: res.status, body, cache: res.headers.get("Cache-Control") };
  };
  /** Signs up with the first offered 활동명; returns it. */
  const signUp = async (token = TOKEN) => {
    const opts = await call("GET", "/me/handle/options", { token });
    const handle = opts.body.data.handles[0];
    await call("POST", "/me/consent", {
      token,
      body: { age14: true, terms: true, privacy: true, notify: false, handle },
    });
    return handle as string;
  };
  const reside = (userId: string, districtId = MAPO_B, days = 180) => {
    accounts.t.residency = accounts.t.residency.filter((r) => r.user_id !== userId);
    accounts.t.residency.push({
      user_id: userId,
      district_id: districtId,
      method: "address_self_declared",
      token_hash: (userId === USER ? "a" : "b").repeat(64),
      verified_at: clock.toISOString(),
      expires_at: new Date(clock.getTime() + days * DAY).toISOString(),
    });
  };
  const advance = (ms: number) => {
    clock = new Date(clock.getTime() + ms);
  };
  return { call, signUp, reside, advance, accounts, community, gotrue, logs };
}

Deno.test("reviews: an empty board is a valid, cacheable answer", async () => {
  const { call } = await setup();
  const r = await call("GET", `/districts/${MAPO_B}/reviews`, { token: null });
  assertEquals(r.status, 200);
  assertEquals(r.cache, "public, max-age=15");
  assertEquals(validateReviewBoard(r.body.data), []);
  assertEquals(r.body.data, { summary: { average: 0, respondents: 0, axes: [] }, reviews: [] });

  assertEquals((await call("GET", "/districts/nec-00000000/reviews")).body.error.code, "not_found");
  assertEquals((await call("GET", "/districts/fixture-x/reviews")).status, 400);
  assertEquals((await call("PUT", `/districts/${MAPO_B}/reviews`)).status, 400);
});

Deno.test("writing: 401 signed out, then residency_required until verified here", async () => {
  const { call, signUp, reside, advance } = await setup();
  for (
    const [path, body] of [
      [`/districts/${MAPO_B}/reviews`, GOOD_REVIEW],
      [`/districts/${MAPO_B}/messages`, { body: "안녕하세요" }],
    ] as const
  ) {
    for (const token of [null, "expired-or-forged"]) {
      const r = await call("POST", path, { token, body });
      assertEquals([path, r.status, r.body.error.code], [path, 401, "unauthorized"]);
    }
    // Signed in, no profile / no residency: the same clear 403.
    const bare = await call("POST", path, { body });
    assertEquals([bare.status, bare.body.error.code], [403, "residency_required"]);
  }

  await signUp();
  const none = await call("POST", `/districts/${MAPO_B}/reviews`, { body: GOOD_REVIEW });
  assertEquals([none.status, none.body.error.code], [403, "residency_required"]);

  reside(USER, MAPO_A); // a resident of the neighbouring district
  const elsewhere = await call("POST", `/districts/${MAPO_B}/reviews`, { body: GOOD_REVIEW });
  assertEquals([elsewhere.status, elsewhere.body.error.code], [403, "residency_required"]);

  reside(USER, MAPO_B, 1);
  advance(2 * DAY); // expired
  const expired = await call("POST", `/districts/${MAPO_B}/messages`, { body: { body: "안녕" } });
  assertEquals([expired.status, expired.body.error.code], [403, "residency_required"]);

  reside(USER, MAPO_B);
  const ok = await call("POST", `/districts/${MAPO_B}/reviews`, { body: GOOD_REVIEW });
  assertEquals(ok.status, 200);
  assertEquals(ok.cache, "no-store");
});

Deno.test("reviews: summary computed on the server; anonymous by default; one per user", async () => {
  const { call, signUp, reside } = await setup();
  const mine = await signUp();
  const theirs = await signUp(OTHER_TOKEN);
  reside(USER);
  reside(OTHER);

  const first = await call("POST", `/districts/${MAPO_B}/reviews`, { body: GOOD_REVIEW });
  assertEquals(validateReviewBoard(first.body.data), []);
  assertEquals(first.body.data.reviews[0].author, "익명 주민");
  assertEquals(first.body.data.reviews[0].verifiedResident, true);
  assertEquals(first.body.data.reviews[0].mine, true);

  await call("POST", `/districts/${MAPO_B}/reviews`, {
    token: OTHER_TOKEN,
    body: {
      scores: { "소통": 2, "공약이행": 2, "지역발전": 2, "도덕성": 3 },
      body: "설명회 일정이 공지되지 않았습니다.",
      anonymous: false,
    },
  });

  const read = await call("GET", `/districts/${MAPO_B}/reviews`, { token: null });
  const board = read.body.data;
  assertEquals(validateReviewBoard(board), []);
  assertEquals(board.summary.respondents, 2);
  // (4+3+5+4)/4 = 4, (2+2+2+3)/4 = 2.25 → 3.13 (rounded to two places, like the SQL).
  assertEquals(board.summary.average, 3.13);
  assertEquals(board.summary.axes, [
    { label: "소통", score: 3 },
    { label: "공약이행", score: 2.5 },
    { label: "지역발전", score: 3.5 },
    { label: "도덕성", score: 3.5 },
  ]);
  assertEquals(
    board.reviews.map((r: { author: string }) => r.author).sort(),
    [theirs, "익명 주민"].sort(),
  );
  assert(!board.reviews.some((r: { mine: boolean }) => r.mine), "signed out: nothing is mine");
  assert(!JSON.stringify(board).includes(mine), "an anonymous author's handle never leaves");
  assert(!JSON.stringify(board).includes(USER) && !JSON.stringify(board).includes(OTHER));

  // A second review replaces the first.
  const again = await call("POST", `/districts/${MAPO_B}/reviews`, {
    body: { ...GOOD_REVIEW, scores: { "소통": 1, "공약이행": 1, "지역발전": 1, "도덕성": 1 } },
  });
  assertEquals(again.body.data.summary.respondents, 2);
  assertEquals(again.body.data.reviews.filter((r: { mine: boolean }) => r.mine).length, 1);
});

Deno.test("writing: malformed bodies are 400; hate terms are 422 without the text", async () => {
  const { call, signUp, reside, logs } = await setup();
  await signUp();
  reside(USER);
  const path = `/districts/${MAPO_B}/reviews`;
  for (
    const body of [
      { ...GOOD_REVIEW, scores: { ...GOOD_REVIEW.scores, "소통": 6 } },
      { ...GOOD_REVIEW, scores: { "소통": 4 } },
      { ...GOOD_REVIEW, scores: { ...GOOD_REVIEW.scores, "extra": 3 } },
      { ...GOOD_REVIEW, body: "짧아요" },
      { ...GOOD_REVIEW, body: "가".repeat(501) },
      { ...GOOD_REVIEW, anonymous: "no" },
    ]
  ) {
    assertEquals((await call("POST", path, { body })).status, 400, JSON.stringify(body));
  }
  const empty = await call("POST", `/districts/${MAPO_B}/messages`, { body: { body: "   " } });
  assertEquals(empty.status, 400);

  const hate = "저 사람 멍청한 소리만 합니다 정말로";
  const r = await call("POST", path, { body: { ...GOOD_REVIEW, body: hate } });
  assertEquals([r.status, r.body.error.code, r.body.error.reason], [
    422,
    "content_rejected",
    "hate",
  ]);
  assert(!JSON.stringify(r.body).includes("멍청"));
  // A possible false claim is the app's warning to send past, not a server refusal.
  const claim = await call("POST", `/districts/${MAPO_B}/messages`, {
    body: { body: "이건 확실히 조작입니다" },
  });
  assertEquals(claim.status, 200);
  for (const line of logs) assert(!line.includes("멍청"), line);

  const board = await call("GET", `/districts/${MAPO_B}/reviews`);
  assertEquals(board.body.data.reviews, [], "the refused review was not stored");
});

Deno.test("writing: more than five posts a minute is rate_limited", async () => {
  const { call, signUp, reside, advance } = await setup();
  await signUp();
  reside(USER);
  const path = `/districts/${MAPO_B}/messages`;
  for (let i = 0; i < 5; i++) {
    advance(1000);
    assertEquals((await call("POST", path, { body: { body: `메시지 ${i}` } })).status, 200);
  }
  const sixth = await call("POST", path, { body: { body: "여섯 번째" } });
  assertEquals([sixth.status, sixth.body.error.code], [429, "rate_limited"]);
  const review = await call("POST", `/districts/${MAPO_B}/reviews`, { body: GOOD_REVIEW });
  assertEquals(review.body.error.code, "rate_limited", "the limit spans every kind of post");
  advance(60_000);
  assertEquals((await call("POST", path, { body: { body: "다시" } })).status, 200);
});

Deno.test("channel: messages oldest first, mine flagged; threads from the incumbent's bills", async () => {
  const { call, signUp, reside, community } = await setup();
  const handle = await signUp();
  await signUp(OTHER_TOKEN);
  reside(USER);
  reside(OTHER);

  const sent = await call("POST", `/districts/${MAPO_B}/messages`, {
    body: { body: "회의록 링크 공유합니다." },
  });
  assertEquals(sent.body.data.message.author, "익명 주민");
  assertEquals(sent.body.data.message.mine, true);
  await call("POST", `/districts/${MAPO_B}/messages`, {
    token: OTHER_TOKEN,
    body: { body: "감사합니다", anonymous: false },
  });
  await call("POST", `/districts/${MAPO_B}/messages`, {
    body: { body: "활동명으로 남깁니다", anonymous: false },
  });

  assertEquals(community.syncBillThreads(), 3);
  assertEquals(community.syncBillThreads(), 0, "idempotent");

  const r = await call("GET", `/districts/${MAPO_B}/community`);
  assertEquals(r.status, 200);
  assertEquals(r.cache, "no-store", "a signed-in read carries `mine`");
  assertEquals(validateCommunity(r.body.data), []);
  const { messages, threads } = r.body.data;
  assertEquals(messages.map((m: { body: string }) => m.body), [
    "회의록 링크 공유합니다.",
    "감사합니다",
    "활동명으로 남깁니다",
  ]);
  assertEquals(messages.map((m: { mine: boolean }) => m.mine), [true, false, true]);
  assertEquals(messages[2].author, handle);
  assertEquals(threads.length, 3);
  for (const t of threads) {
    assertEquals(t.origin, "법안 발의로 자동 생성");
    assertEquals(t.replies, 0);
    assert(t.sourceUrl.startsWith("http://likms.assembly.go.kr/bill/billDetail.do?billId="));
    assert(t.id.startsWith("bill-"));
  }
  // Newest bill first.
  assertEquals(threads[0].title, "도시공원 보전 및 이용에 관한 법률 일부개정법률안");

  const other = await call("GET", `/districts/${MAPO_A}/community`, { token: null });
  assertEquals(other.body.data, { messages: [], threads: [] });
  assertEquals(other.cache, "public, max-age=15");
});

Deno.test("delete: own posts only", async () => {
  const { call, signUp, reside } = await setup();
  await signUp();
  await signUp(OTHER_TOKEN);
  reside(USER);
  reside(OTHER);
  const board = await call("POST", `/districts/${MAPO_B}/reviews`, { body: GOOD_REVIEW });
  const reviewId = board.body.data.reviews[0].id;
  const msg = await call("POST", `/districts/${MAPO_B}/messages`, { body: { body: "안녕" } });
  const messageId = msg.body.data.message.id;

  for (const path of [`/reviews/${reviewId}`, `/messages/${messageId}`]) {
    assertEquals((await call("DELETE", path, { token: null })).status, 401);
    const theirs = await call("DELETE", path, { token: OTHER_TOKEN });
    assertEquals([theirs.status, theirs.body.error.code], [403, "forbidden"]);
    assertEquals((await call("GET", path)).status, 400);
    assertEquals((await call("DELETE", path)).body.data, { deleted: true });
    assertEquals((await call("DELETE", path)).body.error.code, "not_found");
  }
  assertEquals((await call("DELETE", "/reviews/not-a-uuid")).status, 400);
  const after = await call("GET", `/districts/${MAPO_B}/community`);
  assertEquals(after.body.data.messages, []);
});

Deno.test("export includes every post, anonymous or not", async () => {
  const { call, signUp, reside } = await setup();
  await signUp();
  reside(USER);
  await call("POST", `/districts/${MAPO_B}/reviews`, { body: GOOD_REVIEW });
  await call("POST", `/districts/${MAPO_B}/messages`, { body: { body: "안녕하세요" } });
  const r = await call("GET", "/me/export");
  const posts = r.body.data.posts;
  assertEquals(posts.reviews.length, 1);
  assertEquals(posts.reviews[0].scores, GOOD_REVIEW.scores);
  assertEquals(posts.reviews[0].anonymous, true);
  assertEquals(posts.reviews[0].districtId, MAPO_B);
  assertEquals(posts.messages.map((m: { body: string }) => m.body), ["안녕하세요"]);
  assertEquals(posts.threadReplies, []);
});

Deno.test("DELETE /me: posts=keep leaves 「탈퇴한 주민」; posts=delete removes them", async () => {
  for (const choice of ["keep", "delete"]) {
    const { call, signUp, reside, community } = await setup();
    await signUp();
    reside(USER);
    await call("POST", `/districts/${MAPO_B}/reviews`, {
      body: { ...GOOD_REVIEW, anonymous: false },
    });
    await call("POST", `/districts/${MAPO_B}/messages`, { body: { body: "안녕하세요" } });

    assertEquals((await call("DELETE", `/me?posts=${choice}`)).status, 200);
    const reviews = (await call("GET", `/districts/${MAPO_B}/reviews`, { token: null })).body.data;
    const channel = (await call("GET", `/districts/${MAPO_B}/community`, { token: null })).body
      .data;
    if (choice === "keep") {
      assertEquals(reviews.reviews.map((r: { author: string }) => r.author), ["탈퇴한 주민"]);
      assertEquals(reviews.summary.respondents, 1);
      assertEquals(channel.messages.map((m: { author: string }) => m.author), ["탈퇴한 주민"]);
    } else {
      assertEquals(reviews, { summary: { average: 0, respondents: 0, axes: [] }, reviews: [] });
      assertEquals(channel.messages, []);
      assertEquals(community.t.reviews, []);
    }
  }
});

Deno.test("PostgREST: write functions get the user and district; raised codes map", async () => {
  const db = new MemoryPostgrest();
  db.rpcs.set("post_message", (args) => {
    assertEquals(args, {
      p_user_id: USER,
      p_district_id: MAPO_B,
      p_body: "안녕",
      p_anonymous: true,
    });
    throw raised("rate_limited");
  });
  const store = new PostgrestCommunityStore(db);
  let caught: unknown;
  try {
    await store.postMessage({ userId: USER, districtId: MAPO_B, body: "안녕", anonymous: true });
  } catch (error) {
    caught = communityError(error);
  }
  assertInstanceOf(caught, ApiError);
  assertEquals((caught as ApiError).code, "rate_limited");
  assertEquals(
    (communityError(raised("residency_required")) as ApiError).code,
    "residency_required",
  );
  assertEquals((communityError(raised("consent_required")) as ApiError).code, "consent_required");

  db.rpcs.set("bff_review_summary", () => [{
    respondents: 0,
    average: null,
    communication: null,
    pledges: null,
    development: null,
    integrity: null,
  }]);
  assertEquals((await store.reviewSummary(MAPO_B)).average, null);
});

Deno.test("content guard: the app's hate list, spaces ignored; claims are not refused", () => {
  assertEquals(inspectContent("멍청한 소리"), "hate");
  assertEquals(inspectContent("쓰레기같은 정책"), "hate");
  assertEquals(inspectContent("이건 확실히조작입니다"), null);
  assertEquals(inspectContent("판정문 읽어보셨나요?"), null);
});

Deno.test("channel broadcast: the trigger's payload is the GET message minus `mine`", async () => {
  // The broadcast is composed in SQL (migrations/*_channel_broadcast.sql), not here, so this
  // pins the two together: the same keys, the same author labels, createdAt in the same form.
  const sql = await Deno.readTextFile(
    new URL("../../migrations/20260930000000_channel_broadcast.sql", import.meta.url),
  );
  const payload = /function public\.channel_message_payload[\s\S]*?\$\$;/.exec(sql)?.[0] ?? "";
  const sqlKeys = [...payload.matchAll(/^\s+'(\w+)', /gm)].map((m) => m[1]).sort();

  const { call, signUp, reside } = await setup();
  await signUp();
  reside(USER);
  const sent = await call("POST", `/districts/${MAPO_B}/messages`, {
    body: { body: "안녕하세요" },
  });
  const message = sent.body.data.message;
  const viewKeys = Object.keys(message).filter((k) => k !== "mine").sort();
  assertEquals(sqlKeys, viewKeys);

  assert(payload.includes(`'${ANONYMOUS_AUTHOR}'`));
  assert(payload.includes(`'${DELETED_AUTHOR}'`));
  assert(!/'author_id'|'anonymous'|'mine'/.test(payload), "no author id, flag or `mine` leaves");
  assert(/"T"HH24:MI:SS\.MS"Z"/.test(payload), "createdAt as toISOString writes it");
  assert(/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(message.createdAt));

  assert(sql.includes("'district-chat:' || msg.district_id"));
  assert(/jsonb_build_object\('id', old\.id, 'deleted', true\)/.test(sql));
});
