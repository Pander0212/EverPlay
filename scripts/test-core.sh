#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v swift >/dev/null && [[ -x /workspace/everplay-tools/swift/usr/bin/swift ]]; then
  export PATH="/workspace/everplay-tools/swift/usr/bin:$PATH"
fi
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
swift test --cache-path "$PWD/.build/cache" --config-path "$PWD/.build/config" \
  --security-path "$PWD/.build/security" --force-resolved-versions --jobs "${EVERPLAY_BUILD_JOBS:-4}" "$@"
