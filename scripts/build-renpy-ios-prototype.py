#!/usr/bin/env python3
"""Feasibility: Ren'Py's official native iOS runtime around our trusted fixture.

Builds, from pinned official Ren'Py downloads (EVERPLAY_RENPY_RUNTIME: 8.2.0, the default,
or 7.8.7 for Python 2 games):
  build/renpy-ios/xcode    renios prototype Xcode project; base/ holds our fixture (gold 10)
  build/renpy-ios/variant  game/ of a desktop (pc) package of the fixture with gold 37,
                           to be started from outside the app bundle via the basedir argument
The SDK executes only our reviewed fixture. Never pass third-party games to this builder.
"""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
RUNTIMES = {
    '8.2.0': {
        'renpy-8.2.0-sdk.tar.bz2': ('https://github.com/renpy/renpy/releases/download/8.2.0.24012702/renpy-8.2.0-sdk.tar.bz2',
                                    'e79ec1014bad6adba69336f90802e89ae7a70172c1bb9c15301267390e9d7b38'),
        'renpy-8.2.0-renios.zip': ('https://www.renpy.org/dl/8.2.0/renpy-8.2.0-renios.zip',
                                   '509452bc204c59245a8bb52d084c0bab4e0ece330eea03b055a90b37158df282'),
    },
    # Last Python 2 release; also the runtime for older Ren'Py 6/7 games.
    '7.8.7': {
        'renpy-7.8.7-sdk.tar.bz2': ('https://www.renpy.org/dl/7.8.7/renpy-7.8.7-sdk.tar.bz2',
                                    '65466068af7c181a143f13d84b0ddf7a6aa58dd8d26e7ccd97cdcadecabcae5a'),
        'renpy-7.8.7-renios.zip': ('https://www.renpy.org/dl/7.8.7/renpy-7.8.7-renios.zip',
                                   'faaabec4ec65efa8803a5a7222f6e40183c5fe8354c1ee4eeb78e978826cee86'),
    },
}
RELEASE = os.environ.get('EVERPLAY_RENPY_RUNTIME', '8.2.0')
if RELEASE not in RUNTIMES:
    raise SystemExit(f'Unsupported runtime {RELEASE!r}; choose one of {", ".join(RUNTIMES)}')
HASHES = RUNTIMES[RELEASE]
PYTHON = 'py2' if RELEASE.startswith('7.') else 'py3'
# renios.create.create_project expects a reporting interface; the launcher normally takes it
# from the Android tooling, which iOS does not need.
CREATE = '''
import os, sys
sdk, dest, name, version = sys.argv[1:5]
sys.path[:0] = [sdk, os.path.join(sdk, "renios", "buildlib")]
import renios.create
class Interface:
    def info(self, message): print(message)
    def success(self, message): print(message)
    def fail(self, message): raise SystemExit(message)
renios.create.create_project(Interface(), dest, name, version)
'''
# Replaces the prototype's main.c: each launch argument is a game directory, run one after
# another in the same process, to test re-initialising Python and SDL between games.
MAIN = r'''#include <stdio.h>

int launcher_main(int argc, char **argv);
int SDL_UIKitRunApp(int, char **, int (*)(int, char**));

static int everplay_main(int argc, char **argv) {
    if (argc < 2) {
        return launcher_main(argc, argv);
    }
    int status = 0;
    for (int i = 1; i < argc; i++) {
        char *game[] = { argv[0], argv[i], NULL };
        fprintf(stderr, "EverPlay: starting game %d of %d\n", i, argc - 1);
        status = launcher_main(2, game);
        fprintf(stderr, "EverPlay: game %d exited with status %d\n", i, status);
    }
    return status;
}

int main(int argc, char **argv) {
    return SDL_UIKitRunApp(argc, argv, everplay_main);
}
'''


