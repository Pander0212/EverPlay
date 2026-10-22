#!/usr/bin/env python3
"""Feasibility: Ren'Py's official native iOS runtime around our trusted fixture.

Builds, from pinned official Ren'Py downloads (EVERPLAY_RENPY_RUNTIME: 8.2.0, the default,
8.5.3 for current Ren'Py 8 games, or 7.8.7 for Python 2 games):
  build/renpy-ios/xcode    renios prototype Xcode project; base/ holds our fixture (gold 10)
  build/renpy-ios/variant  game/ of a desktop (pc) package of the fixture with gold 37,
                           to be started from outside the app bundle via the basedir argument
The SDK executes only our reviewed fixture. Never pass third-party games to this builder.
"""
import hashlib
import os
from pathlib import Path
import plistlib
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
    # Newest verified Ren'Py 8: newer engines start older 8.x games, not the reverse.
    '8.5.3': {
        'renpy-8.5.3-sdk.tar.bz2': ('https://github.com/renpy/renpy/releases/download/8.5.3.26051504/renpy-8.5.3-sdk.tar.bz2',
                                    'eb0a9be7f0fb13632fe25ceade9a8bed5a1b4d6b6e83bd19eeeb29e1a1bb4a45'),
        'renpy-8.5.3-renios.zip': ('https://www.renpy.org/dl/8.5.3/renpy-8.5.3-renios.zip',
                                   'c4fae153e8276ed0faed5e84ea3e0b7c4bf337f0e3208e9130c6a41748a83b2b'),
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
# Replaces the prototype's main.c. Launch arguments are game directories, run one after another
# in the same process (to test re-initialising Python and SDL). Without arguments, the first
# folder in Documents (visible in the Files app) that contains game/ is started; the bundled
# fixture is the fallback.
MAIN = r'''#include <dirent.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

int launcher_main(int argc, char **argv);
int SDL_UIKitRunApp(int, char **, int (*)(int, char**));

static int is_directory(const char *path) {
    struct stat info;
    return stat(path, &info) == 0 && S_ISDIR(info.st_mode);
}

static int compare_names(const void *a, const void *b) {
    return strcmp(*(char * const *) a, *(char * const *) b);
}

/* Writes the first game directory under Documents into `found`; returns 0 if there is none. */
static int find_game(char *found, size_t size) {
    const char *home = getenv("HOME");
    char documents[PATH_MAX], candidate[PATH_MAX];
    if (!home) return 0;
    snprintf(documents, sizeof documents, "%s/Documents", home);

    snprintf(candidate, sizeof candidate, "%s/README.txt", documents);
    FILE *readme = fopen(candidate, "wx");
    if (readme) {
        fputs("EverPlay Ren'Py test build\n\n"
              "Copy an unzipped Ren'Py PC game folder (the folder that contains game/) here.\n"
              "The first such folder (alphabetical) starts when the app opens.\n"
              "Saves are stored in this Documents folder. Quit the game to switch games.\n", readme);
        fclose(readme);
    }

    snprintf(candidate, sizeof candidate, "%s/game", documents);
    if (is_directory(candidate)) {
        snprintf(found, size, "%s", documents);
        return 1;
    }
    DIR *directory = opendir(documents);
    if (!directory) return 0;
    char *names[256];
    int count = 0;
    struct dirent *entry;
    while ((entry = readdir(directory)) && count < 256) {
        if (entry->d_name[0] == '.') continue;
        snprintf(candidate, sizeof candidate, "%s/%s/game", documents, entry->d_name);
        if (is_directory(candidate)) names[count++] = strdup(entry->d_name);
    }
    closedir(directory);
    if (count == 0) return 0;
    qsort(names, count, sizeof names[0], compare_names);
    snprintf(found, size, "%s/%s", documents, names[0]);
    for (int i = 0; i < count; i++) free(names[i]);
    return 1;
}

static int everplay_main(int argc, char **argv) {
    if (argc < 2) {
        char game[PATH_MAX];
        if (find_game(game, sizeof game)) {
            char *arguments[] = { argv[0], game, NULL };
            fprintf(stderr, "EverPlay: starting %s\n", game);
            return launcher_main(2, arguments);
        }
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


def configure(xcode):
    """Test-build settings: Documents visible in the Files app, per-runtime name, pointer support."""
    plist = xcode / 'Info.plist'
    with plist.open('rb') as stream:
        info = plistlib.load(stream)
    info.update(CFBundleDisplayName=f'EverPlay RenPy {RELEASE[0]}', UIFileSharingEnabled=True,
                LSSupportsOpeningDocumentsInPlace=True, UIApplicationSupportsIndirectInputEvents=True)
    with plist.open('wb') as stream:
        plistlib.dump(info, stream)
    if PYTHON == 'py2':
        # The 7.x prototype's Release configuration still names Python 3.9.
        project = xcode / 'EverPlayRenPyProbe.xcodeproj/project.pbxproj'
        project.write_text(project.read_text().replace('"-lpython3.9"', '"-lpython2.7"'))


GAME_PACKAGES = """
def everplay_game_packages():
    # EverPlay: desktop games may ship extra pure-Python packages (in game/python-packages or
    # their lib/ folder). Make them importable *after* the runtime's own modules, so the iOS
    # standard library always wins and only missing modules come from the game.
    import glob
    if len(sys.argv) < 2 or not os.path.isdir(sys.argv[1]):
        return
    base = os.path.abspath(sys.argv[1])
    for pattern in ("game/python-packages", "lib/python*/site-packages", "lib/python*"):
        for path in sorted(glob.glob(os.path.join(base, pattern))):
            if os.path.isdir(path) and path not in sys.path:
                sys.path.append(path)


def everplay_patch_translations():
    # EverPlay: some desktop games define the same string translation twice (for example in
    # code paths that only run on mobile). Desktop Ren'Py aborts; keep the first one and log.
    import renpy.translation
    translator = getattr(renpy.translation, "StringTranslator", None)
    if translator is None or getattr(translator.add, "everplay", False):
        return
    original = translator.add

    def add(self, old, new, newloc):
        if old in self.translations:
            print("EverPlay: ignored duplicate translation for %r at %r" % (old, newloc))
            return
        return original(self, old, new, newloc)

    add.everplay = True
    translator.add = add


def everplay_compatibility():
    # Patch only after Ren'Py has imported its own modules in its usual order; importing
    # renpy.translation any earlier fails because it needs renpy.ast.
    import renpy
    original = renpy.import_all

    def import_all():
        original()
        everplay_patch_translations()

    renpy.import_all = import_all


"""


def add_game_packages(main_py):
    source = main_py.read_text()
    assert source.count('def main():') == 1 and source.count('    renpy.bootstrap.bootstrap(renpy_base)') == 1
    source = source.replace('def main():', GAME_PACKAGES.lstrip('\n') + 'def main():')
    source = source.replace('    renpy.bootstrap.bootstrap(renpy_base)',
                            '    everplay_game_packages()\n    everplay_compatibility()\n'
                            '    renpy.bootstrap.bootstrap(renpy_base)')
    main_py.write_text(source)


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
        # Two definitions of one string translation: stock Ren'Py refuses this (the SDK will not
        # even build it), so add them after packaging; case B must still reach the gold-37 screen.
        duplicate = 'translate None strings:\n    old "Load slot"\n    new "Load slot"\n'
        for name in ('duplicate_a.rpy', 'duplicate_b.rpy'):
            (output / 'variant/game' / name).write_text(duplicate)
        shutil.copytree(work / 'quit/game', output / 'quit/game')
        (xcode / 'main.c').write_text(MAIN)
        configure(xcode)
        add_game_packages(xcode / 'base/main.py')
    print(f'Built Ren\'Py {RELEASE} iOS prototype and desktop variant in {output.relative_to(ROOT)}')


if __name__ == '__main__':
    main()
