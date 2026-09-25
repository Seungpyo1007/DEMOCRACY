import { assert, assertEquals, assertMatch } from "@std/assert";
import {
  BANNED_FRAGMENTS,
  COMMON_SURNAMES,
  drawHandles,
  GIVEN_NAME_WORDS,
  HANDLE_PATTERN,
  HANDLE_WORDS,
} from "./handles.ts";
import { seededBytes } from "../../../testdata/fake_auth.ts";

Deno.test("handle words: neutral by construction", () => {
  assert(HANDLE_WORDS.length >= 60, `only ${HANDLE_WORDS.length} words`);
  assertEquals(new Set(HANDLE_WORDS).size, HANDLE_WORDS.length, "duplicates");
  for (const word of HANDLE_WORDS) {
    assertMatch(word, /^[가-힣]{2,5}$/);
    // A two-syllable word opening with a surname reads as a person's name (이슬, 한솔).
    if (word.length === 2) assert(!COMMON_SURNAMES.has(word[0]), `surname-like: ${word}`);
    assert(!GIVEN_NAME_WORDS.includes(word), `given name: ${word}`);
    for (const bad of BANNED_FRAGMENTS) assert(!word.includes(bad), `${word} contains ${bad}`);
  }
});

Deno.test("drawHandles: word + space + 10..99, distinct, deterministic, skips excluded", () => {
  const a = drawHandles(5, seededBytes(7));
  assertEquals(a, drawHandles(5, seededBytes(7)));
  assertEquals(new Set(a).size, 5);
  for (const h of a) {
    assertMatch(h, HANDLE_PATTERN);
    const [word, digits] = h.split(" ");
    assert(HANDLE_WORDS.includes(word), h);
    const n = Number(digits);
    assert(n >= 10 && n <= 99, h);
  }
  const b = drawHandles(5, seededBytes(7), new Set([a[0]]));
  assert(!b.includes(a[0]));

  // Every digit pair appears across enough draws: 10 and 99 are reachable.
  const many = drawHandles(2000, seededBytes(3)).map((h) => Number(h.split(" ")[1]));
  assertEquals(Math.min(...many), 10);
  assertEquals(Math.max(...many), 99);

  // A stuck random source yields fewer handles rather than looping forever.
  assertEquals(drawHandles(5, (n) => new Uint8Array(n)).length, 1);
});
