import 'package:democracy/src/app/democracy_app.dart';
import 'package:democracy/src/app/font_licenses.dart';
import 'package:democracy/src/app/live_data.dart';
import 'package:democracy/src/core/network/bff_config.dart';
import 'package:democracy/src/core/tips/tip_providers.dart';
import 'package:democracy/src/core/tips/tip_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicenses();
  runApp(
    ProviderScope(
      // The one place tips are switched on; everywhere else the store
      // reports them as seen.
      overrides: [
        tipStoreProvider.overrideWithValue(SharedPreferencesTipStore()),
        // Fixtures unless the build was given a BFF with --dart-define.
        ...liveDataOverrides(BffConfig.fromEnvironment()),
      ],
      child: const DemocracyApp(),
    ),
  );
}