def fetch(cache):
    for name, (url, expected) in HASHES.items():
        archive = cache / name
        if not archive.exists():
            subprocess.run(['curl', '--fail', '--location', '--show-error', '--retry', '2',
                            '--max-time', '600', url, '--output', str(archive)], check=True)
        digest = hashlib.sha256()
        with archive.open('rb') as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b''):
                digest.update(block)
        if digest.hexdigest() != expected:
            raise SystemExit(f'Checksum mismatch: {name}; inspect the download before retrying')


def main():
    cache = Path(os.environ.get('EVERPLAY_RENPY_CACHE', ROOT / f'.build-tools/renpy-{RELEASE[:3]}')).resolve()
    cache.mkdir(parents=True, exist_ok=True)
    fetch(cache)
    output = ROOT / 'build/renpy-ios'
    if output.exists():
        shutil.rmtree(output)
    output.mkdir(parents=True)
    env = dict(os.environ, SDL_VIDEODRIVER='dummy', SDL_AUDIODRIVER='dummy')
    with tempfile.TemporaryDirectory(prefix='renpy-ios-') as temporary:
        work = Path(temporary)
        subprocess.run(['tar', '-xjf', str(cache / f'renpy-{RELEASE}-sdk.tar.bz2'), '-C', str(work)], check=True)
        sdk = work / f'renpy-{RELEASE}-sdk'
        with zipfile.ZipFile(cache / f'renpy-{RELEASE}-renios.zip') as archive:
            archive.extractall(sdk)
        source = (ROOT / 'Experiments/RenPyProbe/game/script.rpy').read_text()
        assert source.count('default gold = 10') == 1
        assert source.count('    call screen probe\n') == 1
        projects = {'probe': source, 'variant': source.replace('default gold = 10', 'default gold = 37'),
                    # Ends itself so a following game can run in the same process.
                    'quit': source.replace('    call screen probe\n',
                                           '    $ renpy.pause(3.0, hard=True)\n    $ renpy.quit()\n')}
        for name, script in projects.items():
            (work / name / 'game').mkdir(parents=True)
            (work / name / 'game/script.rpy').write_text(script)

        platform = 'mac-universal' if sys.platform == 'darwin' else 'linux-x86_64'
        python = sdk / 'lib' / f'{PYTHON}-{platform}' / 'python'
        (work / 'create.py').write_text(CREATE)
        xcode = output / 'xcode'
        isolated = ['-E', '-s'] if PYTHON == 'py2' else ['-I']  # Python 2 has no -I
        subprocess.run([str(python), *isolated, str(work / 'create.py'), str(sdk), str(xcode),
                        'EverPlay RenPy Probe', '0.1'], check=True)
        subprocess.run([str(sdk / 'renpy.sh'), str(sdk / 'launcher'), 'ios_populate',
                        str(work / 'probe'), str(xcode)], env=env, check=True)

        subprocess.run([str(sdk / 'renpy.sh'), str(sdk / 'launcher'), 'distribute', str(work / 'variant'),
                        '--package', 'pc', '--no-update', '--destination', str(work / 'desktop')],
                       env=env, check=True)
        package = next((work / 'desktop').glob('*-pc.zip'))
        with zipfile.ZipFile(package) as archive:
            top = archive.namelist()[0].split('/')[0]
            members = [n for n in archive.namelist() if n.startswith(f'{top}/game/')]
            assert any(n.endswith('.rpa') for n in members), 'desktop package has no compiled archive'
            assert not any(n.endswith('.rpy') for n in members), 'desktop package unexpectedly ships source'
            archive.extractall(work / 'unpacked', members)
        shutil.copytree(work / 'unpacked' / top / 'game', output / 'variant/game')
        shutil.copytree(work / 'quit/game', output / 'quit/game')
        (xcode / 'main.c').write_text(MAIN)
    print(f'Built Ren\'Py {RELEASE} iOS prototype and desktop variant in {output.relative_to(ROOT)}')


if __name__ == '__main__':
    main()
