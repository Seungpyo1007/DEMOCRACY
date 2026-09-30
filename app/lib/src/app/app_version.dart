/// The version shown in the app, from `version:` in pubspec.yaml.
///
/// A constant rather than a platform lookup: no plugin, and the same value in
/// tests, goldens and every build. `test/app/app_version_test.dart` fails when
/// it drifts from pubspec.yaml, so a release bumps both.
const appVersion = '0.2.0';

/// The build number after `+` in pubspec.yaml: Android's versionCode and iOS's
/// CFBundleVersion. Play requires it to rise with every upload.
const appBuild = 2;
