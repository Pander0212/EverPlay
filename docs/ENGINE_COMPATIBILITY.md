# Engine compatibility

| Engine/package | This build | Evidence and limits |
| --- | --- | --- |
| Generic HTML5/JavaScript with `index.html` | Four-case simulator acceptance passed | Original demo passes import/touch/save/app-relaunch, native HTTP, WebKit isolation/input and draggable-control/landscape cases at source `2eda7f3`. Browser and portable-core tests pass. Earlier intermittent startup observations require lifecycle follow-up; physical-device and arbitrary-game compatibility remain unverified. |
| Twine HTML export | Potentially compatible, untested | Must be packaged as `index.html` with local assets; no Twine-specific fixture yet. |
| RPG Maker MV | Detected, experimental web runtime path | Tests recognize `js/rpg_core.js` and require `data/System.json`; no real MV runtime/game test or compatibility patches yet. |
| RPG Maker MZ | Detected, experimental web runtime path | Tests recognize `js/rmmz_core.js` and require `data/System.json`; no real MZ runtime/game test yet. |
| RPG Maker 2000/2003 | Unsupported | EasyRPG is a plausible GPLv3 interpreter; not linked. |
| RPG Maker XP/VX/VX Ace | Unsupported | Investigate mkxp-z/mobile forks, Ruby/native dependencies and GPL obligations. EasyRPG does **not** implement these engines. |
| Ren’Py desktop package | Direct app import unsupported; matched-version experiment | Original RenPy 8.5.3 Windows/Linux `story.rpa` runs after controlled packaging into WebAssembly; Chromium interaction/save/restart and native simulator interaction/save/session-reopen tests pass. Exact experiment validation is recorded in [RENPY_EXPERIMENT.md](RENPY_EXPERIMENT.md). Windows executables, unknown versions and native extensions are not supported. |
| Godot native/PCK export | Unsupported | Needs matching engine/resource version and native extension/signing review. |
| Godot web export | Not validated | Could fit the web adapter, but WebGL/WASM/thread requirements need real exported fixtures; no compatibility claim. |
| Unity | Excluded | No implementation or roadmap target. |

Games must be self-contained and legally obtained. Node.js/NW.js native modules, Windows DLLs, DRM, filesystem APIs, arbitrary native binaries and remote multiplayer services are not provided. CSP intentionally blocks remote assets/services. Audio may need an initial user tap and depends on WebKit codec support. No universal canvas text interception, save discovery or plugin compatibility claim.
