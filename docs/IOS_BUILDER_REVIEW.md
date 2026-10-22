# ios-builder assessment for EverPlay

Inspected 2026-10-22: [MobAI-App/ios-builder](https://github.com/MobAI-App/ios-builder/tree/17cb1c31eb571879154c47d1d4658e39a13a9906), commit `17cb1c31eb571879154c47d1d4658e39a13a9906`. This is a source/documentation review; its service and CLI were not installed or exercised.

Keep EverPlay's current GitHub Actions workflow for automated acceptance. Builder also delegates compilation to macOS/Xcode. It does not provide an Apple SDK or native simulator on our Linux machine. Its additional useful feature is `builder ios share`, which exposes a remote simulator through MobAI. This needs a MobAI account and a `MOBAI_API_KEY` repository secret. It could be an optional future interactive debugging channel.

| Requirement | Existing EverPlay workflow | Inspected ios-builder |
| --- | --- | --- |
| Linux user without a Mac | Dispatches GitHub's macOS runner | Also supports remote macOS via GitHub, Codemagic or Bitrise |
| Reproducible native acceptance | Pinned XcodeGen, Xcode 16.4, four mandatory HTTP/WebKit/UI cases, explicit result verification | Generated workflows focus on building/distributing apps or sharing a simulator; our test gate would still need integration |
| Interactive simulator | XCTest automation, result bundles and screenshots | MobAI simulator sharing with a separate account/key |
| Private third-party test assets | Requires a separate authenticated transport | Working-tree snapshots are Git commits pushed to a remote ref; a hidden ref in a public repository is not private storage |
| Project generation | Runs our pinned XcodeGen script | Would require an explicit integration for our generated project |
| Device distribution | Not configured | Signing, IPA, TestFlight/App Store tooling; Apple credentials/profiles still required |

Evidence in the inspected source: `internal/snapshot/snapshot.go` uses a temporary index, `git add -A`, `commit-tree` and a pushed `refs/ios-builder/jobs/` ref. Ignored files are excluded. Do not move private game assets out of ignored locations to make snapshotting include them. The generated `ios-share.yml` uses `macos-latest`, `latest-stable` Xcode and tag-based action references; adopting it would need our own version pins and preservation of the existing acceptance gate.

## Contract Demon transport

The EverPlay repository is public. Do not commit or upload the game ZIP, a repacked game bundle, a simulator app containing it, saves, or game-containing result bundles to public repository/release/Actions artifacts. Avoid passing signed download URLs as workflow inputs: inputs are not secret storage.

A suitable next route is a short-lived authenticated HTTPS download stored in a GitHub Actions secret, with the known game SHA-256 checked on the runner. Such a job must keep private inputs and outputs outside artifact/cache uploads and must not echo the URL or game content. Before any real-game run, adapt the test job's logging and artifact collection accordingly; the existing RenPy workflow is for the original MIT fixture only.

Current access evidence: Git and GitHub repository/workflow API reads work through platform authentication. The Actions-secrets listing endpoint returns HTTP 403 (`Resource not accessible by integration`). This does not prove whether any secrets already exist and does not authorize reading their values. No private transport has been provisioned or tested. The old local Contract Demon ZIP and browser profile were absent in this restored environment; a fresh authorized ZIP/download is required first.
