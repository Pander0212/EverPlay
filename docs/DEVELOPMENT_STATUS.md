# Development status

Recorded **2026-10-20**, from the initial empty `Pander0212/EverPlay` checkout. This is the first independently testable foundation slice. **Milestone 1's full iOS acceptance criterion remains open until the native build/UI tests run.**

## Implemented and tested

- The actual Swift package compiles on Linux with Swift 6.0.3.
- ZIP extraction, CRC checks, path/Unicode/case defenses, symlink rejection, decompression limits, nested entry discovery, duplicate detection and rollback.
- Structural HTML5/MV/MZ detection, including rejection of incomplete MV/MZ fixture layouts and unsupported non-web packages.
- Persistent library identities/origins/settings, independent game records, archive retention and interrupted-import/archive recovery.
- The portable production HTTP router: Host/token validation, traversal/symlink defenses, MIME types, HEAD, media ranges and malformed request rejection.
- Original demo packaged as a reproducible ZIP, imported through the real Swift importer and served through the production routing logic in tests.
- Original demo touch/keyboard gameplay, Japanese dialogue loading, gold/inventory/day state, malformed-save preservation and browser save persistence across both page reopen and a complete Chromium process restart.
- XcodeGen 2.44.1 built from its pinned source/lock and generated the actual Xcode project, application resources and native test targets.
- Dependency setup script executed successfully with frozen dependency versions. Official Swift download signature verified before execution; its digest is pinned in the reproducible setup script.

## Implemented but untested on the target platform

- SwiftUI application target and Library/Import/Settings screens, license view and native full-screen player/menu.
- Security-scoped/coordinated Files import and bounded document-provider copy.
- Network.framework loopback server, streaming and connection lifecycle.
- WKWebView startup/navigation policy, per-game persistent website data store and media behavior.
- Virtual keyboard controls, drag positioning and saved transparency/layout.
- Native HTTP integration test and app UI acceptance test.
- GitHub macOS/HTML5/security workflows. Project generation and syntax parsing are verified; Apple-SDK type checking is not.

## Partially implemented

- MV/MZ: structural detection plus common web-runtime routing; real exported games, engine APIs and audio/save/plugin compatibility remain unverified.
- Save handling: persistent browser storage is wired, and demo persistence is browser-tested; native backup/export/restore and game-specific save parsing do not exist yet.
- Recovery: data and archive metadata are preserved, and interrupted archives restore automatically when still referenced; a user-facing archive restore/purge screen remains planned.
- Controls: touch and configurable virtual groups exist; device gestures, external controllers and individual-button remapping remain unverified/planned.

## Planned

SQLite translation memory, provider abstractions/Keychain/AI calls, live extraction/replacement, `.evermod` schema/install/overlays/rollback, cheat adapters, desktop TypeScript MCP Bridge, device pairing, native save-management UI, folder imports and additional engine integrations. Unity is excluded.

## Blocked / external prerequisites

- **iOS compile/run:** no macOS, Xcode or Apple SDK in this machine.
- **Remote CI:** the GitHub API CONNECT request is denied with HTTP 403 by the current proxy policy; native Git read authentication succeeds. No workflow was dispatched or result verified. No token was requested because the observed failure is a network denial.
- **iPhone installation:** no signed device build/signing configuration. Simulator builds require no signing credentials. A simulator `.app` or unsigned IPA is not an installable iPhone release.
- **Future-task restoration:** the work is committed locally, not pushed or published. Restoring local-only commits in a new cloud task is not established; keep this workspace or explicitly transfer the commit before relying on another checkout.

## Validation evidence

| Check actually executed | Result |
| --- | --- |
| `bash scripts/test-core.sh` | 36 XCTest tests passed, 0 failures, 0 skipped. Swift Testing's trailing “0 tests” refers to the unused second runner, not the executed XCTest suite. |
| `npm run check` | Demo JS/module syntax passed. |
| `npm test` | 5 Node tests passed, 0 failures. |
| `PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/usr/bin/chromium npm run test:browser` | 4 Chromium integration tests passed, 0 failures. Uses Python static serving for browser tests; it does not substitute for the native Network.framework test. |
| `npm audit --audit-level=high` | 0 vulnerabilities reported at execution time. |
| Pinned XcodeGen build and `scripts/generate-project.sh` | Passed; project includes app, native HTTP and UI test targets, bundled demo/license/privacy resources and Swift package dependency. |
| Swift frontend parse of app/native test sources | Passed; syntax only, not Apple-SDK compilation. |
| Shell syntax and Info/privacy plist parsing | Passed. |
| `python3 scripts/check-repository.py` | Tracked-file credential patterns and action pins passed; this is basic screening, not a complete secret audit. |
| iOS compile/native tests/real device | **Not run.** |
| GitHub Actions | **Not run or verified in this task.** |

The first malformed-save browser test failed because its fixture overwrote storage in a live page, whose `pagehide` save then legitimately replaced that test value. The fixture now inserts corrupt storage before game initialization; the actual preservation behavior passes. No application assertion was disabled.

## Cloud configuration saved

`install_script` runs the versioned `scripts/setup-cloud.sh`; `start_skill` records the checkout, tool activation, functional checks, optional local demo server and native-validation boundary. The custom network draft adds only `api.github.com`, preserving package-manager presets. Saving this draft did not apply the network change, execute scripts, publish an environment snapshot or validate a new task. Review/save the environment settings and publish when appropriate.

## Precise next Codex task

1. Continue from this local commit/checkout (or explicitly transfer it to a GitHub branch); do not regenerate the project from scratch or discard unpushed work.
2. After the saved `api.github.com` allowance is applied, retry `gh api repos/Pander0212/EverPlay/actions/runs`. Reuse platform authentication; diagnose any new response before requesting credentials. Push/trigger the prepared workflow only within the user's authorized GitHub scope.
3. Run the **iOS Simulator** workflow or `bash scripts/test-ios.sh` on macOS with Xcode 16.4. Fix actual SDK/compiler failures and rerun; generation/syntax success is insufficient.
4. Inspect the fresh `.xcresult`: require native HTTP retrieval/range checks and ZIP import → gameplay → save → exit → full app relaunch UI test to execute and pass. Check touch controls, both orientations, isolation between two games and Files import with a legitimate ZIP.
5. Add any missing targeted tests for failures discovered there. Only then mark milestone 1 accepted. Do not add later-engine or translation breadth to hide a broken foundation.
6. Advance to MV/MZ with legal minimal engine exports; test startup/audio/save behavior before adding compatibility patches. Then proceed to translation/mods/Bridge in roadmap order.

No manual work on the owner's Windows laptop is required for these cloud/build steps. Device signing is a later separate task; never ask for private keys in chat.

## Exact files created in this slice

The repository had no tracked source files before this task. The following is the complete source/configuration inventory; generated `.build`, `.xcodeproj`, reports, tool caches and local validation logs are excluded.

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
docs/ROADMAP.md
docs/TRANSLATION.md
package-lock.json
package.json
playwright.config.js
project.yml
scripts/check-repository.py
scripts/generate-project.sh
scripts/package-demo.py
scripts/setup-cloud.sh
scripts/test-core.sh
scripts/test-ios.sh
tests/browser/demo.spec.js
tests/demo-state.test.js
```
