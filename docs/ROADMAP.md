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

## Competitive position (2026-10-23)

ZScripter (App Store, zscripter.com) already ships Ren'Py 6.15–8.6 with exact per-game runtimes, ONScripter family, KiriKiri, RealLive, Artemis, AI5, RPG Maker MV/MZ (WebKit) and XP/VX/VX Ace (own Ruby runtime), LLM translation (MTool-style, per the owner's use of the app), a save editor and a touch-control editor. Its support page lists RPG Maker 2000/2003 as unsupported and does not mention Wolf RPG or TyranoBuilder; the owner reports that a modified-engine game (School) fails there.

EverPlay differentiates by:
1. Games that ship a modified engine (runs the game's own engine scripts on the exact runtime).
2. Live cheats on top of save editing: in-game variable browser/search, speed-up, gallery unlock, developer console.
3. Translation that is free out of the box (Apple on-device) in addition to BYOK models.
4. Engines ZScripter lacks: RPG Maker 2000/2003 (EasyRPG), TyranoBuilder, Wolf RPG (research), HTML/Twine, Godot, Flash.
5. Community features for F95zone players: updates that keep saves, mods, crowd-sourced compatibility reports.
6. Sideloaded distribution without App Store review limits.

## Working list (2026-10-23)

Ordered; each item ends with a simulator CI check and, where possible, an owner test on iPhone.

**A. All-in-one Ren'Py (in progress)**
- [x] Runtimes 8.5.3 / 8.4.1 / 7.8.7 as private frameworks inside EverPlay
- [x] Ren'Py renders inside EverPlay (simulator: Gold 37 per runtime, Gold 99 with a game's own engine)
- [ ] All-in-one IPA tested on iPhone (School Game, Contract Demon, Another Chance, FET)
- [ ] Engine data (`Runtimes/NN/base`) downloaded on first use from a GitHub release, SHA-256 pinned in the app; native frameworks stay in the IPA
- [ ] Back to the library after quitting instead of closing EverPlay (Ren'Py quit hook, hide SDL window). A second Ren'Py game in the same process failed in CI case C, so starting another Ren'Py game will still need a fresh app start
- [x] Ren'Py ZIP import (safe extraction straight into Documents/Ren'Py)
- [ ] Copy/extract progress bar
- [x] Text input: SDL keyboard retry plus a native "Type" button when the iOS keyboard does not appear (simulator fixture Input85)
- [x] Per-game runtime choice on the game page
- [ ] Crash screen: show `traceback.txt`, copy/share, "report" button
- [ ] More runtimes measured against real games: 7.4.11, 7.3.5, 8.1.3, 8.2.3, 8.3.7
- [x] Ren'Py in-game menu (draggable button): quick save/load, rollback, skip, skip unseen, auto, hide UI, instant text, save/load/settings, main menu (checked on 8.5.3 and 7.8.7 desktop SDKs; simulator fixture Menu78)
- [ ] Gamepad and keyboard shortcuts for the in-game menu

