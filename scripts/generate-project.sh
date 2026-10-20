#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/package-demo.py
if [[ -n "${XCODEGEN_BIN:-}" ]]; then
  generator="$XCODEGEN_BIN"
else
  tool="$PWD/.build-tools/XcodeGen"
  if [[ ! -d "$tool/.git" ]]; then
    git clone --depth 1 --branch 2.44.1 https://github.com/yonaskolb/XcodeGen.git "$tool"
  fi
  [[ "$(git -C "$tool" rev-parse HEAD)" == "21ac9944b0ab546a07422dbed86f33dd2ebd76f8" ]] || { echo 'Unexpected XcodeGen revision' >&2; exit 1; }
  export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
  export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
  swift build --package-path "$tool" --cache-path "$PWD/.build/cache" --config-path "$PWD/.build/config" \
    --security-path "$PWD/.build/security" --force-resolved-versions -c release --product xcodegen --jobs "${EVERPLAY_BUILD_JOBS:-4}"
  generator="$tool/.build/release/xcodegen"
fi
[[ "$($generator --version)" == *"2.44.1"* ]] || { echo 'XcodeGen 2.44.1 is required' >&2; exit 1; }
"$generator" generate --spec project.yml
# Xcode resolves local package dependencies using its workspace lock file.
mkdir -p EverPlay.xcodeproj/project.xcworkspace/xcshareddata/swiftpm
cp Package.resolved EverPlay.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
