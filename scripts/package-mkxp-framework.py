#!/usr/bin/env python3
"""Links the mkxp-z build from build-mkxp-ios.sh into MKXP.framework, which EverPlay embeds.

The framework exports only everplay_mkxp_main(game folder): it switches into the game folder
(mkxp-z is built with workdir_current, so it reads mkxp.json and Game.ini there) and runs
mkxp-z's main. SDL's window is attached to EverPlay's window scene the same way as for Ren'Py
(SCENE_BRIDGE from package-renpy-runtime.py).

Usage (macOS with Xcode): package-mkxp-framework.py OUTPUT_DIR
"""
import importlib.util
import plistlib
import shlex
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / 'build/mkxp-ios'
BUILD = WORK / 'build'
MINIMUM_IOS = '17.0'
NAME = 'MKXP'

ENTRY = r'''#include <stdio.h>
#include <unistd.h>

int SDL_main(int argc, char **argv);
void SDL_SetMainReady(void);
void everplay_attach_sdl_windows(void);

__attribute__((visibility("default")))
int everplay_mkxp_main(const char *game) {
    if (chdir(game) != 0) {
        fprintf(stderr, "EverPlay: cannot open the game folder\n");
        return 1;
    }
    /* EverPlay owns UIApplicationMain; SDL runs inside it instead of SDL_UIKitRunApp. */
    SDL_SetMainReady();
    everplay_attach_sdl_windows();
    char *argv[] = { "mkxp-z", NULL };
    return SDL_main(1, argv);
}
'''


def scene_bridge():
    spec = importlib.util.spec_from_file_location('renpy_packager', ROOT / 'scripts/package-renpy-runtime.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.SCENE_BRIDGE


def executable_link_command():
    """mkxp-z's own executable link line: every static library and framework it needs."""
    targets = subprocess.run(['ninja', '-C', BUILD, '-t', 'targets', 'all'], check=True,
                             capture_output=True, text=True).stdout
    linked = [line.split(':')[0] for line in targets.splitlines()
              if ':' in line and 'LINKER' in line.split(':', 1)[1] and Path(line.split(':')[0]).name.startswith('mkxp-z.')]
    if not linked:
        print('\n'.join(line for line in targets.splitlines() if 'LINKER' in line))
        sys.exit('mkxp-z executable target not found')
    executable = linked[0]
    commands = subprocess.run(['ninja', '-C', BUILD, '-t', 'commands', executable], check=True,
                              capture_output=True, text=True).stdout.strip().splitlines()
    return executable, shlex.split(commands[-1])


def main():
    output = Path(sys.argv[1])
    executable, command = executable_link_command()
    # Build everything the executable links (the libraries, Ruby included), but not the executable.
    inputs = [part for part in command if part.endswith('.a') or part.endswith('.o')]
    subprocess.run(['ninja', '-C', BUILD, *inputs], check=True)
    framework = output / 'Frameworks' / f'{NAME}.framework'
    if framework.exists():
        shutil.rmtree(framework)
    framework.mkdir(parents=True)
    output_index = command.index('-o')
    del command[output_index:output_index + 2]
    with tempfile.TemporaryDirectory() as temporary:
        work = Path(temporary)
        (work / 'entry.c').write_text(ENTRY)
        (work / 'scene.m').write_text(scene_bridge())
        sdk = subprocess.run(['xcrun', '--sdk', 'iphoneos', '--show-sdk-path'], check=True,
                             capture_output=True, text=True).stdout.strip()
        objects = []
        for source in ('entry.c', 'scene.m'):
            target = work / (source + '.o')
            subprocess.run(['xcrun', '-sdk', 'iphoneos', 'clang', '-c', '-arch', 'arm64', f'-mios-version-min={MINIMUM_IOS}',
                            '-isysroot', sdk, '-fobjc-arc', '-fmodules', '-O2', work / source, '-o', target], check=True)
            objects.append(str(target))
        command += [*objects, '-dynamiclib', '-install_name', f'@rpath/{NAME}.framework/{NAME}',
                    '-Wl,-exported_symbol,_everplay_mkxp_main', '-Wl,-dead_strip',
                    '-framework', 'UIKit', '-framework', 'OpenGLES', '-o', str(framework / NAME)]
        print('+', shlex.join(command), flush=True)
        subprocess.run(command, check=True, cwd=BUILD)
    plistlib.dump({'CFBundleExecutable': NAME, 'CFBundleIdentifier': 'app.everplay.runtime.mkxp',
                   'CFBundleName': NAME, 'CFBundlePackageType': 'FMWK', 'CFBundleShortVersionString': '2.4.2',
                   'CFBundleVersion': '1', 'MinimumOSVersion': MINIMUM_IOS,
                   'CFBundleSupportedPlatforms': ['iPhoneOS']},
                  (framework / 'Info.plist').open('wb'))
    print(f'Packaged mkxp-z ({executable}) as {framework}')


if __name__ == '__main__':
    main()
