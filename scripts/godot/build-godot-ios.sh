#!/usr/bin/env bash
# Builds Godot (official sources at a pinned tag, MIT) for iPhone as Godot<NN>.framework, which
# EverPlay loads with dlopen to play a game's .pck (scripts/godot/everplay_godot.mm).
# Usage: build-godot-ios.sh <version e.g. 4.7.2> <device|simulator> <output folder>
set -euo pipefail

version="$1"
kind="$2"
output="$3"
here="$(cd "$(dirname "$0")" && pwd)"
work="${GODOT_WORK:-build/godot-$version}"
id="$(echo "$version" | cut -d. -f1,2 | tr -d .)"   # 4.7.2 -> 47
name="Godot$id"

if [ ! -d "$work/.git" ]; then
  git init -q "$work"
  git -C "$work" fetch -q --depth 1 https://github.com/godotengine/godot.git "refs/tags/$version-stable"
  git -C "$work" checkout -q FETCH_HEAD
  python3 "$here/patch-godot-ios.py" "$work"
fi

if [ "$kind" = simulator ]; then
  arch="$(uname -m)"; [ "$arch" = x86_64 ] || arch=arm64
  sdk=iphonesimulator; flags=(simulator=yes arch="$arch"); min=-mios-simulator-version-min=17.0
  suffix=".simulator"
else
  arch=arm64; sdk=iphoneos; flags=(arch=arm64); min=-miphoneos-version-min=17.0
  suffix=""
fi

# The compatibility renderer (OpenGL ES 3) for gl_compatibility games and Metal for the others; no
# Vulkan (MoltenVK). Release template: no editor, no debugger.
(cd "$work" && scons -j"$(sysctl -n hw.ncpu)" platform=ios target=template_release "${flags[@]}" \
  vulkan=no generate_bundle=no debug_symbols=no ${GODOT_SCONS_EXTRA:-})

library="$work/bin/libgodot.ios.template_release$suffix.$arch.a"
ls -la "$library"

framework="$output/$name.framework"
rm -rf "$framework"
mkdir -p "$framework"
sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"
printf '_everplay_godot_*\n' > "$output/exports.txt"
# Frameworks Godot's sources import (they are also auto-linked from clang modules).
frameworks=(Foundation UIKit QuartzCore CoreGraphics CoreText CoreVideo CoreMedia CoreMotion CoreHaptics
  AVFoundation AudioToolbox CoreAudio GameController OpenGLES Metal MetalKit MetalFX Security
  SystemConfiguration UniformTypeIdentifiers MediaPlayer IOKit AVFAudio CoreServices)
links=()
for f in "${frameworks[@]}"; do
  [ -d "$sdk_path/System/Library/Frameworks/$f.framework" ] && links+=(-framework "$f")
done
xcrun --sdk "$sdk" clang++ -dynamiclib -arch "$arch" -isysroot "$sdk_path" "$min" \
  -install_name "@rpath/$name.framework/$name" \
  -Wl,-all_load "$library" "${links[@]}" -lc++ -lz \
  -Wl,-exported_symbols_list,"$output/exports.txt" -Wl,-dead_strip \
  -o "$framework/$name"
platform=iPhoneOS; [ "$kind" = simulator ] && platform=iPhoneSimulator
python3 - "$framework/Info.plist" "$name" "$version" "$platform" <<'PYTHON'
import plistlib, sys
path, name, version, platform = sys.argv[1:]
plistlib.dump({
    'CFBundleExecutable': name, 'CFBundleIdentifier': f'app.everplay.engine.{name.lower()}',
    'CFBundleName': name, 'CFBundlePackageType': 'FMWK', 'CFBundleShortVersionString': version,
    'CFBundleVersion': '1', 'MinimumOSVersion': '17.0', 'CFBundleSupportedPlatforms': [platform],
}, open(path, 'wb'))
PYTHON
nm -gU "$framework/$name" | grep everplay_godot_
ls -la "$framework"
