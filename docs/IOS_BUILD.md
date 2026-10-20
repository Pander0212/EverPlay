# iOS builds and installation

## Current evidence

The Xcode project was successfully generated with XcodeGen 2.44.1 on Linux. Swift core tests pass on Linux with Swift 6.0.3. SwiftUI/WebKit/Network.framework sources passed a Swift syntax parse, which is **not** Apple-SDK type checking or compilation.

No Xcode or Apple SDK is installed in this cloud machine. `gh api repos/Pander0212/EverPlay/actions/runs` and an HTTPS API probe fail at the network proxy with HTTP 403. Native Git reads work. No GitHub Actions result, simulator execution, code signing, IPA installation or iPhone playback is claimed.

## Reproducible simulator workflow

`.github/workflows/ios.yml` selects `macos-15`, Xcode 16.4 and read-only repository permissions. `scripts/test-ios.sh`:

1. Packages the original demo ZIP deterministically.
2. Builds XcodeGen at verified commit `21ac9944b0ab546a07422dbed86f33dd2ebd76f8` (2.44.1), using its tracked lockfile.
3. Generates `EverPlay.xcodeproj` from `project.yml`; copies the root Swift resolution into the Xcode workspace lockfile.
4. Runs the portable core tests and resolves exact package versions.
5. Selects an available iPhone simulator, compiles/tests the real application with signing disabled, runs a native HTTP transport test and the ZIP import → touch play → save → exit → app relaunch UI test.
6. Preserves logs and a unique `.xcresult`. `pipefail` preserves command failures.

The workflow uploads an unsigned **simulator `.app`**, not a device IPA. It cannot be installed on an iPhone. Native tests are written but have not run. If the runner image no longer carries Xcode 16.4, update the explicit Xcode/runner selection and revalidate; do not silently skip the iOS build.

On a future Mac or a configured macOS cloud runner:

```sh
bash scripts/test-ios.sh
```

No local laptop is needed to run the configured GitHub workflow after the code is available on GitHub and Actions is enabled. This task commits locally; no remote workflow run was triggered or confirmed.

## Privacy manifest

The app bundles a privacy manifest for app-only UserDefaults (`CA92.1`) and file metadata in its own container (`C617.1`), with no tracking/collected-data declarations. ZIPFoundation 0.9.20's old SwiftPM manifest does not automatically package its own privacy resource; the application manifest covers the APIs used by this foundation. Review these declarations against the final built binary and Apple's current requirements before any device distribution, especially when adding providers or additional SDKs.

## Future real-device distribution

A signed device build requires a unique bundle ID, Apple team, distribution/development certificate plus private key, and a matching provisioning profile. They must be supplied through secure GitHub/environment secrets or an appropriate signing service, never committed or posted in chat. No signing requirements are requested for simulator validation.

For a laptop-free route, a configured Apple Developer account plus macOS CI can archive, sign and export an App Store Connect/TestFlight build, followed by the necessary Apple processing/review and tester invitation. Ad Hoc distribution instead needs registered device UDIDs and a matching profile. App Store/TestFlight eligibility, including policies for imported games, is a separate review and is not guaranteed.

Personal-team sideloading and tools such as AltStore/SideStore have setup, certificate lifetime and often computer requirements; they are not an immediate installation promise while the owner is traveling. An unsigned IPA is never described as installable.
