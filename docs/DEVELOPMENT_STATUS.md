# Development status

Recorded **2026-10-21**. The initial empty repository now contains an actual SwiftUI iOS application and a tested portable foundation. Source is pushed to [`codex/everplay-foundation`](https://github.com/Pander0212/EverPlay/tree/codex/everplay-foundation). **The complete four-case native acceptance gate passed on the iPhone simulator. Physical-device validation remains open.**

## Implemented and tested

- **37 passing Swift XCTest cases on Linux and macOS:** real ZIP extraction, CRC verification, traversal/Unicode/case/symlink defenses, actual-byte/decompression limits, nested entry discovery, duplicate detection and transaction rollback.
- Structural HTML5/MV/MZ detection, rejection of incomplete engine layouts and unsupported packages, and a regression test for symlinked directory ancestors.
- Persistent library identities/origins/settings, playtime, distinct game records, archive retention and interrupted-import/archive recovery.
- Production HTTP routing: Host/token enforcement, traversal/symlink boundaries, MIME, HEAD, byte ranges and malformed request rejection.
- The bundled original demo ZIP passes the real Swift importer and production routing tests.
- **5 passing Node tests and 4 passing Chromium integration tests:** original demo gameplay, Japanese dialogue loading, gold/inventory/day changes, malformed-save preservation and saves surviving a complete browser process restart.
- The pinned XcodeGen source build generates the real app and native test targets. Dependency setup is repeatable with frozen locks. Swift's official download signature was verified; the corresponding archive digest is pinned in setup.
- The iOS application has compiled with Xcode 16.4 and native XCTest/UI suites have actually executed on the GitHub macOS simulator runner. Compilation is no longer an unverified assumption.

## Native acceptance passed

The native suite requires these four tests to pass, and `scripts/verify-ios-tests.py` rejects a zero-test or incomplete run:

1. Real HTTP transport of the imported demo, JS MIME, media range and rejected route.
2. WKWebView execution, separate game storage, virtual-key input and session reopen.
3. Demo ZIP import, touch play, inventory/save, exit and full application relaunch.
4. Both virtual-control groups' draggable/saved layout, portrait/landscape gameplay and hiding controls.

Tested application/test source: `2eda7f330b3a0c59dc2e2ea97389c007c7cd5e01`. [iOS run 39564217383](https://github.com/Pander0212/EverPlay/actions/runs/39564217383) **passed all four cases**, compiled the application/test targets with Xcode 16.4, and passed all 37 core tests on macOS. The UI persistence case passed in 106.577 seconds and the controls/orientation case in 85.491 seconds. The workflow uploaded simulator results and a simulator application. Browser [run 39564217159](https://github.com/Pander0212/EverPlay/actions/runs/39564217159) and repository [run 39564217066](https://github.com/Pander0212/EverPlay/actions/runs/39564217066) also passed. This is the accepted foundation baseline; the later RenPy experiment below has its own source/run evidence.

The preceding [run 39475323802](https://github.com/Pander0212/EverPlay/actions/runs/39475323802), source `b1a08fdd1749f9689cdeb83727b185ab9a0b371d`, compiled successfully and passed the HTTP, WebKit-isolation and **complete control-layout/landscape** cases. Giving group dragging priority over individual key gestures fixed the D-pad movement failure. The full run nevertheless failed: the demo's expected inventory did not appear within 20 seconds after application relaunch. That log did not distinguish page readiness from a restored-save mismatch. The current test waits up to 60 seconds for the demo’s module/JSON-ready status independently, then checks the exact saved inventory without resetting game data. Failures retain the accessibility hierarchy and fixed, content-free runtime lifecycle messages.

Earlier native failures exposed a Darwin canonical-path bug and test-harness readiness/sheet-gesture issues. Intel simulator cold boot required a bounded 600-second window during Apple data migration. A previous sequence also showed a blank WebView/loading indicator after implicitly terminating an active game between tests; normal exit is now used for independent test cleanup. The current normal-exit/relaunch acceptance case passes; this does not prove that the earlier intermittent blank-loading behavior or active-game force-quit/background recovery is fixed. Retain a dedicated lifecycle/stress follow-up before broad compatibility work.

## RenPy desktop-data experiment (owner-prioritized follow-up)

The owner prioritized Windows/Linux RenPy games on 2026-10-21. See [the experiment and reproduction steps](RENPY_EXPERIMENT.md). Source `32ae7adab370b7126982a7953b82e8a92e2b7666` contains an original RenPy 8.5.3 fixture, a reproducible desktop-package build, byte-preserving reuse of its compiled `story.rpa`, browser integration checks and an optional native integration case. No original `.rpy` source is present in the desktop conversion input.

Both Chromium scenarios passed real canvas clicks, route selection, save/load and save restoration after complete browser-process restart under the current app CSP and a private URL prefix. The second scenario uses a different Windows-only archive and a data-only repack that executes no game code during conversion. The [native experiment run 39604184241](https://github.com/Pander0212/EverPlay/actions/runs/39604184241) passed: the RenPy native case (28.304 seconds), all four existing foundation acceptance cases and all 37 core tests. This verifies native session reopen; the distinct Windows-only replacement scenario remains browser-tested only. The refreshed Contract Demon download succeeded. Its RenPy 8.2.0 desktop data starts in a matching browser runtime: German menus/dialogue and UI saving work, and saved dialogue restores after browser restart and after further progression. See the experiment document for scope and evidence; this game has not been tested in native EverPlay. Direct import of arbitrary desktop ZIP/RPA packages in the app is **not implemented**; the builder executes only our trusted fixture. Do not run unknown games through host-side RenPy packaging tools as though they were passive file parsers.

## Implemented but untested on physical devices

- Real iPhone installation/playback and external Files/iCloud document-provider selection. The demo exercises the same coordinated copy/import path, but does not claim every third-party document provider was tested.
- External keyboards/controllers, device-specific audio codecs, OS backgrounding/resource pressure and arbitrary commercial games.
- Device signing/distribution. Local ad-hoc **simulator** signing needs no Apple credentials and does not produce an installable iPhone IPA.

## Partially implemented

- RenPy: a matched-version desktop-data experiment; user-facing desktop import, version selection and broad game compatibility are not implemented.
- MV/MZ: tested structural detection and the shared web runtime; no legitimate full MV/MZ engine export has been exercised yet. No engine runtime assets are redistributed.
- Saves: persistent per-game browser storage is wired; native backup/export/restore and game-specific save decoding remain planned.
- Recovery: original data and origin metadata are retained, with automatic recovery of interrupted archives still referenced by the library. Restore/purge UI remains planned.
- Controls: touch and per-game virtual groups exist; individual remapping and orientation-specific layouts are future work.

## Planned

Provider/Keychain integration, SQLite translation memory, safe live/pre-translation, `.evermod` installation/overlays/rollback, save/cheat adapters, desktop TypeScript MCP Bridge, encrypted pairing, folder imports and additional engines. Unity is excluded.

## Blocked and current prerequisites

- The cloud machine is Linux; native compilation uses GitHub's macOS runner. It is not necessary to use the owner's laptop.
- GitHub API reads and native Git pushes work using supplied platform authentication. Direct job-log/artifact storage domains can still be restricted; bounded failure diagnostics are also published as API-readable GitHub check annotations.
- The normal four-case simulator acceptance gate passed. Earlier intermittent startup observations still need dedicated lifecycle/stress validation; one passing run is not a universal reliability claim.
- There is no signed device release, Apple distribution configuration or physical-device result.
- The environment configuration is saved as a draft. Publishing a new Codex snapshot and restoring it in a new Codex task have not been verified. Code is remotely recoverable from the pushed Git branch rather than only a local commit.

## Validation evidence

| Actually executed | Result |
| --- | --- |
| `bash scripts/test-core.sh` on Linux | 37 XCTest tests passed, 0 failed/skipped. Swift Testing's trailing “0 tests” is the unused second runner, not the executed XCTest suite. |
| Same core command on GitHub macOS | Passed after the canonical-path regression fix. |
| `npm run check` and `npm test` | Syntax passed; 5 Node tests passed. |
| `npm run test:browser` | 4 Chromium integration tests passed locally and in GitHub Actions. |
| Dependency/repository workflow | Passed; npm audit reported 0 vulnerabilities, tracked-file screening/action pin checks passed. Basic screening is not a complete security audit. |
| iOS app compilation and simulator execution | Passed for source `2eda7f3`: all four required HTTP/WebKit/UI cases, zero native failures; simulator `.app` uploaded. |
| Real iPhone | Not run. |

### Diagnosed failures and corrections

- Darwin enumeration can return `/private` aliases even when a base URL uses `/var`. Relative entry-point calculation now canonicalizes **both** base and enumerated URLs and compares path components; the former character-count slicing produced corrupt entry paths and wrong MV/MZ detection. The new test passes on Linux and macOS.
- The native demo test now waits for its explicit module/JSON readiness marker, rather than assuming navigation completion means asynchronous resource loading finished.
- The game menu starts with its large sheet detent. Menu tests scroll inside the form and target the native switch thumb, with bounded state-change assertions; failures identify the actual caller and switch frames.
- Swift UI-test coordinate dragging and rectangle text formatting were corrected after real Apple-SDK compiler errors.
- The initial malformed-save browser test seeded invalid storage in a live page, whose legitimate pagehide handler replaced it. It now seeds before game initialization and verifies the invalid save is preserved. No assertion was disabled.

## Cloud configuration

On 2026-10-21, `bash scripts/setup-cloud.sh` was rerun successfully without changing source or locks, followed by 37 passing Linux core tests, 5 Node tests and 4 Chromium tests. The versioned setup script installs/verifies the toolchain if needed and refreshes frozen dependencies. Startup instructions identify the existing checkout and functional tests, and prohibit unnecessary worktrees. Custom network draft additions preserve presets. Draft saving does not execute scripts, publish a snapshot or prove new-task restoration.

## Precise next task

1. Continue from the pushed branch/current checkout. Preserve the passing four-case baseline at `2eda7f3` (run 39564217383). Next, add focused repeated lifecycle coverage for graceful reopen, active-game termination and background/foreground transitions; inspect retained runtime diagnostics if the earlier intermittent blank-loading behavior recurs. Do not hide failures with automatic test retries or reset saved game data.
2. After native acceptance, validate an external Files ZIP on a device when signing/distribution is available. No manual Windows-laptop setup is needed for the cloud build.
3. Follow the owner’s updated priority: continue the limited RenPy Windows/Linux data-import investigation in RENPY_EXPERIMENT.md while preserving the baseline. Once that scope is agreed/tested, advance to MV/MZ with a legally usable minimal web export. Do not redistribute commercial engine/game assets without the appropriate rights. Verify startup, audio, touch and saves before adding narrowly scoped compatibility shims.
4. Follow translation → mods/cheats/saves → Bridge → additional engines in roadmap order. Preserve the working HTML5 test fixture and immutable installations.
5. For future TestFlight/device work, verify Apple's current SDK/submission requirements, configure a unique bundle ID/team and secure signing outside the repository, and test a genuinely signed device build. Never request private-key values in chat.

## Complete source/configuration inventory

All files below were created from the initially empty repository; generated projects, build caches and validation reports are excluded.

```text
.github/workflows/ios.yml
.github/workflows/renpy.yml
.github/workflows/security.yml
.github/workflows/web.yml
.gitignore
App/EverPlayApp.swift
App/Info.plist
App/LibraryModel.swift
App/Resources/EverPlayDemo.zip
App/Resources/PrivacyInfo.xcprivacy
App/Resources/ThirdPartyNotices.txt
App/Views/GamePlayerView.swift
App/Views/RootView.swift
App/WebRuntime/GameSession.swift
App/WebRuntime/LocalGameServer.swift
AppTests/EverPlayUITests.swift
AppUnitTests/GameSessionTests.swift
AppUnitTests/LocalGameServerTests.swift
AppUnitTests/RenPyRuntimeTests.swift
DemoGame/dialogue.json
DemoGame/game.js
DemoGame/index.html
DemoGame/state.js
DemoGame/style.css
Experiments/RenPyProbe/game/script.rpy
LICENSE
Package.resolved
Package.swift
README.md
Sources/EverPlayCore/GameDetector.swift
Sources/EverPlayCore/GameImporter.swift
Sources/EverPlayCore/HTTPResourceRouter.swift
Sources/EverPlayCore/LibraryStore.swift
Sources/EverPlayCore/Models.swift
Sources/EverPlayCore/SafePath.swift
Tests/EverPlayCoreTests/HTTPResourceRouterTests.swift
Tests/EverPlayCoreTests/ImporterTests.swift
docs/ARCHITECTURE.md
docs/DEVELOPMENT_STATUS.md
docs/ENGINE_COMPATIBILITY.md
docs/IOS_BUILD.md
docs/KNOWN_LIMITATIONS.md
docs/MCP.md
docs/MODDING.md
docs/RENPY_EXPERIMENT.md
docs/RESEARCH.md
docs/RESEARCH_METADATA.json
docs/ROADMAP.md
docs/TRANSLATION.md
package-lock.json
package.json
playwright.config.js
project.yml
scripts/build-renpy-probe.py
scripts/check-repository.py
scripts/generate-project.sh
scripts/package-demo.py
scripts/report-ci-failure.py
scripts/setup-cloud.sh
scripts/test-core.sh
scripts/test-ios.sh
scripts/test-renpy-browser.mjs
scripts/test-renpy-data-only.py
scripts/verify-ios-tests.py
tests/browser/demo.spec.js
tests/demo-state.test.js
```
