/// What the resident told us about themselves, for match analysis.
///
/// Every field is optional by design. The guide marks this step
/// `프로필 (AI 분석용 · 선택)`, and the address gate must not become a
/// personal-data gate: a resident who skips all of it still gets the whole
/// read-only app.
class ResidentProfile {
  const ResidentProfile({this.tags = const {}, this.interest = 2});

  /// The chips the guide offers. Both mockups draw a subset; this is the
  /// union, since the README lists 청년 and only the Android frame drops it.
  static const availableTags = <String>[
    '30대',
    '자영업',
    '1인 가구',
    '부동산',
    '세금',
    '복지',
    '교육',
    '청년',
  ];

  /// `Slider(divisions: 4)` -- five stops, not a continuum.
  static const interestSteps = 4;

  static const _interestLabels = ['매우 낮음', '낮음', '보통', '높음', '매우 높음'];

  final Set<String> tags;

  /// 0..[interestSteps].
  final int interest;

  String get interestLabel => _interestLabels[interest.clamp(0, interestSteps)];

  /// The chips that name a policy area rather than a demographic. These are
  /// what a match runs against; the rest only describe who is asking.
  Set<String> get policyTags =>
      tags.where((tag) => !const {'30대', '자영업', '1인 가구'}.contains(tag)).toSet();

  bool get isEmpty => tags.isEmpty;

  ResidentProfile toggle(String tag) {
    final next = Set<String>.from(tags);
    if (!next.remove(tag)) {
      next.add(tag);
    }
    return ResidentProfile(tags: next, interest: interest);
  }

  ResidentProfile withInterest(int value) {
    return ResidentProfile(tags: tags, interest: value.clamp(0, interestSteps));
  }

  /// The one-line summary the AI screen shows under its title.
  String get summary {
    if (tags.isEmpty) {
      return '프로필 미설정';
    }
    final ordered = availableTags.where(tags.contains);
    return ordered.join(' · ');
  }
}
