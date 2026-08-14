import 'package:democracy/src/app/app_router.dart';
import 'package:democracy/src/design/app_page_background.dart';
import 'package:democracy/src/design/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DemocracyApp extends ConsumerWidget {
  const DemocracyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
