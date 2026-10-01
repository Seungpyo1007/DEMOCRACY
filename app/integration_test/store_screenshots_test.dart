// Store screenshots: the real app, live data, one district, the screens a
// listing shows. Run with tool/store_screenshots.sh, never in CI.
import 'package:democracy/src/app/app_router.dart';
import 'package:democracy/src/app/app_routes.dart';
import 'package:democracy/src/app/democracy_app.dart';
import 'package:democracy/src/app/live_data.dart';
import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/core/auth/address_state.dart';
import 'package:democracy/src/core/network/bff_config.dart';
import 'package:democracy/src/core/network/retry_policy.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _district = DistrictRef(
  id: String.fromEnvironment('SHOT_DISTRICT_ID'),
  displayName: String.fromEnvironment('SHOT_DISTRICT_NAME'),
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('store screenshots', (tester) async {
    final config = BffConfig.fromEnvironment();
    expect(config, isNotNull, reason: 'Run with --dart-define-from-file.');
    expect(_district.id, isNotEmpty, reason: 'Pass SHOT_DISTRICT_ID.');

    final container = ProviderContainer(
      retry: appRetry,
      overrides: liveDataOverrides(config),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const DemocracyApp(),
      ),
    );
    await _settle(tester);
    container
        .read(addressControllerProvider.notifier)
        .continueReadOnly(district: _district);
    await _settle(tester);

    if (defaultTargetPlatform == TargetPlatform.android) {
      await binding.convertFlutterSurfaceToImage();
    }
    final platform = defaultTargetPlatform == TargetPlatform.iOS
        ? 'ios'
        : 'android';
    final router = container.read(appRouterProvider);

    var n = 0;
    Future<void> shot(String route, String name) async {
      router.go(route);
      await _settle(tester, seconds: 6);
      n += 1;
      await binding.takeScreenshot(
        '$platform/${n.toString().padLeft(2, '0')}-$name',
      );
    }

    await shot(AppRoutes.home, 'home');
    await shot(AppRoutes.tracker, 'pledges');
    await shot(AppRoutes.history, 'history');
    await shot(AppRoutes.results, 'results');
    await shot(AppRoutes.aiDirection, 'direction');
  });
}

/// Real network and real motion: pump frames for a while rather than wait
/// for a settle that a live screen may never reach.
Future<void> _settle(WidgetTester tester, {int seconds = 3}) async {
  for (var i = 0; i < seconds * 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
