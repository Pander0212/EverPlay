#!/usr/bin/env bash
# Builds mkxp-z (RPG Maker XP, VX and VX Ace; GPL-2.0+) and the libraries it needs as static
# libraries for iPhone (arm64, iOS 17), following mkxp-z's own macOS dependency list
# (macos/Dependencies/common.make), from the mkxp-z project's forks where it uses them.
#
#   scripts/build-mkxp-ios.sh deps     libraries into build/mkxp-ios/prefix
#   scripts/build-mkxp-ios.sh ruby     Ruby (mkxp-z's 3.1 branch) into the same prefix
#
# Each step logs to build/mkxp-ios/logs/<name>.log and skips libraries already installed.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/build/mkxp-ios"
SRC="$WORK/src"
PREFIX="$WORK/prefix"
LOGS="$WORK/logs"
mkdir -p "$SRC" "$PREFIX/lib" "$PREFIX/include" "$LOGS"

MIN_IOS=17.0
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
CC_IOS="$(xcrun --sdk iphoneos -f clang)"
CXX_IOS="$(xcrun --sdk iphoneos -f clang++)"
ARCH_FLAGS="-arch arm64 -isysroot $SDK -miphoneos-version-min=$MIN_IOS"
export IPHONEOS_DEPLOYMENT_TARGET=$MIN_IOS
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
NPROC="$(sysctl -n hw.ncpu)"

# Repository and branch (pinned where mkxp-z pins one); macOS ships bash 3, without maps.
repo() {
  case "$1" in
    ogg) echo "https://github.com/mkxp-z/ogg" ;;
    vorbis) echo "https://github.com/mkxp-z/vorbis" ;;
    theora) echo "https://github.com/xiph/theora" ;;
    uchardet) echo "https://github.com/mkxp-z/uchardet" ;;
    libpng) echo "https://github.com/mkxp-z/libpng" ;;
    pixman) echo "https://github.com/mkxp-z/pixman" ;;
    physfs) echo "https://github.com/mkxp-z/physfs release-3.2.0" ;;
    sdl2) echo "https://github.com/mkxp-z/SDL mkxp-z" ;;
    sdl2_image) echo "https://github.com/mkxp-z/SDL_image mkxp-z" ;;
    sdl_sound) echo "https://github.com/mkxp-z/SDL_sound git" ;;
    freetype) echo "https://github.com/mkxp-z/freetype2" ;;
    sdl2_ttf) echo "https://github.com/mkxp-z/SDL_ttf mkxp-z" ;;
    openal) echo "https://github.com/mkxp-z/openal-soft" ;;
    ruby) echo "https://github.com/mkxp-z/ruby mkxp-z-3.1.3" ;;
    *) echo "unknown $1" >&2; return 1 ;;
  esac
}

fetch() {
  local name="$1" url branch
  read -r url branch <<< "$(repo "$name")"
  [ -d "$SRC/$name/.git" ] && return
  if [ -n "${branch:-}" ]; then
    git clone -q --depth 1 --single-branch -b "$branch" "$url" "$SRC/$name"
  else
    git clone -q --depth 1 "$url" "$SRC/$name"
  fi
}

# Runs a build step once (marker file), logging its output; prints the log tail on failure.
step() {
  local name="$1"; shift
  [ -f "$WORK/done-$name" ] && { echo "== $name (already built)"; return; }
  echo "== $name"
  fetch "$name"
  if ! ( cd "$SRC/$name" && "$@" ) > "$LOGS/$name.log" 2>&1; then
    tail -n 80 "$LOGS/$name.log"
    echo "::error::$name failed"
    exit 1
  fi
  touch "$WORK/done-$name"
}

cmake_ios() {
  rm -rf cmakebuild && mkdir cmakebuild && cd cmakebuild
  cmake .. -G Ninja -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphoneos -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=$MIN_IOS -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_PREFIX_PATH="$PREFIX" -DCMAKE_FIND_ROOT_PATH="$PREFIX" \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 "$@"
  cmake --build . -j "$NPROC"
  cmake --install .
}

configure_ios() {
  [ -x configure ] || { if [ -x autogen.sh ]; then NOCONFIGURE=1 ./autogen.sh; else autoreconf -fi; fi; }
  # Old Xiph configure scripts add a linker option for PowerPC-era macOS that ld rejects.
  sed -i '' 's/-force_cpusubtype_ALL//g' configure
  CC="$CC_IOS" CXX="$CXX_IOS" CFLAGS="$ARCH_FLAGS -O2 -I$PREFIX/include" CXXFLAGS="$ARCH_FLAGS -O2 -I$PREFIX/include" \
    LDFLAGS="$ARCH_FLAGS -L$PREFIX/lib" ./configure --host=aarch64-apple-darwin --prefix="$PREFIX" \
    --enable-static --disable-shared "$@"
  make -j "$NPROC"
  make install
}

deps() {
  step ogg configure_ios
  step vorbis configure_ios --with-ogg="$PREFIX"
  step theora configure_ios --with-ogg="$PREFIX" --disable-examples --disable-spec --disable-doc
  step uchardet cmake_ios -DBUILD_BINARY=OFF
  step libpng cmake_ios -DPNG_SHARED=OFF -DPNG_TESTS=OFF -DPNG_FRAMEWORK=OFF -DPNG_TOOLS=OFF
  step pixman configure_ios --disable-arm-a64-neon --disable-gtk --disable-libpng
  step physfs cmake_ios -DPHYSFS_BUILD_STATIC=ON -DPHYSFS_BUILD_SHARED=OFF -DPHYSFS_BUILD_TEST=OFF -DPHYSFS_BUILD_DOCS=OFF
  step sdl2 cmake_ios -DSDL_SHARED=OFF -DSDL_STATIC=ON -DSDL_TEST=OFF
  step sdl2_image cmake_ios -DSDL2IMAGE_SAMPLES=OFF -DSDL2IMAGE_JPG_SAVE=ON -DSDL2IMAGE_PNG_SAVE=ON \
    -DSDL2IMAGE_PNG_SHARED=OFF -DSDL2IMAGE_JPG_SHARED=OFF -DSDL2IMAGE_BACKEND_IMAGEIO=OFF -DSDL2IMAGE_VENDORED=OFF
  step sdl_sound cmake_ios -DSDLSOUND_BUILD_SHARED=OFF -DSDLSOUND_BUILD_TEST=OFF -DSDLSOUND_DECODER_COREAUDIO=OFF
  step freetype cmake_ios -DFT_DISABLE_HARFBUZZ=ON -DFT_DISABLE_BROTLI=ON -DFT_DISABLE_BZIP2=ON -DFT_REQUIRE_PNG=OFF -DFT_DISABLE_PNG=ON
  step sdl2_ttf cmake_ios -DSDL2TTF_SAMPLES=OFF -DSDL2TTF_VENDORED=OFF -DSDL2TTF_HARFBUZZ=OFF
  step openal cmake_ios -DLIBTYPE=STATIC -DALSOFT_EXAMPLES=OFF -DALSOFT_UTILS=OFF -DALSOFT_INSTALL_EXAMPLES=OFF \
    -DALSOFT_INSTALL_UTILS=OFF -DALSOFT_BACKEND_PORTAUDIO=OFF -DALSOFT_BACKEND_PULSEAUDIO=OFF
  ls -la "$PREFIX/lib"
}

case "${1:-deps}" in
  deps) deps ;;
  *) echo "unknown step $1"; exit 2 ;;
esac
