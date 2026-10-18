/// Hangul syllable arithmetic, for 초성 search over the interest list.
///
/// Written here rather than pulled in as a package: the whole of it is the
/// Unicode formula for a precomposed syllable (U+AC00 + (초성 × 21 + 중성) ×
/// 28 + 종성), and a dependency for forty lines would be one more thing to
/// audit and keep current.
library;

const _syllableBase = 0xAC00;
const _syllableLast = 0xD7A3;
const _jungCount = 21;
const _jongCount = 28;

/// The nineteen initial consonants, as compatibility jamo -- the letters a
/// Korean keyboard types on their own.
const _choseong = [
  'ㄱ', 'ㄲ', 'ㄴ', 'ㄷ', 'ㄸ', 'ㄹ', 'ㅁ', 'ㅂ', 'ㅃ', 'ㅅ', //
  'ㅆ', 'ㅇ', 'ㅈ', 'ㅉ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ',
];

/// The final consonants by index (0 is none), as compatibility jamo.
const _jongseong = [
  '', 'ㄱ', 'ㄲ', 'ㄳ', 'ㄴ', 'ㄵ', 'ㄶ', 'ㄷ', 'ㄹ', 'ㄺ', //
  'ㄻ', 'ㄼ', 'ㄽ', 'ㄾ', 'ㄿ', 'ㅀ', 'ㅁ', 'ㅂ', 'ㅄ', 'ㅅ', //
  'ㅆ', 'ㅇ', 'ㅈ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ',
];

/// One precomposed syllable taken apart.
class HangulSyllable {
  const HangulSyllable(this.cho, this.jung, this.jong);

  /// Indexes into the Unicode tables: 초성 0..18, 중성 0..20, 종성 0..27.
  final int cho;
  final int jung;
  final int jong;

  /// The 초성 as the jamo a keyboard types.
  String get initial => _choseong[cho];

  /// The 종성 as a jamo, or '' when there is none.
  String get finalConsonant => _jongseong[jong];
}

/// The parts of [rune], or null when it is not a precomposed syllable.
HangulSyllable? decompose(int rune) {
  if (rune < _syllableBase || rune > _syllableLast) {
    return null;
  }
  final offset = rune - _syllableBase;
  return HangulSyllable(
    offset ~/ (_jungCount * _jongCount),
    (offset % (_jungCount * _jongCount)) ~/ _jongCount,
    offset % _jongCount,
  );
}

/// Whether [rune] is one of the nineteen initial consonants typed alone.
bool isInitialJamo(int rune) => _choseong.contains(String.fromCharCode(rune));

/// [text] with every syllable replaced by its 초성: `교통` → `ㄱㅌ`. Anything
/// else is kept as it is.
String initialsOf(String text) {
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    buffer.write(decompose(rune)?.initial ?? String.fromCharCode(rune));
  }
  return buffer.toString();
}

/// Lowercased, with spaces and the separators labels use (`·`, `-`, `/`)
/// taken out, so `지하철 · 광역철도` and `지하철광역철도` read the same.
String normaliseForSearch(String text) =>
    text.toLowerCase().replaceAll(RegExp(r'[\s·・\-/,()]'), '');

/// Whether [query] occurs in [text], Hangul-aware.
///
/// Per character of the query:
/// - a lone initial consonant matches any syllable that starts with it, so
///   `ㄱㅌ` finds 교통 and `ㅈㅎㅊ` finds 지하철;
/// - anything else must be the same character.
///
/// The last character is allowed to be still mid-composition, because that
/// is what a Korean keyboard shows while the reader is typing: `교토` (on the
/// way to 교통) matches 교통, and `벗` (on the way to 버스) matches 버스.
///
/// Both sides go through [normaliseForSearch] first.
bool hangulContains(String text, String query) =>
    hangulIndexOf(text, query) >= 0;

/// Where [query] first matches in the normalised [text], by the rules of
/// [hangulContains], or -1. Zero means the text starts with it.
int hangulIndexOf(String text, String query) {
  final t = normaliseForSearch(text).runes.toList();
  final q = normaliseForSearch(query).runes.toList();
  if (q.isEmpty) {
    return 0;
  }
  for (var start = 0; start + q.length <= t.length; start++) {
    if (_matchesAt(t, q, start)) {
      return start;
    }
  }
  return -1;
}

bool _matchesAt(List<int> t, List<int> q, int start) {
  for (var j = 0; j < q.length; j++) {
    final target = t[start + j];
    final typed = q[j];
    final last = j == q.length - 1;
    if (typed == target) {
      continue;
    }
    if (isInitialJamo(typed)) {
      if (decompose(target)?.initial == String.fromCharCode(typed)) {
        continue;
      }
      return false;
    }
    if (last &&
        _stillComposing(
          typed,
          target,
          start + j + 1 < t.length ? t[start + j + 1] : null,
        )) {
      continue;
    }
    return false;
  }
  return true;
}

/// Whether [typed], the last character of the query, is [target] caught
/// half-typed.
bool _stillComposing(int typed, int target, int? next) {
  final a = decompose(typed);
  final b = decompose(target);
  if (a == null || b == null || a.cho != b.cho || a.jung != b.jung) {
    return false;
  }
  // `교토` → 교통: the final consonant has not been typed yet.
  if (a.jong == 0) {
    return true;
  }
  // `벗` → 버스: the keyboard has hung the next syllable's initial on this
  // one as a final, and will move it across with the next vowel.
  if (b.jong == 0 && next != null) {
    return decompose(next)?.initial == a.finalConsonant;
  }
  return false;
}
