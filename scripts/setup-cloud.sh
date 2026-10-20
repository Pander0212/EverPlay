#!/usr/bin/env bash
# Reproduce the tested Linux toolchain without changing dependency declarations or lockfiles.
set -euo pipefail
cd "$(dirname "$0")/.."
tools_root="${EVERPLAY_TOOLS_ROOT:-/workspace/everplay-tools}"
mkdir -p "$tools_root/cache/npm"
if ! command -v swift >/dev/null; then
  if [[ ! -x "$tools_root/swift/usr/bin/swift" ]]; then
    [[ "$(uname -s)-$(uname -m)" == "Linux-x86_64" ]] || { echo 'Install Swift 6.0+ for this platform first.' >&2; exit 1; }
    archive="$tools_root/swift-6.0.3-ubuntu24.04.tar.gz"
    curl --fail --location --show-error --retry 2 \
      https://download.swift.org/swift-6.0.3-release/ubuntu2404/swift-6.0.3-RELEASE/swift-6.0.3-RELEASE-ubuntu24.04.tar.gz \
      --output "$archive"
    # Digest of the official artifact whose detached Swift release signature was verified during onboarding.
    printf '%s  %s\n' '33e923609f6d89ee455af0a017ae4941ce16878c4940882cbf6a1656de294e8b' "$archive" | sha256sum --check -
    stage="$(mktemp -d "$tools_root/swift-install.XXXXXX")"
    tar -xzf "$archive" --strip-components=1 -C "$stage"
    "$stage/usr/bin/swift" --version
    [[ ! -e "$tools_root/swift" ]] || { echo 'Incomplete Swift installation exists; inspect it before replacing.' >&2; exit 1; }
    mv "$stage" "$tools_root/swift"
  fi
  export PATH="$tools_root/swift/usr/bin:$PATH"
fi
swift --version
node --version
python3 --version
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
swift build --cache-path "$PWD/.build/cache" --config-path "$PWD/.build/config" \
  --security-path "$PWD/.build/security" --force-resolved-versions --jobs "${EVERPLAY_BUILD_JOBS:-4}"
npm ci --ignore-scripts --cache "$tools_root/cache/npm"
