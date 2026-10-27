#!/usr/bin/env bash
# Builds Godot (official sources at a pinned tag, MIT) for iPhone as Godot<NN>.framework, which
# EverPlay loads with dlopen to play a game's .pck (scripts/godot/everplay_godot.mm, everplay_godot3.mm).
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
  sdk=iphonesimulator; flags=(ios_simulator=yes arch="$arch"); min=-mios-simulator-version-min=17.0
else
  arch=arm64; sdk=iphoneos; flags=(arch=arm64); min=-miphoneos-version-min=17.0
fi

# The compatibility renderer (OpenGL ES 3) for gl_compatibility games and Metal for the others; no
# Vulkan (MoltenVK). Release template: no editor, no debugger. Path overrides on (Godot 4.5+): EverPlay
# names the game's pack with --main-pack, which release templates refuse otherwise.
if [ "${version%%.*}" = 3 ]; then
  # Godot 3: platform "iphone", release template without tools (GLES3 with GLES2 fallback).
  (cd "$work" && scons -j"$(sysctl -n hw.ncpu)" platform=iphone target=release tools=no "${flags[@]}" \
    debug_symbols=no ${GODOT_SCONS_EXTRA:-})
else
  grep -q '"disable_path_overrides"' "$work/SConstruct" && flags+=(disable_path_overrides=no)
  (cd "$work" && scons -j"$(sysctl -n hw.ncpu)" platform=ios target=template_release "${flags[@]}" \
    vulkan=no generate_bundle=no debug_symbols=no ${GODOT_SCONS_EXTRA:-})
fi

# libgodot.ios.template_release.arm64[.simulator].a, Godot 3: libgodot.iphone.opt.arm64[.simulator].a
# (the order of the suffixes differs between versions).
library="$(ls "$work"/bin/libgodot.*.a | grep -E "(template_release|[.]opt)[.]" | grep -E "\.$arch[.]" \
  | { if [ "$kind" = simulator ]; then grep simulator; else grep -v simulator; fi; } | head -n 1)"
ls -la "$library"
# Linked whole (-all_load): Godot 4.4's pcre2 has _pcre2_ckd_smul in both its 16- and 32-bit objects
# (identical code), which a whole-archive link rejects as a duplicate. Keep one.
copy="$output/libgodot.a"
cp "$library" "$copy"
for member in $(ar t "$copy" | grep -E '^pcre2_chkdint_16[.]' || true); do ar d "$copy" "$member"; done
library="$copy"

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
rm -f "$copy"
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
