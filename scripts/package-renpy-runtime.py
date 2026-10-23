#!/usr/bin/env python3
"""Turns the renios project produced by build-renpy-ios-prototype.py into parts EverPlay embeds.

One iOS app can carry several Ren'Py runtimes: each becomes a dynamic framework
(Frameworks/RenPyNN.framework) that exports only everplay_renpy_main, so the Python, SDL and
FFmpeg copies inside different runtimes never meet. Only one runtime is loaded per app run.
Its engine files go to Runtimes/NN/base; Ren'Py finds them relative to argv[0].

Usage (macOS with Xcode): package-renpy-runtime.py iphoneos|iphonesimulator OUTPUT_DIR
"""
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
XCODE = ROOT / 'build/renpy-ios/xcode'
RELEASE = os.environ.get('EVERPLAY_RENPY_RUNTIME', '8.5.3')
PLUGIN = ''.join(RELEASE.split('.')[:2])
MINIMUM_IOS = '17.0'
# The 8.x runtimes ship the same MetalANGLE build; other versions get their own renamed copy.
SHARED_ANGLE_SHA256 = '5f861cec64bf298eafff3b698b5af4fd6a9d8d3786ba43b9af3a0804b69b88e6'

ENTRY = r'''#include <limits.h>
#include <stdio.h>
#include <stdlib.h>

int launcher_main(int argc, char **argv);
void SDL_SetMainReady(void);

/* Runs one game. `runtime` holds base/ (engine, Python library, EverPlay's main.py);
   `game` is the desktop game folder that contains game/. */
__attribute__((visibility("default")))
int everplay_renpy_main(const char *runtime, const char *game) {
    static char program[PATH_MAX];
    snprintf(program, sizeof program, "%s/main", runtime);
    /* Buttons at the bottom edge reach the game before the home indicator gesture. */
    setenv("SDL_IOS_HIDE_HOME_INDICATOR", "2", 0);
    /* EverPlay owns UIApplicationMain; SDL runs inside it instead of SDL_UIKitRunApp. */
    SDL_SetMainReady();
    char *argv[] = { program, (char *) game, NULL };
    return launcher_main(2, argv);
}
'''


def run(*command):
    print('+', ' '.join(str(c) for c in command), flush=True)
    subprocess.run([str(c) for c in command], check=True)


def link_flags():
    project = (XCODE / 'EverPlayRenPyProbe.xcodeproj/project.pbxproj').read_text()
    block = re.search(r'OTHER_LDFLAGS = \((.*?)\);', project, re.S)
    libraries = re.findall(r'"(-l[^"]+)"', block.group(1))
    frameworks = sorted(set(re.findall(r'name = (\w+)\.framework; path = System/Library/Frameworks', project)))
    # Pulled in by the prototype's Objective-C (StoreKit, video playback) and by SDL itself.
    frameworks = sorted(set(frameworks) | {'AVFoundation', 'StoreKit', 'Metal', 'CoreMedia',
                                           'CoreVideo', 'CoreAudio', 'CoreHaptics', 'AVKit', 'Security'})
    assert '-lrenpython' in libraries, 'unexpected renios link settings'
    return libraries, frameworks


def objective_c_sources(work):
    sources = []
    for name in ('Log.m', 'IAPHelper.m', 'VideoPlayer.m'):
        text = (XCODE / name).read_text()
        if name == 'Log.m':
            # The plugin-app URL bridge hooks SDL's own app delegate, which EverPlay does not use.
            text = text.split('\n@import UIKit;\n#import <objc/runtime.h>', 1)[0]
        path = work / name
        path.write_text(text)
        sources.append(path)
    return sources


