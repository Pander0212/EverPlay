# EverPlay Bridge — design only

There is no MCP service or pairing endpoint in this foundation, and no UI control pretends to connect to one. The app's loopback resource server is not an MCP server and cannot install mods.

The planned desktop companion will use TypeScript with the official MCP SDK on Windows/macOS/Linux. Research found the SDK's current main branch describes v2 packages and an Apache-2.0 licensing transition; choose and pin a verified release when implementation starts, rather than assuming old v1 examples remain current.

Start with a complete, tested cycle: `list_games`, scoped `inspect_game`/`list_files`/`read_file`, `create_workspace`, `write_patch`, `validate_mod`, `build_mod`, `request_install`, `get_install_status`, `set_mod_enabled`, `rollback_mod`. Expose no unrestricted shell. `test_mod` must return actual test evidence, not validation renamed as execution.

## Trust boundaries to implement before device access

- Default local stdio transport for desktop AI clients; any HTTP transport binds localhost and authenticates. Never an unauthenticated LAN endpoint.
- iPhone foreground connection with TLS and pinned peer identity; short-lived, single-use pairing challenge encoded as QR, mutual verification and explicit approval on the phone.
- Per-device revocable trust and per-game capabilities. Reading one game never grants whole-library access.
- Strict canonical paths/symlink checks, file-size/output quotas and read-only mode. Workspace writes cannot overwrite original games or user files.
- Treat all retrieved game text as untrusted data. Annotate tool outputs accordingly; file contents cannot grant permissions or authorize installs. Approval must be tracked as an independent device-side state transition.
- Bind requests to game ID, content digest, workspace/mod hash, device and nonce. Installation/activation require explicit approval and expire safely; a changed package invalidates approval.
- Keep secrets in desktop OS credential storage and iOS Keychain. Native binaries are never valid mod payloads. Device error logs must redact secrets and stay scoped.

Do not depend on continuous iOS background service execution. The first Bridge CI must type-check, test schemas, traversal, authentication, read-only mode, approval replay/tampering, manifest validation and rollback before a device demonstration is called complete.
