#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p artifacts
command -v xcodebuild >/dev/null || { echo 'iOS compilation requires macOS with Xcode.' >&2; exit 1; }
xcodebuild -version
bash scripts/generate-project.sh
bash scripts/test-core.sh | tee artifacts/swift-tests.log
xcodebuild -resolvePackageDependencies -project EverPlay.xcodeproj -scheme EverPlay \
  -clonedSourcePackagesDirPath .build/xcode-packages -onlyUsePackageVersionsFromResolvedFile \
  | tee artifacts/ios-resolve.log
simulator_id="$(xcrun simctl list devices available -j | python3 -c '
import json,sys
items=json.load(sys.stdin)["devices"]
phones=[device["udid"] for runtime,devices in items.items() if "iOS" in runtime for device in devices if device.get("isAvailable") and "iPhone" in device["name"]]
if not phones: sys.exit("No available iPhone simulator installed")
print(phones[0])
')"
# A new result directory prevents stale test results from being mistaken for a new run.
result_path="$PWD/artifacts/ios-$(date -u +%Y%m%dT%H%M%S).xcresult"
xcodebuild test -project EverPlay.xcodeproj -scheme EverPlay \
  -destination "platform=iOS Simulator,id=$simulator_id" \
  -derivedDataPath DerivedData -clonedSourcePackagesDirPath .build/xcode-packages \
  -onlyUsePackageVersionsFromResolvedFile -resultBundlePath "$result_path" \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO \
  | tee artifacts/ios-build-test.log
