#!/usr/bin/env bash
# Builds GDE GoZen (MIT, video playback for Godot through FFmpeg, codeberg.org/gozen/gde_gozen) for
# iPhone as gozen.framework. Godot games that bring GoZen ship it for Windows/Linux/macOS only; the
# patched Godot runtimes load EverPlay's iOS build instead (EVERPLAY_GODOT_EXTENSIONS, see
# patch-godot-ios.py). FFmpeg (LGPL) is built static with the decoders games use.
# Usage: build-gozen-ios.sh <device|simulator> <output folder>
set -euo pipefail

kind="$1"
output="$(mkdir -p "$2" && cd "$2" && pwd)"
here="$(cd "$(dirname "$0")" && pwd)"
work="${GOZEN_WORK:-build/gozen}"
gozen_commit="${GOZEN_COMMIT:-f9448619324ad7d0d4e79d3bd501bde477ea4b7f}"

fetch() {  # fetch <url> <commit> <folder>
  [ -d "$3/.git" ] && return
  git init -q "$3"
  git -C "$3" fetch -q --depth 1 "$1" "$2"
  git -C "$3" checkout -q FETCH_HEAD
}
fetch https://github.com/VoylinsGamedevJourney/gde_gozen.git "$gozen_commit" "$work"
# The FFmpeg and godot-cpp commits GoZen pins as submodules.
ffmpeg_commit="$(git -C "$work" ls-tree HEAD ffmpeg | awk '{print $3}')"
godot_cpp_commit="$(git -C "$work" ls-tree HEAD godot_cpp | awk '{print $3}')"
rmdir "$work/ffmpeg" "$work/godot_cpp" 2>/dev/null || true
fetch https://github.com/FFmpeg/FFmpeg.git "$ffmpeg_commit" "$work/ffmpeg"
fetch https://github.com/godotengine/godot-cpp.git "$godot_cpp_commit" "$work/godot_cpp"

if [ "$kind" = simulator ]; then
  sdk=iphonesimulator; min=-mios-simulator-version-min=17.0; simulator=yes
else
  sdk=iphoneos; min=-miphoneos-version-min=17.0; simulator=no
fi
sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"
prefix="$PWD/$work/ffmpeg/bin"

# FFmpeg: decoders for the videos and sounds games ship (H.264/HEVC/VP8/VP9/Theora, AAC/MP3/Vorbis/
# Opus/FLAC/PCM) in MP4/MOV, WebM/MKV, Ogg; no network, no encoders, no hardware decoders.
if [ ! -f "$prefix/lib/libavcodec.a" ]; then
  (cd "$work/ffmpeg" && ./configure --prefix="$prefix" --enable-cross-compile --target-os=darwin --arch=aarch64 \
    --cc="xcrun --sdk $sdk clang" --cxx="xcrun --sdk $sdk clang++" --sysroot="$sdk_path" \
    --extra-cflags="-arch arm64 $min" --extra-ldflags="-arch arm64 $min" \
    --enable-static --disable-shared --enable-pic --disable-programs --disable-doc --disable-debug \
    --disable-everything --disable-network --disable-avdevice --disable-avfilter --disable-hwaccels \
    --disable-videotoolbox --disable-audiotoolbox --disable-securetransport --disable-iconv \
    --disable-bzlib --disable-lzma --enable-zlib \
    --enable-avformat --enable-avcodec --enable-swscale --enable-swresample \
    --enable-protocol=file \
    --enable-demuxer=mov,matroska,ogg,mp3,wav,flac,aac,gif,apng,image2 \
    --enable-decoder=h264,hevc,vp8,vp9,theora,mpeg4,aac,mp3,vorbis,opus,flac,pcm_s16le,pcm_f32le,gif,apng,png \
    --enable-parser=h264,hevc,vp8,vp9,aac,mpegaudio,vorbis,opus,flac,png \
    && make -j"$(sysctl -n hw.ncpu)" && make install)
fi

# GoZen's SConstruct knows Linux, Windows, macOS, Android and the web; iOS links like macOS, with
# godot-cpp's iOS toolchain.
if ! grep -q 'elif "ios" in platform' "$work/SConstruct"; then
  python3 - "$work/SConstruct" <<'PYTHON'
import sys
path = sys.argv[1]
text = open(path).read()
marker = 'elif "android" in platform:'
assert text.count(marker) == 1, 'GoZen SConstruct changed'
text = text.replace(marker, '''elif "ios" in platform:
    env.Append(
        CPPPATH=["ffmpeg/bin/include"],
        LIBPATH=["ffmpeg/bin/lib"],
        LIBS=LIBS_COMMON,
        LINKFLAGS=["-framework", "CoreFoundation", "-framework", "CoreVideo", "-framework", "CoreMedia",
                   "-framework", "AudioToolbox", "-framework", "Security"],
    )
    env.Append(LIBS=["z"])
''' + marker)
open(path, 'w').write(text)
PYTHON
fi
(cd "$work" && scons -j"$(sysctl -n hw.ncpu)" platform=ios arch=arm64 target=template_release ios_simulator="$simulator" \
  ios_min_version=17.0)
library="$(ls "$work"/test_room/addons/gde_gozen/bin/libgozen.ios.template_release*.dylib | head -n 1)"
ls -la "$library"

framework="$output/gozen.framework"
rm -rf "$framework"
mkdir -p "$framework"
cp "$library" "$framework/gozen"
install_name_tool -id @rpath/gozen.framework/gozen "$framework/gozen"
platform=iPhoneOS; [ "$kind" = simulator ] && platform=iPhoneSimulator
python3 - "$framework/Info.plist" "$platform" "$gozen_commit" <<'PYTHON'
import plistlib, sys
path, platform, commit = sys.argv[1:]
plistlib.dump({
    'CFBundleExecutable': 'gozen', 'CFBundleIdentifier': 'app.everplay.extension.gozen',
    'CFBundleName': 'gozen', 'CFBundlePackageType': 'FMWK', 'CFBundleShortVersionString': commit[:7],
    'CFBundleVersion': '1', 'MinimumOSVersion': '17.0', 'CFBundleSupportedPlatforms': [platform],
}, open(path, 'wb'))
PYTHON
nm -gU "$framework/gozen" | grep gozen_library_init
ls -la "$framework"
