# Architecture

## Implemented foundation

**Deployment:** iOS/iPadOS 17+. **Build:** Xcode 16.4, Swift 5 language mode with Swift 6 toolchain, XcodeGen 2.44.1, local Swift package. iOS 17 permits a persistent `WKWebsiteDataStore(forIdentifier:)` for each game. Linux runs the actual `EverPlayCore` package, not a rewrite of its algorithms.

```
SwiftUI Library / Import / Settings
              │
       LibraryModel (@MainActor)
              │ security-scoped document → coordinated temporary copy
       LibraryStore (actor) ───── atomic versioned library.json
              │
       GameImporter → private staging → validate → move → publish record
              │
       Games/<UUID>/ (immutable to the runtime)
              │
       HTTPResourceRouter (portable and tested)
              │
       LocalGameServer (Network.framework, loopback TCP)
              │
       GameSession → WKWebView → persistent per-UUID browser data
```

`GameEngineAdapter` describes validation and honest capabilities. A platform-specific session owns launch/presentation; the portable core does not import SwiftUI or WebKit. Only the web adapter exists. No fake native adapters are registered.

## Import transactions and recovery

1. Coordinate the Files URL while its security scope remains active; copy it into app-private temporary storage off the main thread.
2. Check ZIP structure/metadata, enforce paths and budgets, reject symlinks and conflicting names.
3. Extract into a random `Staging/<UUID>` directory; count actual output and compare CRCs and declared lengths. Reject mixed-case/Unicode path collisions and file/parent conflicts.
4. Locate a single shallowest web entry, preferring root `index.html` or `www/index.html`. MV/MZ detection checks core filenames plus required System.json presence.
5. Hash sorted relative paths, byte lengths and content using SHA-256. Repacked identical path/content imports are duplicates.
6. Move the validated installation to `Games/<UUID>`, then atomically write schema-v1 library metadata. On failure, remove only this uncommitted import. Existing games are untouched.

On reopen, unreferenced installations and interrupted staging directories are moved to `Recovery/`, not silently erased. Malformed/unknown metadata versions fail closed and preserve files. No legacy schema migration is needed yet: v1 is the initial schema; future versions require an explicit migration. Archive retains the original game record (including storage identity/origin) alongside the files in Recovery before updating the library. On startup, still-referenced games from an interrupted archive are restored to their original location. There is not yet a recovery/restore UI.

Limits: 1 GiB ZIP, 2 GiB expanded total, 256 MiB per file, 20,000 entries, depth 32, 1,024 UTF-8 bytes per path; compression ratios over 500:1 for entries larger than 1 MiB are rejected. No unlimited extraction fallback.

## Runtime isolation

- One foreground session; server binds `127.0.0.1` on the game's saved port, never all interfaces.
- Each game has a distinct persistent WebKit data-store UUID, port and random resource-path token. No port rotation that silently loses storage origins.
- GET/HEAD only; validate Host, token, percent decoding, root containment and symlinks. Never expose directory listings or writes.
- MIME mappings for HTML, ES modules, JSON, CSS, images, fonts, audio and WASM; single byte ranges and HEAD for media. Stream files in 256 KiB chunks. Header/connection/lifetime bounds constrain resource use.
- Default CSP blocks remote resources and network requests. Scripts, inline code and eval are allowed within the untrusted game's web sandbox for engine compatibility. Frames/plugins/forms are blocked.
- Deny external navigation, new windows, camera/microphone capture and native message handlers. No arbitrary native invocation, shell or filesystem bridge.
- The game saves itself using WebKit storage. EverPlay does not claim it can serialize arbitrary JavaScript memory. Virtual keyboard events are synthetic and will not satisfy APIs requiring trusted physical events.

The token is a local capability, not a replacement for future encrypted/authenticated device pairing. A malicious game cannot receive access to other games via an app bridge because no such bridge exists.

## Persistence choices

Small bounded library metadata/settings use Codable JSON with atomic replacement. WebKit owns game localStorage/IndexedDB. No external database service is needed. SQLite is reserved for the high-volume translation memory milestone; an empty SQLite layer is deliberately not presented as implemented functionality. User API keys will belong in Keychain, not library JSON.

## Future modules

TranslationEngine, ModManager, CheatManager, SaveManager and DevicePairing remain separate milestones. Asset overlays must resolve ahead of immutable original game assets. Save writes and mod activation need explicit backups and rollback transactions before they are exposed in UI. See the focused design documents; they are plans, not implementations.
