# Development status

Recorded **2026-10-20**. The initial empty repository now contains an actual SwiftUI iOS application and a tested portable foundation. Source is pushed to [`codex/everplay-foundation`](https://github.com/Pander0212/EverPlay/tree/codex/everplay-foundation). **The full native acceptance gate is still being validated.**

## Implemented and tested

- **37 passing Swift XCTest cases on Linux and macOS:** real ZIP extraction, CRC verification, traversal/Unicode/case/symlink defenses, actual-byte/decompression limits, nested entry discovery, duplicate detection and transaction rollback.
- Structural HTML5/MV/MZ detection, rejection of incomplete engine layouts and unsupported packages, and a regression test for symlinked directory ancestors.
- Persistent library identities/origins/settings, playtime, distinct game records, archive retention and interrupted-import/archive recovery.
- Production HTTP routing: Host/token enforcement, traversal/symlink boundaries, MIME, HEAD, byte ranges and malformed request rejection.
- The bundled original demo ZIP passes the real Swift importer and production routing tests.
- **5 passing Node tests and 4 passing Chromium integration tests:** original demo gameplay, Japanese dialogue loading, gold/inventory/day changes, malformed-save preservation and saves surviving a complete browser process restart.
- The pinned XcodeGen source build generates the real app and native test targets. Dependency setup is repeatable with frozen locks. Swift's official download signature was verified; the corresponding archive digest is pinned in setup.
- The iOS application has compiled with Xcode 16.4 and native XCTest/UI suites have actually executed on the GitHub macOS simulator runner. Compilation is no longer an unverified assumption.

## Native acceptance validation in progress

The native suite requires these four tests to pass, and `scripts/verify-ios-tests.py` rejects a zero-test or incomplete run:

1. Real HTTP transport of the imported demo, JS MIME, media range and rejected route.
2. WKWebView execution, separate game storage, virtual-key input and session reopen.
3. Demo ZIP import, touch play, inventory/save, exit and full application relaunch.
4. Both virtual-control groups' draggable/saved layout, portrait/landscape gameplay and hiding controls.

The latest source under validation is `f68340db35903c08269b686eb586d95ad2fb71a4`, [iOS run 39467612506](https://github.com/Pander0212/EverPlay/actions/runs/39467612506). Browser and security workflows for this source have passed. The first three named native acceptance cases passed in preceding ARM and Intel simulator runs. The Intel retry failed while waiting for WebKit content before it reached the controls assertion; startup waiting is now bounded at 60 seconds and preserves the actual accessibility hierarchy on failure. The complete gate is being rerun. Earlier native failures exposed a real Darwin path bug and test-harness readiness/sheet-gesture issues; they are not described as successful runs.

## Implemented but untested on physical devices

- Real iPhone installation/playback and external Files/iCloud document-provider selection. The demo exercises the same coordinated copy/import path, but does not claim every third-party document provider was tested.
- External keyboards/controllers, device-specific audio codecs, OS backgrounding/resource pressure and arbitrary commercial games.
- Device signing/distribution. Local ad-hoc **simulator** signing needs no Apple credentials and does not produce an installable iPhone IPA.

## Partially implemented

- MV/MZ: tested structural detection and the shared web runtime; no legitimate full MV/MZ engine export has been exercised yet. No engine runtime assets are redistributed.
- Saves: persistent per-game browser storage is wired; native backup/export/restore and game-specific save decoding remain planned.
- Recovery: original data and origin metadata are retained, with automatic recovery of interrupted archives still referenced by the library. Restore/purge UI remains planned.
- Controls: touch and per-game virtual groups exist; individual remapping and orientation-specific layouts are future work.

## Planned

Provider/Keychain integration, SQLite translation memory, safe live/pre-translation, `.evermod` installation/overlays/rollback, save/cheat adapters, desktop TypeScript MCP Bridge, encrypted pairing, folder imports and additional engines. Unity is excluded.

## Blocked and current prerequisites

- The cloud machine is Linux; native compilation uses GitHub's macOS runner. It is not necessary to use the owner's laptop.
- GitHub API reads and native Git pushes work using supplied platform authentication. Direct job-log/artifact storage domains can still be restricted; bounded failure diagnostics are also published as API-readable GitHub check annotations.
- Required native acceptance failures must be fixed before milestone 1 is called accepted. A simulator build alone does not validate all functionality.
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
| iOS app compilation and simulator execution | Confirmed; complete four-case acceptance result is still pending for the current source. |
| Real iPhone | Not run. |

### Diagnosed failures and corrections

- Darwin enumeration can return `/private` aliases even when a base URL uses `/var`. Relative entry-point calculation now canonicalizes **both** base and enumerated URLs and compares path components; the former character-count slicing produced corrupt entry paths and wrong MV/MZ detection. The new test passes on Linux and macOS.
- The native demo test now waits for its explicit module/JSON readiness marker, rather than assuming navigation completion means asynchronous resource loading finished.
- The game menu starts with its large sheet detent. Menu tests scroll inside the form and target the native switch thumb, with bounded state-change assertions; failures identify the actual caller and switch frames.
- Swift UI-test coordinate dragging and rectangle text formatting were corrected after real Apple-SDK compiler errors.
- The initial malformed-save browser test seeded invalid storage in a live page, whose legitimate pagehide handler replaced it. It now seeds before game initialization and verifies the invalid save is preserved. No assertion was disabled.

## Cloud configuration

The versioned setup script installs/verifies the toolchain if needed and refreshes frozen dependencies. Startup instructions identify the existing checkout and functional tests, and prohibit unnecessary worktrees. Custom network draft additions preserve presets. Draft saving does not execute scripts, publish a snapshot or prove new-task restoration.

## Precise next task

1. Continue from the pushed branch/current checkout and inspect the latest native workflow result. Fix any remaining acceptance failure and require all four named native cases to complete, not just an open port or successful compile.
2. After native acceptance, validate an external Files ZIP on a device when signing/distribution is available. No manual Windows-laptop setup is needed for the cloud build.
3. Advance to milestone 2 with a legally usable minimal MV/MZ web export. Do not redistribute commercial engine/game assets without the appropriate rights. Verify startup, audio, touch and saves before adding narrowly scoped compatibility shims.
4. Follow translation → mods/cheats/saves → Bridge → additional engines in roadmap order. Preserve the working HTML5 test fixture and immutable installations.
5. For future TestFlight/device work, verify Apple's current SDK/submission requirements, configure a unique bundle ID/team and secure signing outside the repository, and test a genuinely signed device build. Never request private-key values in chat.

## Complete source/configuration inventory

All files below were created from the initially empty repository; generated projects, build caches and validation reports are excluded.

```text
.github/workflows/ios.yml
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
DemoGame/dialogue.json
DemoGame/game.js
DemoGame/index.html
DemoGame/state.js
DemoGame/style.css
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
docs/RESEARCH.md
docs/RESEARCH_METADATA.json
docs/ROADMAP.md
docs/TRANSLATION.md
package-lock.json
package.json
playwright.config.js
project.yml
scripts/check-repository.py
scripts/generate-project.sh
scripts/package-demo.py
scripts/report-ci-failure.py
scripts/setup-cloud.sh
scripts/test-core.sh
scripts/test-ios.sh
scripts/verify-ios-tests.py
tests/browser/demo.spec.js
tests/demo-state.test.js
```
