#!/usr/bin/env bash
# Run UIKit diagnostic tests on one explicitly selected simulator (requires XcodeGen).
set -euo pipefail
simulator=${1:?usage: test-ios-diagnostics.sh <simulator-udid>}
root=$(cd "$(dirname "$0")/.." && pwd)
xcodegen generate --spec "$root/Tests/iOS/project.yml"
xcrun simctl bootstatus "$simulator" -b
xcodebuild -project "$root/Tests/iOS/BugKitDiagnostics.xcodeproj" -scheme BugKitDiagnostics \
  -destination "platform=iOS Simulator,id=$simulator" -derivedDataPath "$root/DerivedData/BugKitDiagnostics" \
  -parallel-testing-enabled NO test
