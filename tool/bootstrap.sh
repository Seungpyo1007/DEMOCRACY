#!/usr/bin/env bash
#
# The macOS and Linux counterpart to bootstrap.ps1.
#
# It does not run `flutter create`: the Android and iOS projects are committed,
# so there is nothing to generate. What it does is enforce the same toolchain
# pin and run the same verification chain, plus the CocoaPods and iOS build
# steps that only exist on macOS.

set -euo pipefail

EXPECTED_FLUTTER="3.44.8"
EXPECTED_DART="3.12.2"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(dirname "$script_dir")"
app_root="$repo_root/app"

if [ ! -d "$app_root" ]; then
  echo "App scaffold not found: $app_root" >&2
  exit 1
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter is not on PATH. Install Flutter $EXPECTED_FLUTTER first." >&2
  exit 1
fi

cd "$app_root"

# Same guard as bootstrap.ps1. A drifting toolchain fails here rather than
# producing a green run nobody else can reproduce. Parsed with sed because
# macOS ships neither jq nor a guaranteed python3.
version_json="$(flutter --version --machine | tr -d '\n')"

read_field() {
  printf '%s' "$version_json" |
    sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p"
}

framework_version="$(read_field frameworkVersion)"
dart_version="$(read_field dartSdkVersion)"

if [ "$framework_version" != "$EXPECTED_FLUTTER" ]; then
  echo "Expected Flutter $EXPECTED_FLUTTER, found ${framework_version:-unknown}." >&2
  exit 1
fi

case "$dart_version" in
  "$EXPECTED_DART"*) ;;
  *)
    echo "Expected Dart $EXPECTED_DART, found ${dart_version:-unknown}." >&2
    exit 1
    ;;
esac

echo "Toolchain: Flutter $framework_version / Dart $dart_version"

flutter pub get
dart format lib test
flutter analyze
flutter test

# The iOS build is the whole reason a Mac is needed, so it runs automatically
# rather than waiting to be remembered.
if [ "$(uname -s)" = "Darwin" ]; then
  if [ ! -d ios ]; then
    echo "No ios/ directory; skipping the iOS steps." >&2
  else
    # CocoaPods is conditional, not mandatory. Running `pod install`
    # unconditionally aborted the script before it ever reached the build,
    # because no Podfile existed to install from.
    #
    # The first version of this comment predicted a Podfile would appear as
    # soon as a plugin with iOS platform code was added. Three of them were
    # added -- the Liquid Glass packages -- and none did: Flutter resolved
    # them through Swift Package Manager instead, which needs no Podfile and
    # no pod install. The guard is still right, for a wider reason than the
    # one it was written for. Only a plugin that is CocoaPods-only will bring
    # a Podfile back, and this branch is waiting if one does.
    if [ -f ios/Podfile ]; then
      if ! command -v pod >/dev/null 2>&1; then
        echo "ios/Podfile exists but CocoaPods is not installed." >&2
        echo "Run 'brew install cocoapods', then re-run this script." >&2
        exit 1
      fi
      ( cd ios && pod install )
    else
      echo "No ios/Podfile: no plugin needs CocoaPods. Skipping pod install."
    fi

    flutter build ios --no-codesign
  fi
else
  echo "Not macOS: skipping CocoaPods and the iOS build."
fi

echo 'Flutter scaffold and baseline verification completed.'
