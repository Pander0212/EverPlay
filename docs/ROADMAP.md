# Roadmap

1. **Foundation (this slice, native verification pending):** SwiftUI target, safe ZIP import, engine detection, immutable installations, local HTTP/WKWebView runtime, original demo, persistent per-game storage, virtual controls, portable tests and simulator CI. Close the native compilation/UI-test gate before calling milestone 1 complete.
2. **MV/MZ:** Obtain legitimate minimal engine exports, verify startup/audio/touch/storage, add narrowly tested web compatibility shims and engine APIs. Never infer real-game compatibility from filename detection.
3. **Translation:** Provider abstraction, deterministic tests, Keychain, SQLite migrations/cache, language/model settings, safe extraction/replacement, bounded asynchronous work and placeholder preservation.
4. **Mods/cheats/saves:** Manifest/hash validation, immutable overlays, explicit activation, backup/restore/rollback, original demo mod cycle, then verified MV/MZ adapters.
5. **MCP Bridge:** Pinned official SDK, TypeScript tests and CI, scoped workspaces, authenticated pairing, per-game permissions, phone-side installation approval and redacted debug logs.
6. **Additional engines:** Separately assess EasyRPG (2000/2003), mkxp-z/Ruby (XP/VX/VX Ace), Ren’Py versioned iOS exports and compatible Godot builds. Resolve licensing/distribution obligations before linking any interpreter.

Unity is excluded. Keep each milestone independently testable; no native binaries as mods and no universal engine-support claims. Folder imports, cover extraction, recovery management and external controllers follow after foundation stability.
