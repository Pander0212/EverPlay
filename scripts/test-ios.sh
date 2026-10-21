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
  if [[ -n "${simulator_id:-}" ]]; then
    # App-process stdout is not reliably forwarded by UI tests. Keep only our
    # fixed lifecycle messages (no game content, URLs or saved data).
    xcrun simctl spawn "$simulator_id" log show --last 15m --style compact \
      --predicate 'subsystem == "app.everplay.player" AND category == "runtime"' \
      > artifacts/runtime.log 2>&1 || true
    tail -n 100 artifacts/runtime.log
  fi
  if [[ -n "${result_path:-}" && -d "$result_path" ]]; then
    xcrun xcresulttool export attachments --path "$result_path" --output-path "$attachment_path" \
      > artifacts/attachment-export.log 2>&1 || true
  fi
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
# Compile all application and test targets before spending time booting a device.
phase=ios-build
xcodebuild build-for-testing -project EverPlay.xcodeproj -scheme EverPlay \
  -destination "platform=iOS Simulator,id=$simulator_id" -destination-timeout 120 \
  -derivedDataPath DerivedData -clonedSourcePackagesDirPath .build/xcode-packages \
  -onlyUsePackageVersionsFromResolvedFile -enableCodeCoverage NO CODE_SIGN_IDENTITY=- \
  2>&1 | tee artifacts/ios-build.log
printf '%s\n' '::notice title=EverPlay CI::iOS application and test-target compilation passed.'
phase=simulator-boot
python3 - "$simulator_id" <<'PYTHON' 2>&1 | tee artifacts/simulator-boot.log
import subprocess, sys
subprocess.run(['xcrun', 'simctl', 'bootstatus', sys.argv[1], '-b'], timeout=600, check=True)
PYTHON
printf '%s\n' '::notice title=EverPlay CI::iPhone simulator boot completed.'
# A new result directory prevents stale test results from being mistaken for a new run.
result_path="$PWD/artifacts/ios-$(date -u +%Y%m%dT%H%M%S).xcresult"
attachment_path="$PWD/artifacts/attachments-$(basename "$result_path" .xcresult)"
phase=ios-build-test
xcodebuild test-without-building -project EverPlay.xcodeproj -scheme EverPlay \
  -destination "platform=iOS Simulator,id=$simulator_id" -destination-timeout 120 \
  -derivedDataPath DerivedData -clonedSourcePackagesDirPath .build/xcode-packages \
  -onlyUsePackageVersionsFromResolvedFile -resultBundlePath "$result_path" \
  -parallel-testing-enabled NO -test-timeouts-enabled YES \
  -enableCodeCoverage NO -collect-test-diagnostics never \
  -default-test-execution-time-allowance 300 -maximum-test-execution-time-allowance 300 \
  CODE_SIGN_IDENTITY=- \
  2>&1 | tee artifacts/ios-build-test.log
python3 scripts/verify-ios-tests.py artifacts/ios-build-test.log
# Standalone screenshots let the owner inspect actual simulator UI without a local Mac.
if ! xcrun xcresulttool export attachments --path "$result_path" --output-path "$attachment_path" \
    > artifacts/attachment-export.log 2>&1; then
  printf '%s\n' '::warning title=Screenshot export::Standalone attachments could not be exported; the original xcresult is retained.'
fi
