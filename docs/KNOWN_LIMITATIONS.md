# Known limitations

- **Device validation remains:** real iPhone installation/playback, external Files document-provider behavior, OS background/resource pressure and external controllers are not verified. Simulator compilation and test execution have occurred; the current acceptance result is in DEVELOPMENT_STATUS.md. Simulator success is not proof of every iPhone/game combination.
- ZIP imports only. Folder, RAR, 7z, encrypted ZIP, self-extracting EXE and non-web engine packages are unsupported. Large archives may be rejected by explicit resource limits.
- MV/MZ detection is structural. Real game engine startup/audio/saves/plugins are not verified. No proprietary RPG Maker assets are redistributed.
- Game documents/resources are served under a private URL prefix. Root-absolute asset/navigation paths such as `/assets/...` need a compatible game export; they are not silently rewritten.
- No remote game network access by default; CSP blocks remote services/assets. Offline single-player games are the target. NW.js/Node filesystem plugins, native binaries and desktop browser extensions are unsupported.
- WebKit media/codecs, WebGL limits, service workers, browser permissions and synthetic keyboard behavior vary. Audio requires user interaction. There is no guarantee for every web API or every game.
- Use the game's own save controls. Browser localStorage/IndexedDB persists by design, but in-memory state is not automatically serialized. Native save backup/import/export, migration and restore are not implemented.
- A simulator CI sequence that force-terminated an actively playing app before the next independent test produced a blank WebView/loading indicator after relaunch. Graceful exit is used for test cleanup; force-quit/background recovery needs separate investigation and is not claimed reliable.
- One foreground game at a time; app backgrounding is not a guarantee the game's simulation or server keeps running. The menu does not universally pause games.
- Saved ports do not change automatically. An occupied port produces a startup error instead of opening a new origin and appearing to lose saves.
- Library schema v1 uses atomic JSON; unknown versions fail closed. Recovery preserves interrupted/orphaned imports. Archive retains files/browser data, but a restore/purge UI is not yet implemented. Recovery data may use storage until explicitly managed.
- Cover art uses original procedural gradients/SF Symbols, not imported cover extraction. Virtual control groups are draggable with adjustable opacity; individual-button remapping, external controller mapping and orientation-specific layouts are future work.
- App playtime currently measures opened-session elapsed time, including time spent in menus/background; it is not a precise active-play metric.
- Translation, Keychain provider settings, SQLite translation cache, `.evermod` installation, cheats, MCP and pairing are planned. No decorative feature buttons claim otherwise.
- No signed device artifact or published device release exists. GitHub API access and pushes work, and real GitHub Actions runs exist. Xcode is supplied by the macOS runner rather than the local Linux cloud machine. Local ad-hoc simulator signing does not provide device signing.
- The repository screening script catches selected credential accidents; it is not a comprehensive secret scanner. Dependency audit covers the npm toolchain; Swift packages still require advisory/license review when updating.
