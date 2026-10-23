#!/usr/bin/env python3
"""Feasibility: Ren'Py's official native iOS runtime around our trusted fixture.

Builds, from pinned official Ren'Py downloads (EVERPLAY_RENPY_RUNTIME: 8.2.0, the default,
8.5.3 for current Ren'Py 8 games, or 7.8.7 for Python 2 games):
  build/renpy-ios/xcode    renios prototype Xcode project; base/ holds our fixture (gold 10)
  build/renpy-ios/variant  game/ of a desktop (pc) package of the fixture with gold 37,
                           to be started from outside the app bundle via the basedir argument
The SDK executes only our reviewed fixture. Never pass third-party games to this builder.
"""
import ast
import hashlib
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import struct
import tempfile
import zipfile
import zlib

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
    # Exact match for 8.4.1 games that ship a modified engine; they use their own engine scripts.
    '8.4.1': {
        'renpy-8.4.1-sdk.tar.bz2': ('https://www.renpy.org/dl/8.4.1/renpy-8.4.1-sdk.tar.bz2',
                                    '7e398814f242b3c4e51b29b9edb7369d1c71434dacdeb2e83445f11addd55076'),
        'renpy-8.4.1-renios.zip': ('https://www.renpy.org/dl/8.4.1/renpy-8.4.1-renios.zip',
                                   'f631ccd21f6fdc22619882bf55d44653f402dfe832422d1eefa804cba1ee819f'),
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
PLUGIN = ''.join(RELEASE.split('.')[:2])  # 8.5.3 -> 85: plugin id and URL scheme everplay-renpy85
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
# Appended to the prototype's Log.m (already compiled Objective-C). EverPlay, the library app,
# starts a game with everplay-renpyNN://play?game=<folder in Documents>; when Ren'Py exits, the
# plugin opens everplay://library so the player lands back in the library.
URL_BRIDGE = r'''

@import UIKit;
#import <objc/runtime.h>

static NSString *everplay_requested;
static IMP everplay_original_open;
static IMP everplay_original_finish;

static void everplay_capture(NSURL *url) {
    if (![url.scheme hasPrefix:@"everplay-renpy"] || ![url.host isEqualToString:@"play"]) return;
    for (NSURLQueryItem *item in [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO].queryItems) {
        if ([item.name isEqualToString:@"game"] && item.value.length > 0) everplay_requested = [item.value copy];
    }
}

static BOOL everplay_open(id self, SEL command, UIApplication *application, NSURL *url, NSDictionary *options) {
    everplay_capture(url);
    if (everplay_original_open) {
        return ((BOOL (*)(id, SEL, UIApplication *, NSURL *, NSDictionary *)) everplay_original_open)(
            self, command, application, url, options);
    }
    return YES;
}

static BOOL everplay_finish(id self, SEL command, UIApplication *application, NSDictionary *options) {
    NSURL *url = options[UIApplicationLaunchOptionsURLKey];
    if (url) everplay_capture(url);
    return ((BOOL (*)(id, SEL, UIApplication *, NSDictionary *)) everplay_original_finish)(
        self, command, application, options);
}

__attribute__((constructor)) static void everplay_install_url_hooks(void) {
    Class delegate = objc_getClass("SDLUIKitDelegate");
    if (!delegate) return;
    SEL open = @selector(application:openURL:options:);
    Method method = class_getInstanceMethod(delegate, open);
    if (method) everplay_original_open = method_setImplementation(method, (IMP) everplay_open);
    else class_addMethod(delegate, open, (IMP) everplay_open, "B@:@@@");
    method = class_getInstanceMethod(delegate, @selector(application:didFinishLaunchingWithOptions:));
    if (method) everplay_original_finish = method_setImplementation(method, (IMP) everplay_finish);
}

/* The requested game folder name, or NULL. A launch URL can arrive just after launch. */
const char *everplay_requested_game(void) {
    for (int i = 0; i < 20 && everplay_requested == nil; i++) {
        [[NSRunLoop mainRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    return everplay_requested.UTF8String;
}

void everplay_return_to_library(void) {
    NSURL *library = [NSURL URLWithString:@"everplay://library"];
    __block BOOL done = NO;
    NSLog(@"EverPlay: returning to the library");
    [[UIApplication sharedApplication] openURL:library options:@{} completionHandler:^(BOOL success) {
        NSLog(@"EverPlay: library opened: %d", success);
        done = YES;
    }];
    for (int i = 0; i < 20 && !done; i++) {
        [[NSRunLoop mainRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
}
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

const char *everplay_requested_game(void);
void everplay_return_to_library(void);

/* A game folder requested by EverPlay: a plain name directly inside Documents. */
static int requested_game(char *found, size_t size) {
    const char *name = everplay_requested_game();
    const char *home = getenv("HOME");
    char candidate[PATH_MAX];
    if (!name || !home || !*name || name[0] == '.' || strchr(name, '/')) return 0;
    snprintf(found, size, "%s/Documents/%s", home, name);
    snprintf(candidate, sizeof candidate, "%s/game", found);
    return is_directory(candidate);
}

static int everplay_main(int argc, char **argv) {
    if (argc < 2) {
        char game[PATH_MAX];
        if (requested_game(game, sizeof game)) {
            char *arguments[] = { argv[0], game, NULL };
            fprintf(stderr, "EverPlay: starting requested %s\n", game);
            atexit(everplay_return_to_library);
            return launcher_main(2, arguments);
        }
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
    /* Games put buttons at the very bottom edge; let taps there reach the game first instead of
       the home indicator gesture (a second swipe still goes home). */
    setenv("SDL_IOS_HIDE_HOME_INDICATOR", "2", 0);
    return SDL_UIKitRunApp(argc, argv, everplay_main);
}
'''


def configure(xcode):
    """Test-build settings: Documents visible in the Files app, per-runtime name, pointer support."""
    plist = xcode / 'Info.plist'
    with plist.open('rb') as stream:
        info = plistlib.load(stream)
    info.update(CFBundleDisplayName=f'EverPlay RenPy {RELEASE[:3]}', UIFileSharingEnabled=True,
                LSSupportsOpeningDocumentsInPlace=True, UIApplicationSupportsIndirectInputEvents=True,
                CFBundleURLTypes=[{'CFBundleURLName': f'app.everplay.renpy{PLUGIN}',
                                   'CFBundleURLSchemes': [f'everplay-renpy{PLUGIN}']}],
                LSApplicationQueriesSchemes=['everplay'])
    with plist.open('wb') as stream:
        plistlib.dump(info, stream)
    if PYTHON == 'py2':
        # The 7.x prototype's Release configuration still names Python 3.9.
        project = xcode / 'EverPlayRenPyProbe.xcodeproj/project.pbxproj'
        project.write_text(project.read_text().replace('"-lpython3.9"', '"-lpython2.7"'))


GAME_PACKAGES = """
EVERPLAY_RUNTIME = "@RUNTIME@"


def everplay_engine_override(renpy_base):
    # EverPlay: desktop games ship Ren'Py's pure-Python engine next to game/, and some developers
    # modify it (even moving game logic into it). When that copy is exactly our runtime's version,
    # load it instead of the bundled one; the compiled modules still come from the app and match.
    import re
    if len(sys.argv) < 2 or not os.path.isdir(sys.argv[1]):
        return renpy_base
    base = os.path.abspath(sys.argv[1])
    engine = os.path.join(base, "renpy")
    if not os.path.isfile(os.path.join(engine, "__init__.py")):
        return renpy_base
    try:
        with open(os.path.join(engine, "vc_version.py")) as stream:
            found = re.search("version *= *u?['\\"]([0-9]+[.][0-9]+[.][0-9]+)", stream.read())
    except Exception:
        found = None
    version = found.group(1) if found else "unknown"
    if version != EVERPLAY_RUNTIME:
        print("EverPlay: game engine %s differs from runtime %s; using the bundled engine" % (version, EVERPLAY_RUNTIME))
        return renpy_base
    print("EverPlay: using the game's own Ren'Py %s engine scripts" % version)
    sys.path.insert(0, base)
    return base


def everplay_save_location():
    # EverPlay (all-in-one app): iOS Ren'Py saves every game into Documents; give each game the
    # folder the host chose instead. Plugin apps do not set this and keep Ren'Py's behaviour.
    target = os.environ.get("EVERPLAY_SAVE_DIR")
    if not target:
        return

    def path_to_saves(gamedir, save_directory=None):
        if not os.path.isdir(target):
            os.makedirs(target)
        return target

    globals()["path_to_saves"] = path_to_saves


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


def everplay_open_url(url):
    # Opens a link in Safari through UIKit (pyobjus is what Ren'Py itself uses on iOS).
    try:
        from pyobjus import autoclass, objc_str
    except ImportError:
        return False
    try:
        target = autoclass("NSURL").URLWithString_(objc_str(url))
        application = autoclass("UIApplication").sharedApplication()
        try:
            application.openURL_options_completionHandler_(target, autoclass("NSDictionary").dictionary(), None)
        except Exception:
            application.openURL_(target)
        print("EverPlay: opened %r" % (url,))
        return True
    except Exception as e:
        print("EverPlay: could not open %r: %r" % (url, e))
        return False


# Online extras some desktop games bundle (AI text, analytics, cloud saves). They often depend on
# compiled parts built only for Windows or macOS, which iOS cannot load.
EVERPLAY_OPTIONAL = ("openai", "anthropic", "boto3", "pymysql", "mysql.connector", "MySQLdb",
                     "pypresence", "steamworks")


class EverPlayMissing(object):
    # Stands in for anything inside an extra that could not load: attribute access keeps
    # working, calling it raises, which games already handle for offline play.
    def __init__(self, name, reason):
        self._everplay_name = name
        self._everplay_reason = reason

    def __getattr__(self, attribute):
        if attribute.startswith("__"):
            raise AttributeError(attribute)
        return EverPlayMissing(self._everplay_name + "." + attribute, self._everplay_reason)

    def __call__(self, *args, **kwargs):
        raise RuntimeError("%s is not available on iOS (%s)" % (self._everplay_name, self._everplay_reason))

    def __bool__(self):
        return False
    __nonzero__ = __bool__


def everplay_shipped(top):
    if sys.version_info[0] >= 3:
        import importlib.util
        return importlib.util.find_spec(top) is not None
    import imp
    try:
        imp.find_module(top)
        return True
    except ImportError:
        return False


def everplay_optional_extras():
    import types

    class EverPlayMissingModule(types.ModuleType):
        def __getattr__(self, attribute):
            if attribute.startswith("__"):
                raise AttributeError(attribute)
            return EverPlayMissing(self.__name__ + "." + attribute, self._everplay_reason)

    for name in EVERPLAY_OPTIONAL:
        try:
            if not everplay_shipped(name.split(".")[0]):
                continue  # not shipped by this game
            __import__(name)
        except Exception as error:
            reason = "%s: %s" % (type(error).__name__, error)
            for loaded in list(sys.modules):
                if loaded == name or loaded.startswith(name + "."):
                    del sys.modules[loaded]
            module = EverPlayMissingModule(name)
            module._everplay_reason = reason
            sys.modules[name] = module
            parent, _, child = name.rpartition(".")
            if parent:
                if parent not in sys.modules:
                    sys.modules[parent] = types.ModuleType(parent)
                setattr(sys.modules[parent], child, module)
            print("EverPlay: %s cannot load on iOS, replaced by a placeholder (%s)" % (name, reason))


def everplay_compatibility():
    import re
    # Python's webbrowser module has no iOS backend here, so Ren'Py's open_url (link buttons
    # such as Patreon or Discord invites) would silently do nothing. Route it to Safari.
    try:
        import webbrowser

        def open_link(url, *args, **kwargs):
            return everplay_open_url(url)

        webbrowser.open = webbrowser.open_new = webbrowser.open_new_tab = open_link
    except ImportError:
        pass

    # iOS forbids starting other programs, so its Python has no os.system. Desktop games still
    # call it (Discord status libraries, "start https://..." link buttons). Open links in
    # Safari and ignore everything else instead of failing.
    if not hasattr(os, "system"):
        def system(command):
            link = re.search("https?://[^ <>']+", command or "")
            if link and everplay_open_url(link.group(0).rstrip('"')):
                return 0
            print("EverPlay: os.system is unavailable on iOS; ignored %r" % (command,))
            return 127
        os.system = system

    everplay_optional_extras()

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
    assert source.count('    sys.path.append(renpy_base)') == 1
    source = source.replace('def main():', GAME_PACKAGES.lstrip('\n').replace('@RUNTIME@', RELEASE) + 'def main():')
    source = source.replace('    sys.path.append(renpy_base)',
                            '    renpy_base = everplay_engine_override(renpy_base)\n    sys.path.append(renpy_base)')
    source = source.replace('    renpy.bootstrap.bootstrap(renpy_base)',
                            '    everplay_game_packages()\n    everplay_save_location()\n    everplay_compatibility()\n'
                            '    renpy.bootstrap.bootstrap(renpy_base)')
    if PYTHON == 'py3':
        ast.parse(source, str(main_py))  # A broken main.py would stop every game from starting.
    main_py.write_text(source)


BUBBLE_LOOP = '    for k in sorted(bubble.properties):\n'
# Ren'Py runs this common code in the game's store, so a game variable named "sorted" breaks it
# (seen in a real 8.4 game whose developer patched their own engine copy the same way).
BUBBLE_SAFE = (
    '    try:\n'
    '        import builtins as _everplay_builtins\n'
    '    except ImportError:\n'
    '        import __builtin__ as _everplay_builtins\n'
    '    for k in _everplay_builtins.sorted(bubble.properties):\n'
)


EMPTY_WINDOW = '            store.narrator.empty_window(multiple=multiple)\n'
# Games written for older Ren'Py replace narrator with their own class, which lacks empty_window
# (and may raise KeyError for unknown attributes); older engines showed the window by calling it.
EMPTY_WINDOW_SAFE = (
    '            try:\n'
    '                _everplay_empty = store.narrator.empty_window\n'
    '            except Exception:\n'
    '                _everplay_empty = None\n'
    '            if _everplay_empty is not None:\n'
    '                _everplay_empty(multiple=multiple)\n'
    '            else:\n'
    '                store.narrator("", interact=False)\n'
)


def harden_common(sdk):
    """Make engine code that shares the game's namespace robust against older games' habits."""
    library = sdk / 'renpy/common/00library.rpy'
    source = library.read_text(encoding='utf-8')
    assert source.count(EMPTY_WINDOW) == 1, 'empty window code changed; review the fallback'
    library.write_text(source.replace(EMPTY_WINDOW, EMPTY_WINDOW_SAFE), encoding='utf-8')
    library.with_suffix('.rpyc').unlink()

    bubble = sdk / 'renpy/common/00speechbubble.rpy'
    source = bubble.read_text(encoding='utf-8')
    assert source.count(BUBBLE_LOOP) == 1, 'speech bubble code changed; review the shadowing guard'
    bubble.write_text(source.replace(BUBBLE_LOOP, BUBBLE_SAFE), encoding='utf-8')
    # Recompiled by the SDK's own launcher run below, before ios_populate copies the engine.
    bubble.with_suffix('.rpyc').unlink()

    # EverPlay's in-game menu (quick actions, variable editor) for every game on this runtime.
    shutil.copy(ROOT / 'scripts/renpy-common/00everplay.rpy', sdk / 'renpy/common/00everplay.rpy')


def verify_common(xcode):
    """The app ships only compiled common code; read its zlib slots (no unpickling) for the guard."""
    compiled = list(xcode.rglob('renpy/common/00speechbubble.rpyc'))
    assert compiled, 'bundled engine has no speech bubble code'
    library = list(xcode.rglob('renpy/common/00library.rpyc'))
    assert library, 'bundled engine has no library code'
    assert list(xcode.rglob('renpy/common/00everplay.rpyc')), 'bundled engine lacks the EverPlay menu'
    for path in compiled + library:
        data = path.read_bytes()
        assert data.startswith(b'RENPY RPC2'), f'unexpected format {path}'
        position, slots = 10, []
        while position + 12 <= len(data):
            slot, start, length = struct.unpack('<III', data[position:position + 12])
            position += 12
            if slot == 0:
                break
            slots.append(zlib.decompress(data[start:start + length]))
        marker = b'_everplay_builtins' if path.stem == '00speechbubble' else b'_everplay_empty'
        assert slots and all(marker in blob for blob in slots), f'unpatched {path}'


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
        harden_common(sdk)
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
        verify_common(xcode)

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
        # A desktop-style package that imports os.system, which iOS Python lacks.
        packages = output / 'variant/game/python-packages'
        packages.mkdir(parents=True)
        (packages / 'everplay_desktop_extra.py').write_text('from os import environ, system\n')
        (output / 'variant/game/desktop_extra.rpy').write_text(
            'init python:\n    import everplay_desktop_extra\n    import openai\n    openai.api_key = "test"\n')
        # An online extra whose compiled part exists only for desktop systems.
        (packages / 'openai').mkdir()
        (packages / 'openai/__init__.py').write_text('from ._native import Client\n')
        # A game variable that shadows a builtin used by Ren'Py's own common code.
        (output / 'variant/game/shadowed_builtin.rpy').write_text('define sorted = "newest"\n')
        # E: a game folder that ships its own (here: marked) copy of the same engine version.
        engine = output / 'engine'
        shutil.copytree(output / 'variant/game', engine / 'game')
        shutil.copytree(sdk / 'renpy', engine / 'renpy', ignore=shutil.ignore_patterns('__pycache__', '*.pyc', '*.pyo'))
        with (engine / 'renpy/game.py').open('a') as stream:
            stream.write('\neverplay_engine_marker = True\n')
        (engine / 'game/engine_marker.rpy').write_text(
            'init python:\n'
            '    if getattr(renpy.game, "everplay_engine_marker", False):\n'
            '        config.after_default_callbacks.append(lambda: setattr(store, "gold", 99))\n')
        shutil.copytree(work / 'quit/game', output / 'quit/game')
        # Opens a link via os.system the way desktop games do; CI expects Safari to show it.
        (output / 'link/game').mkdir(parents=True)
        (output / 'link/game/script.rpy').write_text(
            'label start:\n'
            '    $ import os\n'
            '    $ os.system("start https://example.com/everplay-link-test")\n'
            '    "EverPlay link test"\n'
            '    return\n')
        (xcode / 'main.c').write_text(MAIN)
        log = xcode / 'Log.m'
        log.write_text(log.read_text() + URL_BRIDGE)
        configure(xcode)
        add_game_packages(xcode / 'base/main.py')
    print(f'Built Ren\'Py {RELEASE} iOS prototype and desktop variant in {output.relative_to(ROOT)}')


if __name__ == '__main__':
    main()
