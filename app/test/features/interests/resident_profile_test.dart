import 'package:democracy/src/features/ai_match/application/match_providers.dart';
import 'package:democracy/src/features/interests/domain/interest_catalog.dart';
import 'package:democracy/src/features/onboarding/application/onboarding_providers.dart';
import 'package:democracy/src/features/onboarding/data/resident_profile_store.dart';
import 'package:democracy/src/features/onboarding/domain/resident_profile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('migrating the old flat list', () {
    test('every old policy chip lands on a real interest', () {
      for (final MapEntry(:key, :value) in legacyInterestIds.entries) {
        expect(InterestCatalog.find(value), isNotNull, reason: key);
      }
    });

    test('keeps every chip a reader could have had', () {
      // The whole of the old list, every chip on.
      final profile = ResidentProfile.fromLegacyTags(const {
        '30대',
        '자영업',
        '1인 가구',
        '부동산',
        '세금',
        '복지',
        '교육',
        '청년',
      });

      expect(profile.context, {'30대', '자영업', '1인 가구'});
      expect(profile.topics, [
        'housing.market',
        'education',
        'economy.tax',
        'welfare',
        'youth',
      ]);
      expect(profile.topics, hasLength(ResidentProfile.maxTopics));
      expect(profile.interests.map((i) => i.label), [
        '부동산',
        '교육',
        '세금',
        '복지',
        '청년',
      ]);
    });

    test('reads a stored old-shape record', () {
      final profile = ResidentProfile.fromJson({
        'tags': ['세금', '자영업', '없어진 칩'],
        'interest': 4,
      });
      expect(profile.context, {'자영업'});
      expect(profile.topics, ['economy.tax']);
      expect(profile.interest, 4);
    });

    test('maps an old label even inside a new-shape record', () {
      final profile = ResidentProfile.fromJson({
        'version': 2,
        'context': ['1인 가구'],
        'topics': ['청년', 'transport.bus', 'no.such.id'],
        'interest': 1,
      });
      expect(profile.topics, ['transport.bus', 'youth']);
    });

    test('round-trips through its own JSON', () {
      const original = ResidentProfile(
        context: {'30대'},
        topics: ['transport.rail', 'housing.rent'],
        interest: 3,
      );
      final back = ResidentProfile.fromJson(original.toJson());
      expect(back.context, original.context);
      expect(back.topics, original.topics);
      expect(back.interest, original.interest);
    });
  });

  group('the limit', () {
    test('withTopics keeps catalog order and cuts at the maximum', () {
      final profile = const ResidentProfile().withTopics([
        'pets',
        'transport.bus',
        'transport.bus',
        'housing.rent',
        'youth',
        'welfare',
        'education',
        'digital.ai',
      ]);
      expect(profile.topics, hasLength(ResidentProfile.maxTopics));
      expect(profile.topics, [
        'transport.bus',
        'housing.rent',
        'education',
        'welfare',
        'youth',
      ]);
    });

    test('a stored record over the limit is cut on the way in', () {
      final profile = ResidentProfile.fromJson({
        'version': 2,
        'topics': [for (final i in InterestCatalog.all.take(9)) i.id],
      });
      expect(profile.topics, hasLength(ResidentProfile.maxTopics));
    });
  });

  group('the match query', () {
    test('names the axes by label and carries the keywords', () {
      const profile = ResidentProfile(
        context: {'자영업'},
        topics: ['housing.rent', 'youth'],
      );
      final query = matchQueryFor(profile);
      expect(query.interests, ['전월세', '청년']);
      expect(query.context, ['자영업']);
      expect(query.relatedTerms['전월세'], containsAll(['전세', '월세']));
      // A whole 분야 lists its topics for the model.
      expect(query.relatedTerms['청년'], contains('청년 주거'));
      expect(query.matchTerms, containsAll(['전세', '청년 일자리']));
    });

    test('compares by value, so an unrelated change does not rerun it', () {
      const a = ResidentProfile(topics: ['housing.rent'], interest: 1);
      final b = a.withInterest(4);
      expect(matchQueryFor(a), matchQueryFor(b));
      expect(matchQueryFor(a).hashCode, matchQueryFor(b).hashCode);
      expect(
        matchQueryFor(a),
        isNot(matchQueryFor(a.withTopics(['housing.public']))),
      );
    });
  });

  group('kept on the device', () {
    test('restores what was stored, and stores each change', () async {
      final store = InMemoryResidentProfileStore({
        'tags': ['부동산', '30대'],
      });
      final container = ProviderContainer(
        overrides: [residentProfileStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);

      container.read(residentProfileProvider);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(residentProfileProvider).topics, [
        'housing.market',
      ]);
      expect(container.read(residentProfileProvider).context, {'30대'});

      container.read(residentProfileProvider.notifier).setTopics([
        'housing.market',
        'transport.bus',
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(store.stored?['version'], 2);
      expect(store.stored?['topics'], ['transport.bus', 'housing.market']);
    });

    test('a change made before the read finishes is not overwritten', () async {
      final store = InMemoryResidentProfileStore({
        'version': 2,
        'topics': ['welfare'],
      });
      final container = ProviderContainer(
        overrides: [residentProfileStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);

      container.read(residentProfileProvider.notifier).setTopics(['pets']);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(residentProfileProvider).topics, ['pets']);
    });
  });
}
