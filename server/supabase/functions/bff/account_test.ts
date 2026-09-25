import { assert, assertEquals, assertInstanceOf, assertMatch, assertRejects } from "@std/assert";
import { getUser } from "../_shared/auth.ts";
import { ApiError } from "../_shared/envelope.ts";
import { HANDLE_PATTERN } from "../_shared/handles.ts";
import { UpstreamError } from "../_shared/http.ts";
import { createPostgrest, PostgrestError } from "../_shared/postgrest.ts";
import { accountError, CONSENT_VERSION } from "./account.ts";
import { MemoryAccountStore, PostgrestAccountStore } from "./account_store.ts";
import { validateEnvelope } from "./contract.ts";
import { createHandler } from "./handler.ts";
import { sha256Hex } from "./residency.ts";
import { MemoryStore } from "./store.ts";
import { ANON_KEY, fakeGotrue, seededBytes, SUPABASE_URL } from "../../../testdata/fake_auth.ts";
import { fakeUpstream } from "../../../testdata/fake_upstream.ts";
import { MAPO_B, NOW, runPipeline, toTables } from "../../../testdata/pipeline.ts";

const USER = "00000000-0000-4000-8000-000000000001";
const OTHER = "00000000-0000-4000-8000-000000000002";
const TOKEN = "user-jwt-1";
const OTHER_TOKEN = "user-jwt-2";
const DAY = 86_400_000;

