# Mods and cheats — planned, not implemented

The current player runs the imported game's original assets. It does not install `.evermod` files, expose a cheat API or inject arbitrary native code. Virtual controls inject only fixed keyboard events; that is not a mod system.

## Proposed v1 package contract

An `.evermod` is a bounded ZIP with a versioned `manifest.json`: unique mod ID/version, explicit target engine and game content fingerprint/version constraints, file paths and SHA-256 digests, required capabilities, dependencies/conflicts, and ordered JS/CSS/assets/structured patches. No native binaries. Reuse the importer's path/CRC/budget defenses, then add a manifest schema and engine-specific validation.

Install into a separate immutable mod-version directory. Resolve enabled overlays without changing original game files. Deterministic dependency ordering must reject cycles and conflicting asset paths rather than silently choose a winner. Enabling, installing, replacing or rolling back must require a local user action, perform a compatible save backup first, and record an atomic activation transaction. Restoration of a previous version must be possible after failure.

First implementation should demonstrate one original HTML5 demo JS/CSS mod, explicit enable/disable and rollback. Next add MV/MZ plugin hooks tested against legitimate engine fixtures. The gold-increase example is appropriate for the original single-player demo; no server economy or multiplayer anti-cheat functionality is in scope.

Save editing needs an engine adapter that understands format, compression, schema and game version. Always preserve the original before writing. Generic HTML5 games do not offer universal variable discovery. Current browser-save persistence is not yet a native save backup/export system.
