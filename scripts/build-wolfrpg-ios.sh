#!/usr/bin/env bash
# Builds EverPlay's WOLF RPG Editor engine (Engines/WolfRPG) and the libraries it uses as static
# libraries for iPhone (arm64, iOS 17): SDL2 and SDL2_ttf with its bundled FreeType.
# scripts/package-wolfrpg-framework.py then links them into WolfRPG.framework.
#
#   scripts/build-wolfrpg-ios.sh     → build/wolfrpg-ios/{prefix,engine}
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/build/wolfrpg-ios"
PREFIX="$WORK/prefix"
MIN_IOS=17.0
SDL_VERSION=2.28.5
SDL_TTF_VERSION=2.22.0
mkdir -p "$WORK"

ios_cmake() {
  cmake -G Ninja -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphoneos -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=$MIN_IOS -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_PREFIX_PATH="$PREFIX" -DCMAKE_FIND_ROOT_PATH="$PREFIX" \
    -DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 "$@"  # CMake 4 refuses SDL_ttf's FreeType (cmake_minimum_required 2.8)
}

if [ ! -f "$PREFIX/lib/cmake/SDL2/SDL2Config.cmake" ]; then
  curl -sSfL "https://github.com/libsdl-org/SDL/releases/download/release-$SDL_VERSION/SDL2-$SDL_VERSION.tar.gz" | tar xz -C "$WORK"
  ios_cmake -S "$WORK/SDL2-$SDL_VERSION" -B "$WORK/sdl2-build" -DSDL_SHARED=OFF -DSDL_STATIC=ON -DSDL_TEST=OFF \
    -DCMAKE_C_FLAGS=-Wno-declaration-after-statement
  cmake --build "$WORK/sdl2-build"
  cmake --install "$WORK/sdl2-build"
fi

if [ ! -f "$PREFIX/lib/cmake/SDL2_ttf/SDL2_ttfConfig.cmake" ]; then
  # The release archive carries FreeType (and HarfBuzz, which is left out) in external/.
  curl -sSfL "https://github.com/libsdl-org/SDL_ttf/releases/download/release-$SDL_TTF_VERSION/SDL2_ttf-$SDL_TTF_VERSION.tar.gz" | tar xz -C "$WORK"
  ios_cmake -S "$WORK/SDL2_ttf-$SDL_TTF_VERSION" -B "$WORK/ttf-build" -DBUILD_SHARED_LIBS=OFF -DSDL2TTF_VENDORED=ON \
    -DSDL2TTF_HARFBUZZ=OFF -DSDL2TTF_SAMPLES=OFF -DSDL2TTF_INSTALL=ON
  cmake --build "$WORK/ttf-build"
  cmake --install "$WORK/ttf-build"
fi

ios_cmake -S "$ROOT/Engines/WolfRPG" -B "$WORK/engine" -DWOLF_TOOLS=OFF -DWOLF_TESTS=OFF -DWOLF_SDL=ON
cmake --build "$WORK/engine"
ls -la "$WORK/engine"/*.a "$PREFIX/lib"/*.a
