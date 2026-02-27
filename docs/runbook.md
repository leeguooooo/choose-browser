# ChooseBrowser Operator Runbook

This runbook documents day-to-day operation, validation, and release checks for ChooseBrowser.

## Default Browser Setup

1. Build and launch ChooseBrowser.
2. Open macOS Settings > Desktop & Dock > Default web browser.
3. Select `ChooseBrowser`.
4. Verify onboarding status in the app shows `configured`.
5. Trigger a link (for example `https://example.com`) and confirm chooser/open behavior.

## Failure Triage

When behavior is unexpected, use this sequence:

1. **Build sanity**
   - Run: `xcodebuild -project apps/choose-browser/ChooseBrowser.xcodeproj -scheme ChooseBrowser -destination 'platform=macOS' build`
2. **Targeted tests**
   - Queue/logging: `xcodebuild -project apps/choose-browser/ChooseBrowser.xcodeproj -scheme ChooseBrowserTests -destination 'platform=macOS' test -only-testing:ChooseBrowserTests/RequestQueueTests`
   - Integration routing: `xcodebuild -project apps/choose-browser/ChooseBrowser.xcodeproj -scheme ChooseBrowserIntegrationTests -destination 'platform=macOS' test`
3. **Release pipeline checks**
   - `bash scripts/release/build-app.sh`
   - `bash scripts/release/verify-signing.sh build/ChooseBrowser.app`
   - Confirm `build/ChooseBrowser.dmg` and `build/ChooseBrowser.pkg` are produced
4. **Diagnostics export**
   - `scripts/evidence/collect.sh`
   - Inspect generated `.sisyphus/evidence/*.log` artifacts

Common failure signals:

- `error:no-targets-for-probe`: no visible browser targets discovered
- `error:openFailed`: explicit app dispatch failed
- `error: missing required env vars`: notarization credentials are incomplete

## Evidence Paths

Canonical evidence output directory:

- `.sisyphus/evidence/`

Task-scoped examples already used by this plan:

- `.sisyphus/evidence/task-8-onboarding.log`
- `.sisyphus/evidence/task-9-integration.log`
- `.sisyphus/evidence/task-10-queue.log`
- `.sisyphus/evidence/task-11-release.log`

Evidence collection helper outputs:

- `.sisyphus/evidence/task-12-collect.log`
- `.sisyphus/evidence/task-12-evidence-index.log`

## Test Matrix

- `ChooseBrowserTests`: unit-level routing, discovery, executor, queue/logging
- `ChooseBrowserIntegrationTests`: end-to-end dispatch and fallback with LinkSink
- `ChooseBrowserUITests`: onboarding/chooser/settings flows

## Release Checklist

1. Run full unit + integration test suites.
2. Build release artifact with `scripts/release/build-app.sh` (app + dmg + pkg).
3. Verify signing with `scripts/release/verify-signing.sh`.
4. Validate notarization prerequisites with `scripts/release/notarize.sh --dry-run`.
5. Run `scripts/evidence/collect.sh` and archive evidence logs.
