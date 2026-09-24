import 'package:democracy/src/core/network/not_available.dart';
import 'package:democracy/src/core/provenance/source_metadata.dart';
import 'package:democracy/src/design/app_theme.dart';
import 'package:democracy/src/features/shared/presentation/async_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, Object error) {
    return tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(TargetPlatform.android),
        home: Scaffold(
          body: AsyncSection<int>(
            value: AsyncValue.error(error, StackTrace.empty),
            builder: (context, data) => Text('$data'),
            onRetry: () {},
          ),
        ),
      ),
    );
  }

  testWidgets('data not ready says 준비 중 and offers no retry', (tester) async {
    await pump(tester, const NotAvailableException('pledges'));

    expect(find.text('아직 준비 중인 자료입니다.'), findsOneWidget);
    expect(find.text('다시 시도'), findsNothing);
  });

  testWidgets('a failed fetch offers a retry', (tester) async {
    await pump(tester, Exception('offline'));

    expect(find.text('내용을 불러오지 못했습니다.'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
  });

  testWidgets('an unsourced payload is named as such', (tester) async {
    await pump(
      tester,
      const MissingSourceException(field: 'x', reason: 'none'),
    );

    expect(find.text('출처가 확인되지 않아 표시하지 않습니다.'), findsOneWidget);
  });
}
