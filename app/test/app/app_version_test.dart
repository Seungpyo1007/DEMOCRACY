import 'dart:io';

import 'package:democracy/src/app/app_version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the version shown in the app matches pubspec.yaml', () {
    final line = File(
      'pubspec.yaml',
    ).readAsLinesSync().firstWhere((l) => l.startsWith('version:'));
    expect(line.trim(), 'version: $appVersion+$appBuild');
  });
}
