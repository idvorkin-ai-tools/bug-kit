#!/usr/bin/env bash
# Run UIKit diagnostic tests on one explicitly selected simulator (requires XcodeGen). The whole xcodebuild output is
# kept in $BUG_KIT_TEST_LOG (default DerivedData/BugKitDiagnostics/test.log). With xcbeautify installed the console
# shows its readable summary; without it, the raw output. Either way the exit status is xcodebuild's.
set -euo pipefail
simulator=${1:?usage: test-ios-diagnostics.sh <simulator-udid>}
root=$(cd "$(dirname "$0")/.." && pwd)
log=${BUG_KIT_TEST_LOG:-$root/DerivedData/BugKitDiagnostics/test.log}
beautify=${XCBEAUTIFY:-xcbeautify}
mkdir -p "$(dirname "$log")"
xcodegen generate --spec "$root/Tests/iOS/project.yml"
xcrun simctl bootstatus "$simulator" -b
run() {
  xcodebuild -project "$root/Tests/iOS/BugKitDiagnostics.xcodeproj" -scheme BugKitDiagnostics \
    -destination "platform=iOS Simulator,id=$simulator" -derivedDataPath "$root/DerivedData/BugKitDiagnostics" \
    -parallel-testing-enabled NO test
}
if ! command -v "$beautify" >/dev/null 2>&1; then
  echo "xcbeautify not found: raw output (brew install xcbeautify for a summary); log: $log" >&2
  run 2>&1 | tee "$log"
  exit "${PIPESTATUS[0]}"
fi
set +e
# Drain what the beautifier leaves unread, so its early exit can't SIGPIPE tee and xcodebuild.
run 2>&1 | tee "$log" | { "$beautify"; status=$?; cat >/dev/null; exit "$status"; }
statuses=("${PIPESTATUS[@]}")
set -e
if [ "${statuses[2]}" != 0 ]; then
  echo "xcbeautify failed (${statuses[2]}); the raw log is $log" >&2
fi
if [ "${statuses[0]}" != 0 ]; then
  echo "xcodebuild failed (${statuses[0]}); the raw log is $log" >&2
fi
exit "${statuses[0]}"
