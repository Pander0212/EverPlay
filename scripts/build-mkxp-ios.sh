#!/usr/bin/env bash
# Builds mkxp-z (RPG Maker XP, VX and VX Ace; GPL-2.0+) as a static library for iPhone (arm64,
# iOS 17). mkxp-z's Meson build (dev branch) downloads and builds every library it needs,
# Ruby 3.1 included; scripts/patch-mkxp-ios.py leaves out its macOS-only parts.
#
#   scripts/build-mkxp-ios.sh     → build/mkxp-ios/build/libmkxp-z.a and the libraries it uses
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/build/mkxp-ios"
MKXPZ_COMMIT=37a04d14413454551a7b6aadbb4e93e67168accb  # mkxp-z dev, 2026-10
MIN_IOS=17.0
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
mkdir -p "$WORK"

if [ ! -d "$WORK/mkxp-z/.git" ]; then
  git init -q "$WORK/mkxp-z"
  git -C "$WORK/mkxp-z" fetch -q --depth 1 https://github.com/mkxp-z/mkxp-z "$MKXPZ_COMMIT"
  git -C "$WORK/mkxp-z" checkout -q FETCH_HEAD
  python3 "$ROOT/scripts/patch-mkxp-ios.py" "$WORK/mkxp-z"
fi

# SDL2 from its own CMake build, which knows iOS (the Meson port mkxp-z uses only knows macOS).
PREFIX="$WORK/prefix"
SDL_VERSION=2.28.5
if [ ! -f "$PREFIX/lib/pkgconfig/sdl2.pc" ]; then
  curl -sSfL "https://github.com/libsdl-org/SDL/releases/download/release-$SDL_VERSION/SDL2-$SDL_VERSION.tar.gz" | tar xz -C "$WORK"
  cmake -S "$WORK/SDL2-$SDL_VERSION" -B "$WORK/sdl2-build" -G Ninja -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT=iphoneos -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=$MIN_IOS \
    -DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DSDL_SHARED=OFF -DSDL_STATIC=ON -DSDL_TEST=OFF -DCMAKE_C_FLAGS=-Wno-declaration-after-statement
  cmake --build "$WORK/sdl2-build"
  cmake --install "$WORK/sdl2-build"
fi

target="--target=arm64-apple-ios$MIN_IOS"
cat > "$WORK/ios.txt" <<EOF
[binaries]
c = ['ccache', 'clang', '$target', '-isysroot', '$SDK']
cpp = ['ccache', 'clang++', '$target', '-isysroot', '$SDK']
objc = ['ccache', 'clang', '$target', '-isysroot', '$SDK']
objcpp = ['ccache', 'clang++', '$target', '-isysroot', '$SDK']
ar = 'ar'
strip = 'strip'
cmake = 'cmake'
pkg-config = 'pkg-config'

[properties]
needs_exe_wrapper = true
pkg_config_libdir = ['$PREFIX/lib/pkgconfig']

[cmake]
CMAKE_SYSTEM_NAME = 'iOS'
CMAKE_OSX_SYSROOT = '$SDK'
CMAKE_OSX_ARCHITECTURES = 'arm64'
CMAKE_OSX_DEPLOYMENT_TARGET = '$MIN_IOS'
# CMake makes every iOS executable an app bundle, which the libraries' own tools are not.
CMAKE_MACOSX_BUNDLE = 'OFF'

[host_machine]
system = 'darwin'
subsystem = 'ios'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
EOF

cd "$WORK/mkxp-z"
if [ ! -f "$WORK/build/build.ninja" ]; then
  meson setup "$WORK/build" --cross-file "$WORK/ios.txt" --buildtype release -Db_lto=false \
    -Dgfx_backend=gles -Dangle=disabled -Dopenssl=disabled -Ddefault_library=static -Dsdl_system=enabled
fi
ninja -C "$WORK/build" libmkxp-z.a
ls -la "$WORK/build"/*.a
