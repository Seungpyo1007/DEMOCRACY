#!/usr/bin/env bash
# Store screenshots from the real app with live data, into app/build/screenshots/.
#
#   tool/store_screenshots.sh ios <simulator id>       # iPhone 6.9" (1320x2868) for App Store
#   tool/store_screenshots.sh android <emulator id>    # set to 1080x2160 for Play (2:1 at most)
#
# Needs app/dart_defines.json (the live BFF). The district is 서울 종로구 unless
# SHOT_DISTRICT_ID / SHOT_DISTRICT_NAME are set. Before running:
#   iOS:     xcrun simctl status_bar <id> override --time 9:41 --batteryLevel 100 --batteryState charged
#   Android: adb shell wm size 1080x2160, and System UI demo mode for a clean status bar;
#            adb shell wm size reset afterwards.
set -euo pipefail
platform="${1:?ios|android}"
device="${2:?device id}"
cd "$(dirname "$0")/../app"
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/store_screenshots_test.dart \
  -d "$device" \
  --dart-define-from-file=dart_defines.json \
  --dart-define=SHOT_DISTRICT_ID="${SHOT_DISTRICT_ID:-nec-0bd970c0}" \
  --dart-define=SHOT_DISTRICT_NAME="${SHOT_DISTRICT_NAME:-서울 종로구}"
ls "build/screenshots/$platform"
