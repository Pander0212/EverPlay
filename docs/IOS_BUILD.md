# iOS builds and installation

## Current evidence

Swift core tests pass on Linux and macOS. The real application and test targets compile using Xcode 16.4 on the GitHub `macos-15-intel` runner, and native tests have executed. Full acceptance is being validated; see [the current results](DEVELOPMENT_STATUS.md). Physical iPhone playback and device distribution are not verified.

The source is pushed to `codex/everplay-foundation` in [Pander0212/EverPlay](https://github.com/Pander0212/EverPlay). GitHub API reads and native Git pushes now work with the platform-provided authentication. The initially denied API access is resolved. Direct log/artifact download domains may still need the saved network-setting changes; the workflow also emits bounded failure diagnostics through API-readable check annotations.

## Reproducible simulator workflow

`.github/workflows/ios.yml` selects `macos-15-intel`, Xcode 16.4 and read-only repository permissions. `scripts/test-ios.sh`:

1. Packages the original demo ZIP deterministically.
2. Builds XcodeGen at verified commit `21ac9944b0ab546a07422dbed86f33dd2ebd76f8` (2.44.1), using its tracked lockfile.
3. Generates `EverPlay.xcodeproj` from `project.yml`; copies the root Swift resolution into the Xcode workspace lockfile.
4. Runs the portable core tests and resolves exact package versions.
5. Compiles the app and every native test target with `build-for-testing` before booting a device, using local ad-hoc simulator signing (no Apple credentials). It then explicitly boots the selected simulator with a bounded wait.
6. Uses `test-without-building` to reuse the validated products with 300-second per-test limits. Runs native HTTP/range and WebKit storage/input tests plus import → touch play → save → exit → full app relaunch and draggable-controls/orientation UI tests. Requires all four named cases to be recorded as passed; a zero-test run is rejected.
7. Preserves logs, a unique `.xcresult` and exported standalone attachments/screenshots. `pipefail` preserves command failures; the generator cache is retained even when an application test fails.

After success the workflow uploads a locally ad-hoc-signed **simulator `.app`**, not a device IPA. It cannot be installed on an iPhone. Native test and build results must be checked for the actual source commit. If the runner image no longer carries Xcode 16.4, update the explicit Xcode/runner selection and revalidate; do not silently skip the iOS build.

On a future Mac or a configured macOS cloud runner:

```sh
bash scripts/test-ios.sh
```

No local laptop is needed to run the configured GitHub workflow after the code is available on GitHub and Actions is enabled. The prepared workflows have been triggered remotely and browser/security runs have succeeded; the current native result is recorded in development status.

## Privacy manifest

The app bundles a privacy manifest for app-only UserDefaults (`CA92.1`) and file metadata in its own container (`C617.1`), with no tracking/collected-data declarations. ZIPFoundation 0.9.20's old SwiftPM manifest does not automatically package its own privacy resource; the application manifest covers the APIs used by this foundation. Review these declarations against the final built binary and Apple's current requirements before any device distribution, especially when adding providers or additional SDKs.

## Future real-device distribution

A signed device build requires a unique bundle ID, Apple team, distribution/development certificate plus private key, and a matching provisioning profile. They must be supplied through secure GitHub/environment secrets or an appropriate signing service, never committed or posted in chat. No signing requirements are requested for simulator validation.

For a laptop-free route, a configured Apple Developer account plus macOS CI can archive, sign and export an App Store Connect/TestFlight build, followed by the necessary Apple processing/review and tester invitation. Ad Hoc distribution instead needs registered device UDIDs and a matching profile. App Store/TestFlight eligibility, including policies for imported games, is a separate review and is not guaranteed.

Personal-team sideloading and tools such as AltStore/SideStore have setup, certificate lifetime and often computer requirements; they are not an immediate installation promise while the owner is traveling. An unsigned IPA is never described as installable.
