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

### Resumed environment, 2026-10-22

The new cloud environment did not retain the private Contract Demon package, its browser profile or the old 8.2.0 runtime cache. A new authorized ZIP/download is required; the historical real-game results below have not been rerun here.

`scripts/build-renpy-820-template.py` now reproducibly rebuilds a matching **trusted original fixture** from the official 8.2.0 SDK/web archives, verifying both pinned SHA-256 values before extraction. It accepts no third-party game argument and does not overwrite the standard 8.5.3 fixture. The generated ZIP stays in ignored `artifacts/`. This original fixture passed the browser interaction/route/save/load/full-browser-restart assertions on 8.2.0 in the current environment:

```sh
python3 scripts/build-renpy-820-template.py
PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/usr/bin/chromium node scripts/test-renpy-browser.mjs \
  --fixture artifacts/EverPlayRenPy820Template.zip
```

Override only the download cache location with `EVERPLAY_RENPY82_CACHE` if desired. The RenPy Actions workflow now offers runtime choices `8.5.3` (existing default) and `8.2.0`; both require the native original-fixture test plus all four existing acceptance cases. The 8.2.0 option tests a trusted runtime template, not a Contract Demon package or the 8.5.3 desktop-conversion proof.

**Native 8.2.0 result (source `cc87afc43c85d418db99abe257edccd536ac7334`, runtime input `8.2.0`):**

- [Run 39746629710](https://github.com/Pander0212/EverPlay/actions/runs/39746629710) **passed** on `macos-15-intel`/Xcode 16.4: `testRenPyDesktopArchiveRunsAndRestoresSaveInWebKit` (47.489 s), all four foundation acceptance cases and all 37 core tests. The trusted fixture therefore runs on the RenPy 8.2.0 web runtime inside native EverPlay (production importer, `LocalGameServer`, `GameSession`/WKWebView, virtual keys, save/load, session reopen) in the iOS simulator.
- The preceding dispatch, [run 39743473185](https://github.com/Pander0212/EverPlay/actions/runs/39743473185), on the same source and runtime failed for an infrastructure reason: `EverPlayUITests-Runner ... failed to initialize for UI testing (Timed out while loading Accessibility.)`. In that run the RenPy case (76.197 s), the HTTP case and the WebKit-isolation case had passed; only the UI-test runner never started. The next independent dispatch passed without source changes. This is recorded as a simulator start-up failure, not as evidence of RenPy instability, and it remains a reason for the planned lifecycle/stress coverage.

This still does not test Contract Demon itself: it proves the matching runtime version works natively with our own fixture.

The [ios-builder assessment](IOS_BUILDER_REVIEW.md) explains why the existing CI is retained, where MobAI could add interactive access, and the remaining private transport prerequisite. Do not run our `window.everplayProbe` assertions against Contract Demon: its native test still needs to be implemented and exercised with the actual game through real menu interactions and read-only `renpy_get` observations.

The owner supplied download access to [Contract Demon](https://nomnomnami.itch.io/contract-demon). A refreshed link successfully downloaded **Contract Demon 2.2.7 PC**, 84,098,513 bytes, on 2026-10-21. The earlier proxy blocker is resolved for this download. Package SHA-256: `174ee799d011887b82ac000b4c85e1427a281011d1134c096882017e6b7346bd`.

Passive ZIP inspection found RenPy **8.2.0.24012702**, `script_version.txt` `(8, 2, 0)`, one `game/archive.rpa` and additional translation fonts. A matching official 8.2.0 SDK/web runtime was downloaded and verified against its release SHA-256 list:

- SDK: `e79ec1014bad6adba69336f90802e89ae7a70172c1bb9c15301267390e9d7b38`
- Web: `6db580f557bd77d403b9c29b84e33ec2fe9fc154e5d38056d976703093dae92f`

Only our reviewed fixture was passed to the host SDK's `web_build` to create a matching runtime template. ZIP operations removed the template's `game/` entries and inserted Contract Demon's game data, excluding desktop caches/saves. No downloaded game Python or RPA pickle was executed/deserialized on the host. Its 41,824,343-byte RPA is preserved byte-for-byte (SHA-256 `95d81239af731ea964534e16c5a889a3ce427f231cf1635a9c9ff50c08c8b037`). Runtime execution takes place inside Chromium/WebAssembly with the production CSP and external browser requests blocked.

Observed: language selection, German title menu, animated first scene, translated dialogue advancement and saving through the normal menu. The saved slot survives a full browser-process restart and loads back into the saved dialogue. Assertions then verify that advancing changes the dialogue and loading through the normal UI/confirmation restores the exact previously captured dialogue. The local restore harness completed successfully (`artifacts/contract-result.json`). This is a browser compatibility probe, not a native EverPlay/iPhone result for Contract Demon. Audio output, full playthrough, choices, rollback, all translations, memory pressure and physical-device behavior are unverified. Browser autoplay warnings appeared before the first gesture. The first automated restart attempt clicked during the splash sequence; startup checks must wait for the actual RenPy main-menu screen and its animated controls to become interactive; the corrected harness verifies the load screen before selecting the slot.

The private downloaded package and local browser harness/results remain outside tracked source (tool cache and ignored `artifacts/`). In the retained workspace, the matching SDK/template/repacked web directory are under `/workspace/everplay-tools/renpy-8.2-cache/`; `node artifacts/contract-restore.mjs` repeats the restart/load/dialogue assertions against the previously UI-created local save and its fixed loopback origin. These private local test inputs are not restored by a Git checkout alone. No game assets, signed URLs or save files are committed or uploaded to CI. Do not use the repository's pinned 8.5.3 fixture builder on this third-party package.

## Licensing and provenance

The fixture is original MIT-licensed EverPlay source. No commercial game assets are used. The generated package retains the SDK's full `LICENSE.txt` as `RENPY-LICENSE.txt`, the fixture's MIT license and the exact engine source-release/build-source references. RenPy is largely MIT, with LGPL and other third-party components; those obligations remain applicable to the unmodified WebAssembly runtime. No downloaded engine binaries are committed. Review corresponding-source/rebuild/replacement obligations and the final distribution bundle before an end-user engine release; this experiment is not a completed distribution-license audit.

Authoritative references: [RenPy web documentation](https://www.renpy.org/doc/html/web.html), [save/load semantics](https://www.renpy.org/doc/html/save_load_rollback.html#retaining-data-after-load), [pinned release](https://github.com/renpy/renpy/releases/tag/8.5.3.26051504), [component license documentation](https://www.renpy.org/doc/html/license.html).
