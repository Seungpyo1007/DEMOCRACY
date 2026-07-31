import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/core/auth/address_state.dart';
import 'package:democracy/src/design/app_theme.dart';
import 'package:democracy/src/features/reviews/application/review_providers.dart';
import 'package:democracy/src/features/reviews/domain/resident_review.dart';
import 'package:democracy/src/features/reviews/domain/review_repository.dart';
import 'package:democracy/src/features/reviews/presentation/resident_review_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _district = DistrictRef(id: 'fixture-a', displayName: '가상 지역구');

class FakeBoardRepository implements ReviewRepository {
  const FakeBoardRepository();

  @override
  Future<ReviewBoard> loadBoard(String districtId) async {
    return ReviewBoard.fromJson({
      'summary': {
        'average': 3.8,
        'respondents': 412,
        'axes': [
          {'label': '소통', 'score': 4.1},
        ],
      },
      'reviews': [
        {
          'id': 'fixture-review-1',
          'author': '익명 주민',
          'score': 4,
          'verifiedResident': true,
          'body': '가상 평가 본문입니다.',
        },
      ],
    });
  }
}

void main() {
  Future<ProviderContainer> pumpReviews(
    WidgetTester tester, {
    required bool verified,
  }) async {
    final container = ProviderContainer(
      overrides: [
        reviewRepositoryProvider.overrideWithValue(const FakeBoardRepository()),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(addressControllerProvider.notifier);
    if (verified) {
      controller.acceptVerification(
        district: _district,
        proof: ResidencyVerificationProof(
          opaqueToken: 'fixture-opaque-token',
          verifiedAt: DateTime.utc(2026, 7, 30),
        ),
      );
    } else {
      controller.continueReadOnly(district: _district);
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(TargetPlatform.android),
          home: const ResidentReviewScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('an unverified resident can still read everything', (
    tester,
  ) async {
    await pumpReviews(tester, verified: false);

    expect(find.text('3.8'), findsOneWidget);
    expect(find.text('주민 412명 평가'), findsOneWidget);
    expect(find.text('가상 평가 본문입니다.'), findsOneWidget);
  });

  testWidgets('an unverified write is stopped and explained', (tester) async {
    await pumpReviews(tester, verified: false);

    await tester.tap(find.text('평가 작성하기'));
    await tester.pumpAndSettle();

    expect(find.text('주민 인증이 필요합니다'), findsOneWidget);
    expect(find.textContaining('작성 화면은'), findsNothing);
  });

  testWidgets('a verified write proceeds without the prompt', (tester) async {
    await pumpReviews(tester, verified: true);

    await tester.tap(find.text('평가 작성하기'));
    await tester.pumpAndSettle();

    expect(find.text('주민 인증이 필요합니다'), findsNothing);
    expect(find.textContaining('작성 화면은'), findsOneWidget);
  });
}
