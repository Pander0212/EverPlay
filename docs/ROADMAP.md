# Roadmap

## Product direction (owner decision, 2026-10-22)

EverPlay is an **iOS alternative to JoiPlay**: play existing Windows/Linux desktop releases of Ren’Py, RPG Maker, HTML and compatible Godot games on iPhone and iPad, with optional cheats, a save editor, translation and agent-assisted modding.

- **Distribution:** sideloaded IPA (AltStore/SideStore with free signing as the baseline; TrollStore extras only where available). The App Store is not a target. Funding is expected via Patreon, not ads.
- **Consequences:** native engine runtimes are allowed and GPL-licensed interpreters (EasyRPG, mkxp-z) may be linked, provided the complete source stays published. Every feature must work with free signing: no paid-account entitlements (iCloud containers, App Groups) as a requirement. Native runtimes must be compiled into the IPA; iOS does not allow JIT for native code or loading downloaded native code.
- **Test devices:** iPhone 15 (6 GB RAM, iOS 17+) and iPad 8th generation (3 GB RAM, the low-memory reference).
- **Real-game tests** use owner-supplied games in the private `Pander0212/EverPlay-GameTest` repository only. Never place third-party games, bundles containing them, saves or game screenshots in this public repository, its releases or Actions artifacts.

## Milestones

1. **Foundation (simulator baseline passed):** SwiftUI app, safe ZIP import, engine detection, immutable installations, local HTTP/WKWebView runtime, original demo, per-game storage, virtual controls and simulator CI. Lifecycle/stress coverage and physical-device validation remain open.
2. **Ren’Py, native:** feasibility first — build Ren’Py for iOS from official sources and run an unmodified desktop `game/` directory with our own fixture. Then prove Ren’Py 7 (Python 2) and Ren’Py 8 (Python 3) runtimes side by side in one app (separately built frameworks), choose bundled versions from measured compatibility, stream large games from disk, and support video. The WebAssembly path (see [RENPY_EXPERIMENT.md](RENPY_EXPERIMENT.md)) stays as a fallback. Games with native Python extensions or Windows DLLs remain unsupported.
3. **RPG Maker:** MV/MZ through the web runtime with case-insensitive resource lookup, NW.js/Node API shims (`require('fs')`, `nw.Window`, `process`) backed by per-game storage, and verified Ogg audio on iOS. Then XP/VX/VX Ace via mkxp-z and 2000/2003 via EasyRPG.
4. **Cheats and save editor:** native SwiftUI panel; RPG Maker variables/switches/party, Ren’Py store variables, gallery/replay unlock, developer console toggle, value search, and editing saves inside the engine (never unpickling Ren’Py saves in the app) with automatic backups. Show which variables a Ren’Py choice changes.
5. **Translation (MTool-style):** live text hooks and full pre-translation; OpenAI-compatible BYOK endpoints (including free models) plus optional DeepL Free; keys in Keychain; translation memory so each line is translated once. Network calls are made by the app, never by game code.
6. **Discretion and comfort:** Face ID lock, blurred app-switcher preview, alternate icons, hidden games; gestures and controllers; game updates that keep saves and mods; a user-chosen sync folder (iCloud Drive, Dropbox, … via the Files app) for saves with conflict-safe backups; playing large games directly from Files/external storage.
7. **MCP modding:** paired, local-network MCP server so a desktop coding agent can read game files, query the running game, and install reversible `.evermod` overlays with live reload.
8. **Godot:** GDScript games via bundled native Godot runtimes matching the `.pck` engine version, with texture-format handling verified on Apple GPUs. Godot C# and GDExtension games are out of scope.

## Working list (2026-10-23)

Ordered; each item ends with a simulator CI check and, where possible, an owner test on iPhone.

**A. All-in-one Ren'Py (in progress)**
- [x] Runtimes 8.5.3 / 8.4.1 / 7.8.7 as private frameworks inside EverPlay
- [ ] Ren'Py renders inside EverPlay (simulator: Gold 37 per runtime, Gold 99 with a game's own engine)
- [ ] All-in-one IPA tested on iPhone (School Game, Contract Demon, Another Chance, FET)
- [ ] Engine data (`Runtimes/NN/base`) downloaded on first use from a GitHub release, SHA-256 pinned in the app; native frameworks stay in the IPA
- [ ] Back to the library after quitting instead of closing EverPlay (Ren'Py quit hook, hide SDL window)
- [ ] Ren'Py ZIP import (safe extraction straight into Documents/Ren'Py) and a copy progress bar
- [ ] Crash screen: show `traceback.txt`, copy/share, "report" button
- [ ] More runtimes measured against real games: 7.4.11, 7.3.5, 8.1.3, 8.2.3, 8.3.7
- [ ] Ren'Py controls overlay: rollback, skip, auto, hide UI, quick save/load; gamepad

**B. RPG Maker**
- [ ] MV/MZ: NW.js shims (`require('fs'|'path')`, `nw.Window`, `process`), saves in per-game storage, case-insensitive files, Ogg audio check, performance (WebGL, canvas size)
- [ ] MV/MZ decryption-free play of encrypted assets (`.rpgmvp/.ogg_`) as the engine does
- [ ] XP/VX/VX Ace via mkxp-z as a runtime framework (RTP fonts/assets handling, Win32API shims)
- [ ] 2000/2003 via EasyRPG Player as a runtime framework

**C. Translation (MTool-style)**
- [ ] Provider layer: Apple on-device Translation (iOS 18, free, offline), OpenAI-compatible BYOK, DeepL Free; keys in Keychain
- [ ] Translation memory per game (each line once), glossary for names, export/import
- [ ] Ren'Py: live say/menu text hook in our `main.py` layer, plus batch pre-translation of dialogue
- [ ] RPG Maker MV/MZ: hook `Window_Base` text drawing and batch-translate `data/*.json`
- [ ] Toggle original/translated in game; font fallback for CJK/Cyrillic

**D. Cheats and save editor**
- [ ] Ren'Py: in-game overlay with store variable browser/editor, search by value, developer console toggle, gallery/replay unlock
- [ ] RPG Maker MV/MZ: gold, items, party stats, switches/variables, speed-up (×2/×4), noclip
- [ ] Save editor: MV/MZ saves (LZString JSON) in a native editor; Ren'Py saves edited only inside the running game; automatic backups

**E. Comfort and discretion**
- [ ] Cover art from the game (icon, `gui/main_menu.png`), playtime, per-game settings
- [ ] Face ID lock, blurred app switcher, alternate icons, hidden games
- [ ] Save sync folder via Files (iCloud Drive etc.)

**F. Later engines**
- [ ] Ruffle (Flash) and HTML interactive fiction players (Twine, QSP, TADS/ADRIFT web interpreters)
- [ ] Godot 3.6 / 4.x GDScript games via runtime frameworks
- [ ] MCP modding server

Unity Windows builds cannot be supported (closed engine, natively compiled game code, no JIT on iOS). Unity **WebGL** builds are treated like HTML games. Keep each milestone independently testable and never claim universal engine support.