def angle(sdk, output):
    """Returns (framework name, path) of the MetalANGLE to link, copying it into output."""
    slice_name = 'ios-arm64_armv7' if sdk == 'iphoneos' else 'ios-arm64_i386_x86_64-simulator'
    source = XCODE / 'Frameworks/MetalANGLE.xcframework' / slice_name / 'MetalANGLE.framework'
    digest = subprocess.run(['shasum', '-a', '256', str(XCODE / 'Frameworks/MetalANGLE.xcframework/ios-arm64_armv7/MetalANGLE.framework/MetalANGLE')],
                            check=True, capture_output=True, text=True).stdout.split()[0]
    name = 'MetalANGLE' if digest == SHARED_ANGLE_SHA256 else f'MetalANGLE{PLUGIN}'
    target = output / 'Frameworks' / f'{name}.framework'
    if target.exists():
        shutil.rmtree(target)
    shutil.copytree(source, target, symlinks=True)
    shutil.rmtree(target / 'Headers', ignore_errors=True)
    binary = target / 'MetalANGLE'
    if sdk == 'iphoneos':
        run('lipo', binary, '-thin', 'arm64', '-output', binary)
    if name != 'MetalANGLE':
        binary.rename(target / name)
        binary = target / name
        run('install_name_tool', '-id', f'@rpath/{name}.framework/{name}', binary)
    with (target / 'Info.plist').open('rb') as stream:
        info = plistlib.load(stream)
    info.update(CFBundleExecutable=name, MinimumOSVersion=MINIMUM_IOS,
                CFBundleIdentifier=f'app.everplay.runtime.{name.lower()}')
    with (target / 'Info.plist').open('wb') as stream:
        plistlib.dump(info, stream)
    return name, target


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in ('iphoneos', 'iphonesimulator'):
        raise SystemExit(__doc__)
    sdk, output = sys.argv[1], Path(sys.argv[2]).resolve()
    arch = 'arm64' if sdk == 'iphoneos' else os.environ.get('EVERPLAY_SIMULATOR_ARCH', 'x86_64')
    prebuilt = XCODE / 'prebuilt' / ('release' if sdk == 'iphoneos' else 'debug')
    libraries, frameworks = link_flags()
    # The app link drops unused objects; a dynamic library must resolve everything it keeps.
    libraries += [f'-l{lib}' for lib in ('sharpyuv',) if (prebuilt / f'lib{lib}.a').exists()]
    name = f'RenPy{PLUGIN}'
    framework = output / 'Frameworks' / f'{name}.framework'
    if framework.exists():
        shutil.rmtree(framework)
    framework.mkdir(parents=True)
    angle_name, angle_path = angle(sdk, output)
    version_flag = f'-mios-version-min={MINIMUM_IOS}' if sdk == 'iphoneos' else f'-mios-simulator-version-min={MINIMUM_IOS}'
    with tempfile.TemporaryDirectory() as temporary:
        work = Path(temporary)
        (work / 'entry.c').write_text(ENTRY)
        command = ['xcrun', '-sdk', sdk, 'clang', '-dynamiclib', '-arch', arch, version_flag,
                   '-fobjc-arc', '-fmodules', '-O2',
                   work / 'entry.c', *objective_c_sources(work),
                   '-L', prebuilt, *libraries, '-lc++',
                   '-F', angle_path.parent, '-framework', angle_name,
                   *[part for item in frameworks for part in ('-framework', item)],
                   '-install_name', f'@rpath/{name}.framework/{name}',
                   '-Wl,-exported_symbol,_everplay_renpy_main', '-Wl,-dead_strip',
                   '-o', framework / name]
        run(*command)
    plistlib.dump({'CFBundleExecutable': name, 'CFBundleIdentifier': f'app.everplay.runtime.renpy{PLUGIN}',
                   'CFBundleName': name, 'CFBundlePackageType': 'FMWK', 'CFBundleShortVersionString': RELEASE,
                   'CFBundleVersion': '1', 'MinimumOSVersion': MINIMUM_IOS,
                   'CFBundleSupportedPlatforms': ['iPhoneOS' if sdk == 'iphoneos' else 'iPhoneSimulator']},
                  (framework / 'Info.plist').open('wb'))
    runtime = output / 'Runtimes' / PLUGIN
    if runtime.exists():
        shutil.rmtree(runtime)
    shutil.copytree(XCODE / 'base', runtime / 'base', symlinks=True)
    (runtime / 'version.txt').write_text(RELEASE + '\n')
    print(f'Packaged Ren\'Py {RELEASE} as {framework} and {runtime}')


if __name__ == '__main__':
    main()
