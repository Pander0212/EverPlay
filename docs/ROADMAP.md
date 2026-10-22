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

Unity Windows builds cannot be supported (closed engine, natively compiled game code, no JIT on iOS). Unity **WebGL** builds are treated like HTML games. Keep each milestone independently testable and never claim universal engine support.
