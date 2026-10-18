import 'package:democracy/src/features/interests/domain/interest_catalog.dart';

/// What the resident told us about themselves, for match analysis.
///
/// Every field is optional by design. The guide marks this step
/// `프로필 (AI 분석용 · 선택)`, and the address gate must not become a
/// personal-data gate: a resident who skips all of it still gets the whole
/// read-only app.
///
/// Two kinds of answer, kept apart because the match uses them differently:
/// [context] says who is asking (자영업, 1인 가구) and is read as background
/// only; [topics] are the policy interests the score is broken down by.
class ResidentProfile {
  const ResidentProfile({
    this.context = const {},
    this.topics = const [],
    this.interest = 2,
  });

  /// The old single list, which held both kinds of chip
  /// (`{'30대', '부동산', '청년'}`): the context chips stay context, the
  /// policy chips are mapped onto the taxonomy ([legacyInterestIds]).
  factory ResidentProfile.fromLegacyTags(
    Iterable<String> tags, {
    int interest = 2,
  }) {
    return ResidentProfile(
      context: {
        for (final tag in tags)
          if (contextTags.contains(tag)) tag,
      },
      topics: migrateInterestIds(tags).take(maxTopics).toList(),
      interest: interest.clamp(0, interestSteps),
    );
  }

  /// The chips that describe the reader rather than a policy area.
  static const contextTags = <String>['30대', '자영업', '1인 가구'];

  /// The most interests one profile holds.
  ///
  /// The on-device match scores every interest as its own axis, from a small
  /// context window shared with up to 55 pledge and bill titles; past five
  /// the answer gets long enough that the model starts dropping axes or
  /// cutting reasons short. It is also the size of the old list's policy
  /// chips, so nobody's earlier choice is cut by the migration.
  static const maxTopics = 5;

  /// `Slider(divisions: 4)` -- five stops, not a continuum.
  static const interestSteps = 4;

  static const _interestLabels = ['매우 낮음', '낮음', '보통', '높음', '매우 높음'];

  final Set<String> context;

  /// [Interest] ids, in catalog order, at most [maxTopics].
  final List<String> topics;

  /// 0..[interestSteps].
  final int interest;

  String get interestLabel => _interestLabels[interest.clamp(0, interestSteps)];

  /// The picked interests, resolved.
  List<Interest> get interests => [
    for (final id in topics) ?InterestCatalog.find(id),
  ];

  bool get isEmpty => context.isEmpty && topics.isEmpty;

  ResidentProfile toggleContext(String tag) {
    final next = Set<String>.from(context);
    if (!next.remove(tag)) {
      next.add(tag);
    }
    return copyWith(context: next);
  }

  /// Replaces the interests, cleaned up and cut to [maxTopics].
  ResidentProfile withTopics(Iterable<String> ids) =>
      copyWith(topics: InterestCatalog.normalise(ids).take(maxTopics).toList());

  ResidentProfile withoutTopic(String id) => copyWith(
    topics: [
      for (final t in topics)
        if (t != id) t,
    ],
  );

  ResidentProfile withInterest(int value) =>
      copyWith(interest: value.clamp(0, interestSteps));

  ResidentProfile copyWith({
    Set<String>? context,
    List<String>? topics,
    int? interest,
  }) {
    return ResidentProfile(
      context: Set.unmodifiable(context ?? this.context),
      topics: List.unmodifiable(topics ?? this.topics),
      interest: interest ?? this.interest,
    );
  }

  /// The one-line summary the AI screen shows under its title: who is
  /// asking, then what about.
  String get summary {
    if (isEmpty) {
      return '프로필 미설정';
    }
    return [
      ...contextTags.where(context.contains),
      for (final interest in interests) interest.label,
    ].join(' · ');
  }

  /// What is kept on the device.
  Map<String, Object?> toJson() => {
    'version': 2,
    'context': [...contextTags.where(context.contains)],
    'topics': topics,
    'interest': interest,
  };

  /// Reads back what [toJson] wrote, or the single `tags` list an older
  /// build would have kept. Anything unreadable is left out rather than
  /// failing: losing one chip is better than losing the profile.
  static ResidentProfile fromJson(Map<String, Object?> json) {
    final rawInterest = json['interest'];
    final interest = rawInterest is int ? rawInterest : 2;
    List<String> strings(Object? raw) =>
        raw is List ? raw.whereType<String>().toList() : const [];

    if (json['version'] != 2 && json.containsKey('tags')) {
      return ResidentProfile.fromLegacyTags(
        strings(json['tags']),
        interest: interest,
      );
    }
    return ResidentProfile(
      context: {
        for (final tag in strings(json['context']))
          if (contextTags.contains(tag)) tag,
      },
      topics: migrateInterestIds(
        strings(json['topics']),
      ).take(maxTopics).toList(),
    ).withInterest(interest);
  }
}