async function setup(overrides: Record<string, () => Response> = {}) {
  const { db } = await runPipeline();
  let clock = NOW;
  const now = () => clock;
  const gotrue = fakeGotrue({
    [TOKEN]: { id: USER, email: "resident@example.com", provider: "kakao" },
    [OTHER_TOKEN]: { id: OTHER, email: null, provider: "apple" },
  });
  const accounts = new MemoryAccountStore(undefined, now);
  const up = fakeUpstream(overrides);
  const logs: string[] = [];
  const h = createHandler({
    store: new MemoryStore(toTables(db)),
    fetch: up.fetch,
    jusoKey: "J",
    kakaoKey: "K",
    accounts,
    auth: gotrue.auth,
    randomBytes: seededBytes(42),
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
    if (token !== null) headers.Authorization = `Bearer ${token}`;
    const res = await h(
      new Request(`${SUPABASE_URL}/functions/v1/bff${path}`, {
        method,
        headers,
        body: opts.body === undefined ? undefined : JSON.stringify(opts.body),
      }),
    );
    const body = await res.json();
    assertEquals(validateEnvelope(body, !res.ok), [], `${method} ${path}`);
    assertEquals(res.headers.get("Cache-Control"), "no-store", `${method} ${path}`);
    return { status: res.status, body };
  };
  const advance = (days: number) => {
    clock = new Date(clock.getTime() + days * DAY);
  };
  return { call, accounts, gotrue, up, logs, advance };
}

type Call = Awaited<ReturnType<typeof setup>>["call"];

/** Draws options and consents with the first one; returns the handle. */
async function signUp(call: Call, token = TOKEN): Promise<string> {
  const opts = await call("GET", "/me/handle/options", { token });
  const handle = opts.body.data.handles[0];
  const r = await call("POST", "/me/consent", {
    token,
    body: { age14: true, terms: true, privacy: true, notify: false, handle },
  });
  assertEquals(r.status, 200);
  return handle;
}

function keysOf(value: unknown, out = new Set<string>()): Set<string> {
  if (Array.isArray(value)) value.forEach((v) => keysOf(v, out));
  else if (value && typeof value === "object") {
    for (const [k, v] of Object.entries(value)) {
      out.add(k);
      keysOf(v, out);
    }
  }
  return out;
}

Deno.test("account routes: 401 without a user, with the anon key, or a bad token", async () => {
  const { call, gotrue } = await setup();
  for (const token of [null, ANON_KEY, "expired-or-forged"]) {
    for (const [method, path] of [["GET", "/me"], ["GET", "/me/export"], ["DELETE", "/me"]]) {
      const r = await call(method, path, { token });
      assertEquals([method, path, r.status, r.body.error.code], [
        method,
        path,
        401,
        "unauthorized",
      ]);
    }
  }
  // The anon key is recognised locally and never sent to GoTrue as a user token.
  assertEquals(gotrue.requests.length, 3);
  // An anonymous (guest) Supabase session is not an account either.
  const guest = fakeGotrue({ g: { id: USER, isAnonymous: true } });
  assertEquals(await guest.auth.user("g"), null);
});

Deno.test("account routes: method and path errors", async () => {
  const { call } = await setup();
  assertEquals((await call("PUT", "/me")).status, 400);
  assertEquals((await call("GET", "/me/consent")).status, 400);
  assertEquals((await call("GET", "/me/nope")).status, 404);
  // Public routes stay GET only.
  assertEquals((await call("POST", `/districts/${MAPO_B}/profile`)).status, 400);
});

Deno.test("sign-up: offered handle, required consents, then /me", async () => {
  const { call, accounts } = await setup();
  const empty = await call("GET", "/me");
  assertEquals(empty.body.data, { profile: null, consents: [], residency: null });

  const opts = await call("GET", "/me/handle/options");
  const handles: string[] = opts.body.data.handles;
  assertEquals(handles.length, 5);
  assertEquals(new Set(handles).size, 5);
  for (const h of handles) assertMatch(h, HANDLE_PATTERN);
  assertEquals(accounts.t.offers.map((o) => o.handle).sort(), [...handles].sort());
  assertEquals(opts.body.data.expiresAt, new Date(NOW.getTime() + 30 * 60_000).toISOString());

  const base = { age14: true, terms: true, privacy: true, notify: true, handle: handles[2] };
  for (const missing of ["age14", "terms", "privacy"]) {
    const r = await call("POST", "/me/consent", { body: { ...base, [missing]: false } });
    assertEquals([missing, r.status, r.body.error.code], [missing, 400, "bad_request"]);
  }
  const noAge = { ...base } as Record<string, unknown>;
  delete noAge.age14;
  assertEquals((await call("POST", "/me/consent", { body: noAge })).status, 400);
  assertEquals((await call("POST", "/me/consent", { body: "[]" })).status, 400);

  // A well-formed name that was not offered.
  const other = handles.includes("솔숲 11") ? "솔숲 12" : "솔숲 11";
  const notOffered = await call("POST", "/me/consent", { body: { ...base, handle: other } });
  assertEquals([notOffered.status, notOffered.body.error.code], [403, "forbidden"]);
  assertEquals(accounts.t.profiles, []);

  const ok = await call("POST", "/me/consent", { body: base });
  assertEquals(ok.status, 200);
  const me = ok.body.data;
  assertEquals(me.profile.handle, handles[2]);
  assertEquals(me.profile.provider, "kakao");
  assertEquals(me.profile.notify, true);
  assertEquals(me.profile.handleChangedAt, null);
  assertEquals(
    me.consents.map((c: { kind: string; granted: boolean; version: string }) => [
      c.kind,
      c.granted,
      c.version,
    ]),
    [
      ["age14", true, CONSENT_VERSION],
      ["terms", true, CONSENT_VERSION],
      ["privacy", true, CONSENT_VERSION],
      ["notify", true, CONSENT_VERSION],
    ],
  );
  assertEquals(accounts.t.offers, [], "offers are spent");

  // Retrying consent is harmless and keeps the handle.
  const again = await call("POST", "/me/consent", { body: { ...base, notify: false } });
  assertEquals([again.status, again.body.data.profile.handle], [200, handles[2]]);
  assertEquals(again.body.data.profile.notify, false);
});

Deno.test("handle change: first change free, second within 30 days → 429, then allowed", async () => {
  const { call, advance } = await setup();
  const first = await signUp(call);

  const opts = await call("GET", "/me/handle/options");
  assert(!opts.body.data.handles.includes(first), "the current name is not offered");
  const changed = await call("POST", "/me/handle", { body: { handle: opts.body.data.handles[0] } });
  assertEquals(changed.status, 200);
  assertEquals(changed.body.data.profile.handle, opts.body.data.handles[0]);
  const availableAt = new Date(NOW.getTime() + 30 * DAY).toISOString();
  assertEquals(changed.body.data.profile.handleChangeAvailableAt, availableAt);

  advance(10);
  const blockedOptions = await call("GET", "/me/handle/options");
  assertEquals([blockedOptions.status, blockedOptions.body.error.code], [429, "too_soon"]);
  assertEquals(blockedOptions.body.error.availableAt, availableAt);
  const blocked = await call("POST", "/me/handle", { body: { handle: "솔숲 11" } });
  assertEquals([blocked.status, blocked.body.error.code], [429, "too_soon"]);
  assertEquals(blocked.body.error.availableAt, availableAt);

  advance(21);
  const later = await call("GET", "/me/handle/options");
  assertEquals(later.status, 200);
  const ok = await call("POST", "/me/handle", { body: { handle: later.body.data.handles[1] } });
  assertEquals(ok.status, 200);
});

Deno.test("handle: a name taken between offer and claim → 409; no profile → 403", async () => {
  const { call, accounts } = await setup();
  const noProfile = await call("POST", "/me/handle", { body: { handle: "솔숲 11" } });
  assertEquals([noProfile.status, noProfile.body.error.code], [403, "consent_required"]);

  const opts = await call("GET", "/me/handle/options");
  const wanted = opts.body.data.handles[0];
  // Someone else ends up with it first.
  accounts.t.profiles.push({
    user_id: OTHER,
    provider: "apple",
    email: null,
    handle: wanted,
    handle_changed_at: null,
    notify: false,
    created_at: NOW.toISOString(),
  });
  const r = await call("POST", "/me/consent", {
    body: { age14: true, terms: true, privacy: true, notify: false, handle: wanted },
  });
  assertEquals([r.status, r.body.error.code], [409, "conflict"]);

  // Taken names are not offered in the first place.
  const next = await call("GET", "/me/handle/options", { token: OTHER_TOKEN });
  assert(!next.body.data.handles.includes(wanted));
});

Deno.test("PATCH /me: notify toggles and is recorded as consent; needs a profile", async () => {
  const { call, advance } = await setup();
  const before = await call("PATCH", "/me", { body: { notify: true } });
  assertEquals([before.status, before.body.error.code], [403, "consent_required"]);

  await signUp(call);
  assertEquals((await call("PATCH", "/me", { body: { notify: "yes" } })).status, 400);
  advance(1);
  const r = await call("PATCH", "/me", { body: { notify: true } });
  assertEquals(r.body.data.profile.notify, true);
  const notify = r.body.data.consents.find((c: { kind: string }) => c.kind === "notify");
  assertEquals([notify.granted, notify.at], [true, new Date(NOW.getTime() + DAY).toISOString()]);
});

Deno.test("export: profile, consents, residency; no address, coordinates or token", async () => {
  const { call, accounts } = await setup();
  await signUp(call);
  accounts.t.residency.push({
    user_id: USER,
    district_id: MAPO_B,
    method: "address_self_declared",
    token_hash: "a".repeat(64),
    verified_at: NOW.toISOString(),
    expires_at: new Date(NOW.getTime() + 180 * DAY).toISOString(),
  });
  const r = await call("GET", "/me/export");
  assertEquals(r.status, 200);
  const data = r.body.data;
  assertEquals(data.account, { id: USER, provider: "kakao", email: "resident@example.com" });
  assertEquals(data.residency.districtId, MAPO_B);
  assertEquals(data.residency.displayName, "서울 마포구 을");
  assertEquals(data.consents.length, 4);
  const keys = keysOf(data);
  for (const banned of ["address", "roadAddress", "lat", "lng", "token", "tokenHash"]) {
    assert(!keys.has(banned), `export has ${banned}`);
  }
  assert(!JSON.stringify(data).includes("a".repeat(64)), "token hash leaked");
});

Deno.test("DELETE /me: removes rows and the auth user; posts choice required", async () => {
  const { call, accounts, gotrue } = await setup();
  await signUp(call);
  await signUp(call, OTHER_TOKEN);
  assertEquals((await call("DELETE", "/me")).status, 400);
  assertEquals((await call("DELETE", "/me?posts=maybe")).status, 400);
  assertEquals(gotrue.deleted, []);

  const r = await call("DELETE", "/me?posts=keep");
  assertEquals(r.body.data, { deleted: true, posts: "keep" });
  assertEquals(gotrue.deleted, [USER]);
  assertEquals(accounts.t.profiles.map((p) => p.user_id), [OTHER]);
  assert(accounts.t.consents.every((c) => c.user_id === OTHER));
});

Deno.test("POST /me/under14: deletes the auth user and keeps nothing", async () => {
  const { call, accounts, gotrue } = await setup();
  await call("GET", "/me/handle/options");
  const r = await call("POST", "/me/under14");
  assertEquals(r.body.data, { deleted: true });
  assertEquals(gotrue.deleted, [USER]);
  assertEquals(accounts.t, { profiles: [], consents: [], offers: [], residency: [] });

  // Once an account exists, deletion goes through DELETE /me and its posts choice.
  await signUp(call, OTHER_TOKEN);
  const late = await call("POST", "/me/under14", { token: OTHER_TOKEN });
  assertEquals([late.status, late.body.error.code], [409, "conflict"]);
});

Deno.test("PostgREST: raised account errors surface code, message and hint", async () => {
  const bodies: Record<string, [number, unknown]> = {
    claim_handle: [400, {
      code: "P0001",
      message: "too_soon",
      details: null,
      hint: "2026-10-24T03:00:00Z",
    }],
    accept_consent: [409, {
      code: "23505",
      message: 'duplicate key value violates unique constraint "profiles_handle_key"',
    }],
    issue_residency: [400, { code: "P0001", message: "consent_required" }],
  };
  const db = createPostgrest(
    (input) => {
      const fn = String(input).split("/rpc/")[1];
      const [status, body] = bodies[fn];
      return Promise.resolve(Response.json(body, { status }));
    },
    SUPABASE_URL,
    "service",
  );
  const store = new PostgrestAccountStore(db);

  const tooSoon = await assertRejects(() => store.claimHandle(USER, "솔숲 11"), PostgrestError);
  assertEquals([tooSoon.code, tooSoon.dbMessage, tooSoon.hint], [
    "P0001",
    "too_soon",
    "2026-10-24T03:00:00Z",
  ]);
  const mapped = accountError(tooSoon);
  assertInstanceOf(mapped, ApiError);
  assertEquals([mapped.code, mapped.extra], ["too_soon", {
    availableAt: "2026-10-24T03:00:00.000Z",
  }]);

  const dup = await assertRejects(() =>
    store.acceptConsent({
      userId: USER,
      provider: "kakao",
      email: null,
      handle: "솔숲 11",
      notify: false,
      version: CONSENT_VERSION,
    }), PostgrestError);
  assertEquals((accountError(dup) as ApiError).code, "conflict");

  const noProfile = await assertRejects(() =>
    store.issueResidency({
      userId: USER,
      districtId: MAPO_B,
      method: "address_self_declared",
      tokenHash: "0".repeat(64),
      verifiedAt: NOW.toISOString(),
      expiresAt: NOW.toISOString(),
    }), PostgrestError);
  assertEquals((accountError(noProfile) as ApiError).code, "consent_required");

  // Anything else stays an internal error.
  const other = new PostgrestError("postgrest 500", 500, "XX000", "boom");
  assertEquals(accountError(other), other);
});

Deno.test("getUser: GoTrue is asked with the bearer; outages are upstream errors", async () => {
  const seen: Headers[] = [];
  const user = await getUser(
    (_url, init) => {
      seen.push(new Headers(init?.headers));
      return Promise.resolve(Response.json({
        id: USER,
        email: "",
        app_metadata: { provider: "email" },
      }));
    },
    SUPABASE_URL,
    ANON_KEY,
    TOKEN,
  );
  assertEquals(user, { id: USER, email: null, provider: "email" });
  assertEquals(seen[0].get("Authorization"), `Bearer ${TOKEN}`);
  assertEquals(seen[0].get("apikey"), ANON_KEY);

  assertEquals(
    await getUser(
      () => Promise.resolve(new Response("", { status: 500 })),
      SUPABASE_URL,
      ANON_KEY,
      TOKEN,
    ),
    null,
  );
  await assertRejects(
    () => getUser(() => Promise.reject(new TypeError("dns")), SUPABASE_URL, ANON_KEY, TOKEN),
    UpstreamError,
  );
});

// ------------------------------------------------------------ residency

const SANGAM = "서울특별시 마포구 월드컵북로 400 (상암동)";

Deno.test("residency: needs a user, then a profile, then a well-formed place", async () => {
  const { call, up } = await setup();
  const anon = await call("POST", "/residency/verify", {
    token: ANON_KEY,
    body: { roadAddress: SANGAM },
  });
  assertEquals([anon.status, anon.body.error.code], [401, "unauthorized"]);

  const noProfile = await call("POST", "/residency/verify", { body: { roadAddress: SANGAM } });
  assertEquals([noProfile.status, noProfile.body.error.code], [403, "consent_required"]);
  assertEquals(up.requests.length, 0, "no lookup before the profile check");

  await signUp(call);
  for (
    const body of [
      {},
      { roadAddress: SANGAM, lat: 37.5, lng: 127 },
      { roadAddress: "마포" },
      { lat: 10, lng: 127 },
      { lat: "37.5", lng: 127 },
    ]
  ) {
    const r = await call("POST", "/residency/verify", { body });
    assertEquals([JSON.stringify(body), r.status], [JSON.stringify(body), 400]);
  }
  assertEquals((await call("GET", "/residency/verify")).status, 400);
});

Deno.test("residency: address → district on the server; only the token hash is kept", async () => {
  const { call, accounts, logs } = await setup();
  await signUp(call);
  // A client-supplied district is ignored: the server derives 마포구 을 itself.
  const r = await call("POST", "/residency/verify", {
    body: { roadAddress: `  ${SANGAM.replace(" 400", "  400")} `, districtId: "nec-313502f4" },
  });
  assertEquals(r.status, 200);
  const d = r.body.data;
  assertEquals(d.districtId, MAPO_B);
  assertEquals(d.displayName, "서울 마포구 을");
  assertEquals(d.method, "address_self_declared");
  assertEquals(d.verifiedAt, NOW.toISOString());
  assertEquals(d.expiresAt, new Date(NOW.getTime() + 180 * DAY).toISOString());
  assertMatch(d.token, /^[A-Za-z0-9_-]{43}$/);
  assertEquals(Object.keys(d).sort(), [
    "displayName",
    "districtId",
    "expiresAt",
    "method",
    "token",
    "verifiedAt",
  ]);

  const [row] = accounts.t.residency;
  assertEquals(row.token_hash, await sha256Hex(d.token));
  assert(!JSON.stringify(accounts.t).includes("월드컵북로"), "address persisted");
  assert(!JSON.stringify(accounts.t).includes(d.token), "raw token persisted");
  assertEquals(logs, []);

  const me = await call("GET", "/me");
  assertEquals(me.body.data.residency, {
    districtId: MAPO_B,
    displayName: "서울 마포구 을",
    method: "address_self_declared",
    verifiedAt: d.verifiedAt,
    expiresAt: d.expiresAt,
  });
});

Deno.test("residency: coordinates → 행정동 → district", async () => {
  const { call } = await setup();
  await signUp(call);
  const r = await call("POST", "/residency/verify", { body: { lat: 37.55, lng: 126.9 } });
  assertEquals([r.status, r.body.data.districtId], [200, MAPO_B]);
});

Deno.test("residency: unmapped, ambiguous or unknown places are no_match", async () => {
  const { call, accounts } = await setup();
  await signUp(call);
  for (
    const roadAddress of [
      "부산광역시 중구 가상로 1 (가상동)", // found, but no district mapping
      "서울특별시 마포구 어딘가로 1", // not among juso's results, which span districts
    ]
  ) {
    const r = await call("POST", "/residency/verify", { body: { roadAddress } });
    assertEquals([roadAddress, r.status, r.body.error.code], [roadAddress, 404, "no_match"]);
  }
  assertEquals(accounts.t.residency, []);

  const other = await setup({
    "dapi.kakao.com": () =>
      Response.json({
        documents: [{ region_type: "H", code: "2611051000", region_3depth_name: "가상동" }],
      }),
  });
  await signUp(other.call);
  const r = await other.call("POST", "/residency/verify", { body: { lat: 35.1, lng: 129.03 } });
  assertEquals([r.status, r.body.error.code], [404, "no_match"]);
});

Deno.test("residency: an upstream failure keeps the address out of logs and storage", async () => {
  const { call, accounts, logs } = await setup({
    "business.juso.go.kr": () => new Response("down", { status: 500 }),
  });
  await signUp(call);
  const secret = "서울특별시 마포구 비밀길 123";
  const r = await call("POST", "/residency/verify", { body: { roadAddress: secret } });
  assertEquals([r.status, r.body.error.code], [502, "upstream"]);
  assert(logs.length > 0);
  for (const line of logs) {
    assert(!line.includes("비밀길") && !line.includes(encodeURIComponent("비밀길")), line);
    assert(!line.includes("confmKey"), line);
  }
  assert(!JSON.stringify(r.body).includes("비밀길"));
  assertEquals(accounts.t.residency, []);
});

Deno.test("residency: re-verify replaces, expiry hides it from /me, DELETE removes", async () => {
  const { call, accounts, advance } = await setup();
  await signUp(call);
  const first = await call("POST", "/residency/verify", { body: { roadAddress: SANGAM } });
  advance(1);
  const second = await call("POST", "/residency/verify", { body: { lat: 37.55, lng: 126.9 } });
  assert(first.body.data.token !== second.body.data.token);
  assertEquals(accounts.t.residency.length, 1);
  assertEquals(accounts.t.residency[0].token_hash, await sha256Hex(second.body.data.token));

  advance(181);
  assertEquals((await call("GET", "/me")).body.data.residency, null);
  assertEquals((await call("GET", "/me/export")).body.data.residency.districtId, MAPO_B);

  assertEquals((await call("DELETE", "/residency")).body.data, { deleted: true });
  assertEquals(accounts.t.residency, []);
});
