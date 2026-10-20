#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p artifacts
command -v xcodebuild >/dev/null || { echo 'iOS compilation requires macOS with Xcode.' >&2; exit 1; }
phase=environment
report_failure() {
  failure_code=$?
  trap - ERR
  python3 scripts/report-ci-failure.py "$phase" "$failure_code" || true
  exit "$failure_code"
}
trap report_failure ERR
xcodebuild -version 2>&1 | tee artifacts/environment.log
phase=project-generation
bash scripts/generate-project.sh 2>&1 | tee artifacts/project-generation.log
printf '%s\n' '::notice title=EverPlay CI::Project generation passed.'
phase=swift-tests
bash scripts/test-core.sh 2>&1 | tee artifacts/swift-tests.log
printf '%s\n' '::notice title=EverPlay CI::Swift core tests passed on macOS.'
phase=ios-resolve
xcodebuild -resolvePackageDependencies -project EverPlay.xcodeproj -scheme EverPlay \
  -clonedSourcePackagesDirPath .build/xcode-packages -onlyUsePackageVersionsFromResolvedFile \
  2>&1 | tee artifacts/ios-resolve.log
printf '%s\n' '::notice title=EverPlay CI::Xcode package resolution passed.'
phase=simulator-selection
simulator_id="$(xcrun simctl list devices available -j | python3 -c '
import json,sys
items=json.load(sys.stdin)["devices"]
phones=[device["udid"] for runtime,devices in items.items() if "iOS" in runtime for device in devices if device.get("isAvailable") and "iPhone" in device["name"]]
if not phones: sys.exit("No available iPhone simulator installed")
print(phones[0])
')"
# A new result directory prevents stale test results from being mistaken for a new run.
result_path="$PWD/artifacts/ios-$(date -u +%Y%m%dT%H%M%S).xcresult"
phase=ios-build-test
xcodebuild test -project EverPlay.xcodeproj -scheme EverPlay \
  -destination "platform=iOS Simulator,id=$simulator_id" \
  -derivedDataPath DerivedData -clonedSourcePackagesDirPath .build/xcode-packages \
  -onlyUsePackageVersionsFromResolvedFile -resultBundlePath "$result_path" \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO \
  2>&1 | tee artifacts/ios-build-test.log
python3 scripts/verify-ios-tests.py artifacts/ios-build-test.log
