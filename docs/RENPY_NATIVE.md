# Native Ren’Py on iOS

Direction: run unmodified desktop `game/` directories with Ren’Py’s own native iOS runtime (see [ROADMAP.md](ROADMAP.md)). The WebAssembly path in [RENPY_EXPERIMENT.md](RENPY_EXPERIMENT.md) remains a fallback.

## Official building blocks

- Ren’Py publishes `renpy-<version>-renios.zip` per release (8.2.0: SHA-256 `509452bc204c59245a8bb52d084c0bab4e0ece330eea03b055a90b37158df282`, matching the official `checksums.txt`). It contains a prototype Xcode project and prebuilt static libraries: Python 3.9, Ren’Py’s compiled modules, SDL2, FFmpeg and MetalANGLE (OpenGL ES on Metal). `prebuilt/release` is device `arm64`; `prebuilt/debug` is simulator `x86_64` + `arm64`.
- The app bundle’s `base/` holds `main.py`, the pure-Python `renpy/` package, the Python standard library and a game. `launcher_main` (renpy-build `runtime/librenpython.c`) finds `base/` next to the executable and passes extra launch arguments to Ren’Py; Ren’Py treats the first one as `basedir` and loads `basedir/game`.
- `scripts/build-renpy-ios-prototype.py` reproduces the project from pinned downloads around our MIT fixture only. It calls `renios.create.create_project` directly (the launcher’s `ios_create` command needs the Android tooling just for a reporting object) and then the official `ios_populate` command.

## Feasibility result (simulator)

[Run 39793190244](https://github.com/Pander0212/EverPlay/actions/runs/39793190244), source `6ddf3d07906a02e86bfa549cc0cd4c454525210a`, `macos-15-intel`, Xcode 16.4, iPhone simulator:

| Case | Input | Result |
| --- | --- | --- |
| A | Fixture inside the bundle’s `base/game` | Rendered natively, “Gold: 10” |
| B | `game/` of a desktop (pc) package of a fixture variant (`story.rpa` + `script_version.txt`, no source) copied to the app’s `Documents/EverPlayGames/variant`, launched with that directory as the argument | Rendered natively, “Gold: 37” — the external desktop game ran |

Logs show the GLES2 renderer on “ANGLE (Metal Renderer: Apple iOS simulator GPU)” and interface start in 0.4–1.1 s. Interaction, saving, audio, video and physical devices were **not** tested in this run.

## Known integration work

- **Saves:** on iOS, `path_to_saves` returns the app’s Documents directory for every game; EverPlay must give each game its own save directory (our bundled `renpy.py` can honour an EverPlay-provided path).
- **App lifecycle:** `SDL_UIKitRunApp` owns `UIApplicationMain`. EverPlay’s SwiftUI library and the SDL game must share one app, and Python can only be initialised reliably once per process; returning from a game to the library may need an app restart at first.
- **Ren’Py 7 and 8 together:** both link a static CPython with identical symbols; plan separately linked frameworks per runtime, loaded on demand.
- **Info.plist:** add `UIApplicationSupportsIndirectInputEvents` for mouse/trackpad support.

## Compatibility layer for real desktop games

Found with real games on an iPhone; each rule covers a class of games, not a single title.

| Problem | Handling |
| --- | --- |
| Extra Python packages in `game/python-packages` or `lib/python*` | Appended to `sys.path` after the runtime's own modules |
| Same string translation defined twice | First definition wins, duplicate is logged |
| `os.system` / `webbrowser` (Discord status, link buttons) | Links open in Safari, other commands are ignored |
| Game variable shadows a builtin used by engine code (`sorted`) | Bundled speech-bubble code uses the real builtin |
| Online extras whose compiled parts exist only for desktop (OpenAI via `pydantic_core`, MySQL, …) | Replaced by a placeholder: attributes work, calls raise, games keep running offline |
| Game ships a **modified engine** (`renpy/` next to `game/`) | If its `vc_version.py` matches the runtime exactly, the game's own engine scripts are used with the app's compiled modules |

The last rule is why exact runtimes matter: a real 8.4.1 game moved part of its game logic into `renpy/game.py` and `renpy/persistent.py` and removed engine checks (VPGrid overfull, duplicate translations). It needs the 8.4.1 runtime. CI case E proves the switch with a marked engine copy (`Gold: 99`).

## One app for every runtime (all-in-one)

Free sideloading allows only three apps, so separate runtime apps (JoiPlay-style plugins) are not the main path. Instead each Ren'Py runtime is packaged into EverPlay itself (`scripts/package-renpy-runtime.py`):

- `Frameworks/RenPyNN.framework` links the official prebuilt renios libraries and exports only `everplay_renpy_main`, so the Python, SDL and FFmpeg inside different runtimes never meet. The 8.x runtimes share one MetalANGLE; 7.8 gets a renamed copy.
- `Runtimes/NN/base` holds the engine and EverPlay's `main.py`; Ren'Py's launcher finds it relative to `argv[0]`, which EverPlay sets per runtime.
- EverPlay keeps Ren'Py games in Documents/Ren'Py, picks the exact engine version when bundled (otherwise the newest of the same major version), loads that framework with `dlopen` and calls it on the main thread after `SDL_SetMainReady` (EverPlay, not SDL, owns `UIApplicationMain`). Saves go to Documents/Saves/<game>.
- One Python per process: quitting a Ren'Py game currently closes EverPlay.

The standalone runtime apps (with `everplay-renpyNN://play?game=` URL start, CI case F) remain test builds.
