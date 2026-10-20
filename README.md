# EverPlay

An open-source iPhone game library and HTML5 player, built with SwiftUI and WKWebView. **Foundation in development; iOS compilation and device playback are not yet verified.**

This first slice contains a real iOS application target, ZIP importer, persistent library, local resource server, touch/keyboard controls, and the original **Lantern Garden** demo. The portable Swift core and browser fixture have been compiled and tested in Linux. This is not yet a signed or installable iPhone release.

## What is implemented

- Import a ZIP from Files, locate a root or nested `index.html`, and detect HTML5 or experimental MV/MZ exports.
- Validate paths, links, CRC, case/Unicode collisions, archive limits, expanded bytes and duplicate content before committing an installation.
- Browse a persistent game library and launch the game using WKWebView plus a loopback-only HTTP server.
- Keep a separate persistent WebKit store and a stable origin for each game.
- Use touch or optional D-pad/action/Enter/Escape controls, with per-game opacity and draggable group layouts.
- Import the included demo ZIP through the same importer; collect gold, buy seeds, advance the day, read Japanese dialogue and save.

Native execution, control gestures and WebKit persistence still need the macOS/iOS tests. **MV/MZ detection is tested; real RPG Maker game compatibility is not.** No Unity support. Translation, mods, cheats, additional engines and an MCP Bridge are future milestones, not hidden working features.

## Develop in the cloud

Requires Swift 6.0 or newer, Python 3, Node.js 22 or newer, Git and a C toolchain with zlib headers for Linux. Dependencies are pinned in `Package.resolved` and `package-lock.json`.

```sh
bash scripts/test-core.sh
npm ci --ignore-scripts
npm run check
npm test
npx --no-install playwright install chromium
npm run test:browser
```

In the prepared Codex environment, Swift is installed at `/workspace/everplay-tools/swift/usr/bin`; `scripts/test-core.sh` discovers it. For the existing system Chromium:

```sh
PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/usr/bin/chromium npm run test:browser
```

Generate the Xcode project using the pinned XcodeGen 2.44.1 source build:

```sh
bash scripts/generate-project.sh
```

On macOS with Xcode 16.4 and an iPhone simulator, `bash scripts/test-ios.sh` resolves dependencies, compiles the app, runs core/native HTTP/UI tests and preserves logs/results under `artifacts/`. CI contains the same command. See [iOS builds and future signing](docs/IOS_BUILD.md).

## Read next

- [Actual development status and next task](docs/DEVELOPMENT_STATUS.md)
- [Architecture and security boundaries](docs/ARCHITECTURE.md)
- [Research and licensing decisions](docs/RESEARCH.md)
- [Engine compatibility](docs/ENGINE_COMPATIBILITY.md)
- [Known limitations](docs/KNOWN_LIMITATIONS.md)
- [Roadmap](docs/ROADMAP.md)

The original code and demo are MIT-licensed. ZIPFoundation and Swift Crypto retain their own licenses; notices are bundled in the app. Imported commercial games are not included or licensed by EverPlay.
