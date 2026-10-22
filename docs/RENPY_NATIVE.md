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
