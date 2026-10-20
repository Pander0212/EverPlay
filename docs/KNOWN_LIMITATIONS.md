# Known limitations

- **Required validation remains:** iOS compilation, Network.framework execution, Files document-provider behavior, virtual control gestures, WebKit per-game storage and simulator UI tests have not run. Linux/browser success is not proof of iPhone compatibility.
- ZIP imports only. Folder, RAR, 7z, encrypted ZIP, self-extracting EXE and non-web engine packages are unsupported. Large archives may be rejected by explicit resource limits.
- MV/MZ detection is structural. Real game engine startup/audio/saves/plugins are not verified. No proprietary RPG Maker assets are redistributed.
- No remote game network access by default; CSP blocks remote services/assets. Offline single-player games are the target. NW.js/Node filesystem plugins, native binaries and desktop browser extensions are unsupported.
- WebKit media/codecs, WebGL limits, service workers, browser permissions and synthetic keyboard behavior vary. Audio requires user interaction. There is no guarantee for every web API or every game.
- Use the game's own save controls. Browser localStorage/IndexedDB persists by design, but in-memory state is not automatically serialized. Native save backup/import/export, migration and restore are not implemented.
- One foreground game at a time; app backgrounding is not a guarantee the game's simulation or server keeps running. The menu does not universally pause games.
- Saved ports do not change automatically. An occupied port produces a startup error instead of opening a new origin and appearing to lose saves.
- Library schema v1 uses atomic JSON; unknown versions fail closed. Recovery preserves interrupted/orphaned imports. Archive retains files/browser data, but a restore/purge UI is not yet implemented. Recovery data may use storage until explicitly managed.
- Cover art uses original procedural gradients/SF Symbols, not imported cover extraction. Virtual control groups are draggable with adjustable opacity; individual-button remapping, external controller mapping and orientation-specific layouts are future work.
- App playtime currently measures opened-session elapsed time, including time spent in menus/background; it is not a precise active-play metric.
- Translation, Keychain provider settings, SQLite translation cache, `.evermod` installation, cheats, MCP and pairing are planned. No decorative feature buttons claim otherwise.
- No signed device artifact, published release or verified GitHub Actions run exists from this task. GitHub API access is blocked by the current proxy policy. Xcode is unavailable locally.
- The repository screening script catches selected credential accidents; it is not a comprehensive secret scanner. Dependency audit covers the npm toolchain; Swift packages still require advisory/license review when updating.
