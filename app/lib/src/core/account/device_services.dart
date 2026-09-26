import 'dart:convert';
import 'dart:io';

import 'package:democracy/src/core/adaptive/platform_adaptive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Face ID, Touch ID or the device passcode, to confirm it is still the
/// phone's owner before something that cannot be undone.
///
/// Never proof of residency: a phone's owner is not an address.
class LocalDeviceAuth implements PlatformAdaptiveAuth {
  LocalDeviceAuth([LocalAuthentication? auth])
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> authenticate({required String reason}) async {
    try {
      if (!await _auth.isDeviceSupported()) {
        // Nothing to confirm with; the in-app confirmation still stands.
        return true;
      }
      return await _auth.authenticate(localizedReason: reason);
    } on Object catch (error) {
      debugPrint('Device authentication failed: $error');
      return false;
    }
  }
}

/// Always yes: tests and a build without a device to ask.
class TrustingDeviceAuth implements PlatformAdaptiveAuth {
  const TrustingDeviceAuth();

  @override
  Future<bool> authenticate({required String reason}) async => true;
}

final deviceAuthProvider = Provider<PlatformAdaptiveAuth>(
  (ref) => const TrustingDeviceAuth(),
);

/// Whether risky actions ask the device first. A setting of this phone, not
/// of the account: it is kept here and never sent anywhere.
class DeviceConfirmSetting extends Notifier<bool> {
  static const _key = 'democracy.confirmWithDevice';

  @override
  bool build() {
    _load();
    return true;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getBool(_key);
      if (stored != null && ref.mounted) {
        state = stored;
      }
    } on Object {
      // No preferences in this environment; the default stands.
    }
  }

  Future<void> set({required bool enabled}) async {
    state = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, enabled);
    } on Object {
      // Kept for this run only.
    }
  }
}

final deviceConfirmProvider = NotifierProvider<DeviceConfirmSetting, bool>(
  DeviceConfirmSetting.new,
);

/// Hands an export to the platform's share sheet.
abstract interface class ExportSharer {
  Future<void> share(Map<String, Object?> export);
}

class ShareSheetExporter implements ExportSharer {
  const ShareSheetExporter();

  @override
  Future<void> share(Map<String, Object?> export) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/democracy-내-데이터.json');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(export),
    );
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], subject: 'DEMOCRACY 내 데이터'),
    );
  }
}

final exportSharerProvider = Provider<ExportSharer>(
  (ref) => const ShareSheetExporter(),
);