**A2. Control profiles (for every engine)**
- [ ] Profile model: per engine defaults (built-in "Compact" and "Standard"), user profiles, per-game override, separate iPhone/iPad and portrait/landscape layouts, import/export
- [ ] Touch layout editor: add, edit, select, duplicate, delete, snap-to-grid, opacity/size, live preview; builds on the existing HTML virtual-controls arrange mode
- [ ] Element types: button (key, mouse click, action), D-pad, analog stick, swipe area, toggle buttons (skip, auto, hide UI), menu button
- [ ] Input injection: WebKit games via key events (existing), SDL engines (Ren'Py, mkxp-z, EasyRPG, ONScripter) via SDL_PushEvent from the runtime framework
- [ ] Hardware controllers (GameController framework), keyboard and mouse/trackpad mapping, mouse mode (relative cursor)
- [ ] Gestures: swipe for rollback/skip, two-finger tap for menu, long press for right click, pinch to zoom

**B. RPG Maker**
- [x] MV/MZ: NW.js stand-ins (`require('fs'|'path'|'os'|'nw.gui'|...)`, `nw.Window`; `process` left undefined so saves stay in per-game browser storage), case-insensitive file lookup in the game server (node and core tests)
- [ ] MV/MZ: Ogg audio check, performance (WebGL, canvas size), real-game test
- [ ] MV/MZ decryption-free play of encrypted assets (`.rpgmvp/.ogg_`) as the engine does
- [ ] XP/VX/VX Ace via mkxp-z as a runtime framework (RTP fonts/assets handling, Win32API shims)
- [ ] 2000/2003 via EasyRPG Player as a runtime framework

**B2. Japanese / DLsite engines**
- [ ] TyranoScript / TyranoBuilder: HTML5 game in WKWebView like MV/MZ, plus NW.js/Electron shims and packed-EXE extraction (JoiPlay supports it the same way)
- [ ] KiriKiri 2 / Z (KAG): research native players. Kirikiroid2 (Android) is the established player for commercial games; krkrsdl2 is SDL2-based but targets macOS/Linux and not unmodified commercial games. Check licences and iOS buildability, XP3 archives, common plugin DLL replacements; games with custom XP3 encryption stay unsupported
- [ ] Wolf RPG Editor: closed engine without a known open-source player; long-term research item (would need a reimplementation)
- [ ] NScripter / ONScripter games via the open-source ONScripter family

**C. Translation (MTool-style)**
- [x] Provider layer: Google (free, unofficial endpoint), DeepL (free/pro key), OpenAI-compatible BYOK (OpenAI, OpenRouter, local servers), Claude BYOK; keys in the Keychain; markup kept via placeholders (unit tested)
- [ ] Apple on-device Translation (iOS 18+, offline) as a further free provider
- [x] Translation memory per game and language (each line once, Application Support/Translations)
- [ ] Glossary for names, export/import, editing single lines
- [x] Ren'Py: live say/menu hook (config.say_menu_text_filter) with look-ahead prefetch of the next lines and choices; no waiting while skipping; "Original text" switch in the in-game menu (checked on 8.5.3 and 7.8.7 SDKs with a stand-in service)
- [ ] Ren'Py: interface text (screens) and batch pre-translation of a whole game
- [ ] RPG Maker MV/MZ: hook `Window_Base` text drawing and batch-translate `data/*.json`
- [ ] Toggle original/translated in game; font fallback for CJK/Cyrillic

**D. Cheats and save editor**
- [x] Ren'Py: variable editor in the in-game menu (game-changed or all variables, one level into objects and dicts, search by name or =value, ±1/10/100, edit), developer console, gallery/replay unlock
- [ ] Ren'Py: freeze values, saved cheat presets per game, search for changed/unchanged values between scans
- [x] RPG Maker MV/MZ: gold, items/weapons/armor, heal and level the party, switches/variables (search by name, #id, =value), speed ×1–×4, walk through walls, no random encounters (game menu › Cheats; logic tested against an engine stand-in in `tests/rpgmaker-cheats.test.js`)
- [ ] Save editor: MV/MZ saves (LZString JSON) in a native editor; Ren'Py saves edited only inside the running game; automatic backups

**E. Comfort and discretion**
- [x] Cover art from the game (`gui/main_menu.png`, window icon, RPG Maker title), playtime, last played, game page
- [ ] More per-game settings (controls profile, translation, cheats) on the game page
- [ ] Face ID lock, blurred app switcher, alternate icons, hidden games
- [ ] Save sync folder via Files (iCloud Drive etc.)

**F. Later engines**
- [ ] Ruffle (Flash) and HTML interactive fiction players (Twine, QSP, TADS/ADRIFT web interpreters)
- [ ] Godot 3.6 / 4.x GDScript games via runtime frameworks
- [ ] MCP modding server

Unity Windows builds cannot be supported (closed engine, natively compiled game code, no JIT on iOS). Unity **WebGL** builds are treated like HTML games. Keep each milestone independently testable and never claim universal engine support.
