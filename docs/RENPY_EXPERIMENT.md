# RenPy desktop-data experiment

## Goal and current scope

The owner's priority is existing Windows/Linux RenPy games, with Windows first. This experiment tests whether **desktop game data**, rather than a pre-existing web export, can run through EverPlay's existing sandboxed WebKit runtime. It does not run Windows executables or emulate Windows.

RenPy 8.5.3 (`8.5.3.26051504`) is pinned. `scripts/build-renpy-probe.py` builds our original fixture into a real combined Windows/Linux distribution, verifies both launchers are present, and takes only `game/story.rpa` and `game/script_version.txt`. The archive contains compiled scripts; original `.rpy` files are excluded. The official builder produces a WebAssembly package from those desktop data. The test verifies that `story.rpa` is retained **byte-for-byte**.

**Current result:** the generated package runs in Chromium under EverPlay's current CSP and private URL-prefix layout. Actual canvas clicks change gold/select a route; a save restores after further changes and after a complete browser process restart. The native EverPlay test also passed in the iOS simulator, including production key delivery, save/load and saved-slot restoration after reopening the session. No general RenPy compatibility badge or import support is enabled in the app.

A second **data-only repack** experiment also passed in Chromium. It builds a different, Windows-only fixture with initial gold **37**, while the runtime template's original game starts with **10**. After packaging that trusted fixture, conversion uses only ZIP operations: remove the template's game entries, insert the Windows archive unchanged, and retain the existing engine/common code. No game code executes during this repack stage. The new game starts at 37, responds to clicks, saves at 47, changes to 57, reloads 47 and restores 47 after browser-process restart. This distinguishes actual replacement from accidentally running the template game. This second variant has **not** yet been separately exercised in native WebKit.

An additional local platform comparison built PC, Windows-only and Linux-only distributions of the same original fixture. Windows-only had an `.exe` and no `.sh`; Linux-only had a `.sh` and no `.exe`; all three contained byte-identical `story.rpa` data. This verifies the shared-data observation for this fixture, not every third-party package.

## Reproduce

```sh
python3 scripts/build-renpy-probe.py
# Linux cloud with the installed browser:
PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/usr/bin/chromium node scripts/test-renpy-browser.mjs
# Repeat the different Windows-game/data-only repack and browser checks:
PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/usr/bin/chromium python3 scripts/test-renpy-data-only.py
# On the configured macOS/Xcode runner:
bash scripts/test-ios.sh
python3 scripts/verify-ios-tests.py artifacts/ios-build-test.log testRenPyDesktopArchiveRunsAndRestoresSaveInWebKit
```

The SDK and web runtime are downloaded from the official release and checked against pinned SHA-256 values. They live in ignored `.build-tools/renpy` (override with `EVERPLAY_RENPY_CACHE`). The generated `App/Resources/EverPlayRenPyProbe.zip` is ignored. The normal app checkout has no bundled RenPy engine; the optional native test explicitly skips when this generated fixture is absent. The separate **RenPy desktop-data experiment** workflow is manually dispatched and requires this test to pass in addition to all four existing native acceptance cases. Its output includes logs and a WKWebView screenshot; it does not publish an iPhone release.

`AppUnitTests/RenPyRuntimeTests.swift` imports the generated ZIP through `LibraryStore`, serves it through `LocalGameServer`, attaches the production `GameSession` WebView to a real window, and exercises production virtual-key delivery for collect/save/load. It checks the state published by the original RenPy fixture, then reopens a new GameSession with the same game identity and loads the saved slot. This native case tests **session reopen**, not termination of the entire iOS app. The browser case separately tests a full browser-process restart. Neither replaces an iPhone test.

The tiny fixture has explicit diagnostic state in `window.everplayProbe`. It is written by Python running in the real engine; it is not a fake JavaScript implementation of RenPy. No native scripting bridge is added to the app. Fixture fixes preserve RenPy's normal game-start context and use documented `renpy.retain_after_load()` semantics for its editable screen.

## Important boundary: this is not yet a user-game converter

RenPy's packaging tools execute game Python during inspection/build. The script deliberately accepts **no arbitrary input-game path**: it builds only the original, reviewed fixture in this repository. Do not run downloaded desktop games through this host-side builder as though it were a passive archive reader. A future conversion service would need a separate, disposable execution sandbox with explicit resource/network/filesystem boundaries.

Direct desktop ZIP/RPA import inside EverPlay is still unsupported. The data-only browser proof supports investigating the next step: mount validated desktop data with a pinned runtime **inside the app’s web sandbox**, without running user-game Python during cloud conversion and without rewriting original installations. The current repacker handles only the two known files in our fixture; arbitrary paths/assets, runtime selection, import transactions and user-facing recovery are not implemented. Do not silently accept unknown engine versions.

## Compatibility limits and next work

1. Preserve the passed native simulator gate: source `32ae7adab370b7126982a7953b82e8a92e2b7666`, [run 39604184241](https://github.com/Pander0212/EverPlay/actions/runs/39604184241), passed the RenPy case in 28.304 seconds, all four existing app acceptance cases and 37 core tests. The first attempt stopped at a screenshot-test compiler error; the callback API correction is included in this successful source.
2. Prototype data-only desktop import into an isolated, pinned runtime; preserve immutable originals and stable per-game save origins. Validate paths, archive limits, game identity and runtime selection before launch.
3. Extend the fixture matrix to supported RenPy 8 versions, loose `.rpyc` files, RPA archives, image/audio/dialogue assets and real choice/rollback behavior. The current fixture is intentionally small.
4. Treat RenPy 7/Python 2, incompatible compiled scripts, native Python extensions/DLLs, external networking, threads, custom launchers and DRM/encryption as separate compatibility questions. A shared `game` folder does not guarantee that any of these work.
5. Validate lifecycle, memory pressure, audio unlock, save isolation and real-device behavior. A simulator success cannot establish iPhone memory/performance limits.
6. Only then expose honest supported-version import/capability UI. Existing desktop saves need their own version/format/security tests; this experiment creates new saves in the web runtime.

## Requested real-game check

The owner supplied download access to [Contract Demon](https://nomnomnami.itch.io/contract-demon). On 2026-10-21, both the supplied R2 download host and itch.io download page were blocked by the cloud network proxy (`Tunnel connection failed: 403 Forbidden`), before an origin response. No game bytes were downloaded or executed; its engine version and compatibility remain unknown. The direct signed URL advertises a 60-second lifetime; future testing may need a refreshed link or a locally supplied ZIP. Signed URLs are not retained in source or configuration. The two exact destination hosts were prepared in the environment configuration draft; saving that draft does not activate networking.

## Licensing and provenance

The fixture is original MIT-licensed EverPlay source. No commercial game assets are used. The generated package retains the SDK's full `LICENSE.txt` as `RENPY-LICENSE.txt`, the fixture's MIT license and the exact engine source-release/build-source references. RenPy is largely MIT, with LGPL and other third-party components; those obligations remain applicable to the unmodified WebAssembly runtime. No downloaded engine binaries are committed. Review corresponding-source/rebuild/replacement obligations and the final distribution bundle before an end-user engine release; this experiment is not a completed distribution-license audit.

Authoritative references: [RenPy web documentation](https://www.renpy.org/doc/html/web.html), [save/load semantics](https://www.renpy.org/doc/html/save_load_rollback.html#retaining-data-after-load), [pinned release](https://github.com/renpy/renpy/releases/tag/8.5.3.26051504), [component license documentation](https://www.renpy.org/doc/html/license.html).
