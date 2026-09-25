// 활동명 (activity names) the server offers at sign-up and on a change.
//
// A handle is a neutral nature word, a space and two digits: "솔숲 42". Users pick
// from what the server drew; they never type one, so a handle cannot carry a real name,
// a party, a slogan or a place. The word list is curated against that:
//  * no two-syllable word that opens with a common surname (이슬, 노을, 한솔, 윤슬 read
//    as a person's name), and no word that is itself a common given name (하늘, 바다);
//  * no party name or fragment (민주, 국민, 정의, 미래, 개혁, 진보, 녹색 …);
//  * no colour a party is known by (파랑, 빨강, 노랑, 주황, 보라, 초록 …) and no
//    movement symbol (촛불, 태극, 무궁화);
//  * no place: mountains, rivers and islands are regions (한라, 한강, 설악 …).
// handles_test.ts checks these rules against the list.

export const HANDLE_WORDS: readonly string[] = [
  "솔숲",
  "물안개",
  "들꽃",
  "조약돌",
  "은행잎",
  "너울",
  "산들",
  "바람결",
  "모래톱",
  "소나기",
  "새벽별",
  "여울",
  "갈대숲",
  "도토리",
  "솔방울",
  "개울",
  "물결",
  "달무리",
  "별무리",
  "봄비",
  "가랑비",
  "이슬비",
  "산마루",
  "풀잎",
  "꽃잎",
  "억새",
  "들녘",
  "오솔길",
  "징검다리",
  "나뭇잎",
  "반딧불",
  "몽돌",
  "눈송이",
  "눈꽃",
  "물수제비",
  "파도",
  "뭉게구름",
  "새털구름",
  "햇살",
  "봄볕",
  "샘물",
  "옹달샘",
  "시냇물",
  "잔물결",
  "조각달",
  "초승달",
  "보름달",
  "샛별",
  "달빛",
  "별빛",
  "첫눈",
  "함박눈",
  "메아리",
  "풀벌레",
  "다람쥐",
  "느티나무",
  "버드나무",
  "싸리꽃",
  "솔바람",
  "갯바위",
  "물레방아",
  "들국화",
  "산딸기",
  "모닥불",
  "호숫가",
  "갈매기",
  "물총새",
];

/** Common surnames (about 85% of the population). */
export const COMMON_SURNAMES = new Set(
  [..."김이박최정강조윤장임한오서신권황안송전홍유고문양손배백허남심노하곽성차주우구민류나진지엄채원"],
);

/** Substrings no handle may contain: parties, party colours, symbols, places. */
export const BANNED_FRAGMENTS: readonly string[] = [
  // parties, past and present
  "민주",
  "국민",
  "정의",
  "미래",
  "개혁",
  "진보",
  "보수",
  "녹색",
  "기본",
  "조국",
  "희망",
  "통합",
  "자유",
  "새누리",
  "한나라",
  "열린",
  "바른",
  "평화",
  "시대",
  // colours
  "파랑",
  "파란",
  "푸른",
  "빨강",
  "빨간",
  "붉은",
  "노랑",
  "노란",
  "주황",
  "보라",
  "초록",
  "분홍",
  // symbols
  "촛불",
  "태극",
  "무궁화",
  "횃불",
  // places
  "한라",
  "백두",
  "지리산",
  "설악",
  "금강",
  "한강",
  "낙동",
  "섬진",
  "남산",
  "독도",
  "제주",
  "서울",
];

/** Words that are common given names on their own. */
export const GIVEN_NAME_WORDS: readonly string[] = [
  "하늘",
  "바다",
  "이슬",
  "노을",
  "한솔",
  "윤슬",
  "보람",
  "나래",
  "다솜",
  "가람",
  "슬기",
  "은하",
];

export const HANDLE_PATTERN = /^[가-힣]{2,5} [1-9][0-9]$/;

/** A uniform integer in [0, max) from four random bytes (bias < 1e-7 for max < 500). */
function pick(randomBytes: (n: number) => Uint8Array, max: number): number {
  const b = randomBytes(4);
  return (((b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3]) >>> 0) % max;
}

/**
 * Up to `count` distinct handles such as "솔숲 42", skipping any in `exclude` (taken ones).
 * Randomness is injected so tests are exact. Gives up after a bounded number of draws, so a
 * broken random source returns fewer handles instead of spinning.
 */
export function drawHandles(
  count: number,
  randomBytes: (n: number) => Uint8Array,
  exclude: ReadonlySet<string> = new Set(),
): string[] {
  const out = new Set<string>();
  for (let tries = 0; out.size < count && tries < count * 50; tries++) {
    const word = HANDLE_WORDS[pick(randomBytes, HANDLE_WORDS.length)];
    const handle = `${word} ${10 + pick(randomBytes, 90)}`;
    if (!exclude.has(handle)) out.add(handle);
  }
  return [...out];
}
