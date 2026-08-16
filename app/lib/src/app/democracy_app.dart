import 'package:democracy/src/app/app_router.dart';
import 'package:democracy/src/core/auth/address_controller.dart';
import 'package:democracy/src/design/app_page_background.dart';
import 'package:democracy/src/design/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DemocracyApp extends ConsumerWidget {
  const DemocracyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The stored session has to be in the controller before the router parses
    // its first route, or a returning resident is redirected to onboarding and
    // only then restored -- landing them one screen behind where they left off.
    // A read from the Keychain is a frame or two, so the wait is a background,
    // not a spinner; a spinner here would flash on every launch.
    final restored = ref.watch(addressRestoreProvider);
    if (restored.isLoading) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(defaultTargetPlatform),
        builder: AppPageBackground.builder,
        home: const SizedBox.shrink(),
      );
    }

    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'DEMOCRACY',
      debugShowCheckedModeBanner: false,
      // The one place native controls are switched on: a real iOS process,
      // where a platform view has something to embed.
      theme: AppTheme.light(
        defaultTargetPlatform,
        nativeControls: defaultTargetPlatform == TargetPlatform.iOS,
      ),
      builder: AppPageBackground.builder,
      routerConfig: router,
    );
  }
}
