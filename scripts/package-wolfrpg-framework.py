#!/usr/bin/env python3
"""Links the build from build-wolfrpg-ios.sh into WolfRPG.framework, which EverPlay embeds.

The framework exports only everplay_wolf_main(game, saves, font, soundfont, cheats, log). SDL's
window is attached to EverPlay's window scene as for Ren'Py and mkxp-z (SCENE_BRIDGE from
package-renpy-runtime.py); Engines/WolfRPG/ios/WolfGamepad.m adds the touch controls. The fallback
font for games whose fonts are missing is EverPlay's own App/Resources/Fonts/BIZUDGothic-Regular.ttf.

Usage (macOS with Xcode): package-wolfrpg-framework.py OUTPUT_DIR
"""
import importlib.util
import plistlib
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / 'build/wolfrpg-ios'
MINIMUM_IOS = '17.0'
NAME = 'WolfRPG'


def scene_bridge():
    spec = importlib.util.spec_from_file_location('renpy_packager', ROOT / 'scripts/package-renpy-runtime.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.SCENE_BRIDGE


def main():
    output = Path(sys.argv[1]).resolve()
    framework = output / 'Frameworks' / f'{NAME}.framework'
    if framework.exists():
        shutil.rmtree(framework)
    framework.mkdir(parents=True)
    sdk = subprocess.run(['xcrun', '--sdk', 'iphoneos', '--show-sdk-path'], check=True,
                         capture_output=True, text=True).stdout.strip()
    engine = WORK / 'engine'
    libraries = [engine / 'libwolfsdl.a', engine / 'libwolfengine.a', engine / 'libwolfdata.a']
    libraries += sorted((WORK / 'prefix/lib').glob('*.a'))
    with tempfile.TemporaryDirectory() as temporary:
        work = Path(temporary)
        (work / 'scene.m').write_text(scene_bridge())
        objects = []
        sources = [(work / 'scene.m', ['-fobjc-arc', '-fmodules']),
                   (ROOT / 'Engines/WolfRPG/ios/WolfGamepad.m', ['-fobjc-arc', '-fmodules']),
                   (ROOT / 'Engines/WolfRPG/src/platform/EverPlayEntry.cpp',
                    ['-std=c++20', f'-I{WORK / "prefix/include/SDL2"}'])]
        for source, flags in sources:
            target = work / (source.name + '.o')
            compiler = 'clang++' if source.suffix == '.cpp' else 'clang'
            subprocess.run(['xcrun', '-sdk', 'iphoneos', compiler, '-c', '-arch', 'arm64',
                            f'-mios-version-min={MINIMUM_IOS}', '-isysroot', sdk, '-O2', *flags, source, '-o', target],
                           check=True)
            objects.append(str(target))
        frameworks = ['UIKit', 'Foundation', 'Metal', 'QuartzCore', 'CoreGraphics', 'CoreFoundation', 'AVFoundation',
                      'AudioToolbox', 'CoreAudio', 'CoreMotion', 'CoreHaptics', 'GameController', 'CoreBluetooth', 'OpenGLES']
        command = ['xcrun', '-sdk', 'iphoneos', 'clang++', '-arch', 'arm64', f'-mios-version-min={MINIMUM_IOS}',
                   '-isysroot', sdk, '-dynamiclib', '-install_name', f'@rpath/{NAME}.framework/{NAME}',
                   *objects, '-Wl,-dead_strip', *map(str, libraries),
                   '-Wl,-exported_symbol,_everplay_wolf_main', '-liconv', '-lc++',
                   *[part for name in frameworks for part in ('-framework', name)],
                   '-o', str(framework / NAME)]
        print('+', ' '.join(command), flush=True)
        subprocess.run(command, check=True)
    plistlib.dump({'CFBundleExecutable': NAME, 'CFBundleIdentifier': 'app.everplay.runtime.wolfrpg',
                   'CFBundleName': NAME, 'CFBundlePackageType': 'FMWK', 'CFBundleShortVersionString': '1.0',
                   'CFBundleVersion': '1', 'MinimumOSVersion': MINIMUM_IOS,
                   'CFBundleSupportedPlatforms': ['iPhoneOS']},
                  (framework / 'Info.plist').open('wb'))
    subprocess.run(['nm', '-gU', str(framework / NAME)], check=True)
    print(f'Packaged {framework}')


if __name__ == '__main__':
    main()
