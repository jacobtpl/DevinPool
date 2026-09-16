#!/bin/bash
# Build, install and launch the app on a booted iPhone simulator (default: iPhone 17).
set -euo pipefail
cd "$(dirname "$0")/.."
DEVICE="${1:-iPhone 17}"
xcodebuild -project EightBallPool.xcodeproj -scheme EightBallPool \
  -destination "platform=iOS Simulator,name=$DEVICE" \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD" || true
xcrun simctl boot "$DEVICE" 2>/dev/null || true
open -a Simulator
xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/EightBallPool.app
xcrun simctl launch booted pool-ios
