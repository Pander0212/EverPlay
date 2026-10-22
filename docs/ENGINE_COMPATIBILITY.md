# Engine compatibility

| Engine/package | This build | Evidence and limits |
| --- | --- | --- |
| Generic HTML5/JavaScript with `index.html` | Four-case simulator acceptance passed | Original demo passes import/touch/save/app-relaunch, native HTTP, WebKit isolation/input and draggable-control/landscape cases at source `2eda7f3`. Browser and portable-core tests pass. Earlier intermittent startup observations require lifecycle follow-up; physical-device and arbitrary-game compatibility remain unverified. |
| Twine HTML export | Potentially compatible, untested | Must be packaged as `index.html` with local assets; no Twine-specific fixture yet. |
| RPG Maker MV | Detected, experimental web runtime path | Tests recognize `js/rpg_core.js` and require `data/System.json`; no real MV runtime/game test or compatibility patches yet. |
| RPG Maker MZ | Detected, experimental web runtime path | Tests recognize `js/rmmz_core.js` and require `data/System.json`; no real MZ runtime/game test yet. |
| RPG Maker 2000/2003 | Unsupported, planned | EasyRPG (GPLv3); acceptable for the sideloaded IPA with published source. Not linked yet. |
| RPG Maker XP/VX/VX Ace | Unsupported, planned | mkxp-z (Ruby/native, GPL); not linked yet. EasyRPG does **not** implement these engines. |
| Ren’Py desktop package | Direct app import unsupported; matched-version experiment | Original RenPy 8.5.3 Windows/Linux `story.rpa` runs after controlled packaging into WebAssembly; Chromium interaction/save/restart and native simulator interaction/save/session-reopen tests pass. Exact experiment validation is recorded in [RENPY_EXPERIMENT.md](RENPY_EXPERIMENT.md). Windows executables, unknown versions and native extensions are not supported. |
| Godot native/PCK export | Unsupported, planned | GDScript games via a bundled native runtime matching the `.pck` engine version; desktop texture formats on Apple GPUs need verification. C# (.NET) and GDExtension games are out of scope. |
| Godot web export | Not validated | Could fit the web adapter, but WebGL/WASM/thread requirements need real exported fixtures; no compatibility claim. |
| Unity Windows/Linux build | Not possible | Closed engine and natively compiled game code (IL2CPP) or .NET requiring JIT, which iOS does not allow. |
| Unity WebGL build | Potentially compatible, untested | Handled like other HTML5 games if a game ships one. |

EverPlay targets a sideloaded IPA (see [ROADMAP.md](ROADMAP.md)); native engine runtimes are planned for Ren’Py, older RPG Maker and Godot. Games must be self-contained and legally obtained. Node.js/NW.js native modules, Windows DLLs, DRM, filesystem APIs, arbitrary native binaries and remote multiplayer services are not provided. CSP intentionally blocks remote assets/services. Audio may need an initial user tap and depends on WebKit codec support. No universal canvas text interception, save discovery or plugin compatibility claim.
