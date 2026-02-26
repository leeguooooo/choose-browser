# ChooseBrowser

ChooseBrowser is a native macOS app that handles `http/https` links and routes them to the selected browser with deterministic fallback behavior.

## Architecture

- `apps/choose-browser/App`: app lifecycle and inbound URL handling
- `apps/choose-browser/Routing`: URL normalization and route decision logic
- `apps/choose-browser/Discovery`: installed browser discovery and filtering
- `apps/choose-browser/Execution`: explicit app-target open execution
- `apps/choose-browser/Store`: persisted exact-host routing rules
- `apps/choose-browser/UI`: chooser, onboarding, and settings surfaces
- `apps/choose-browser/Support`: default-handler inspection and settings utilities

## Run

1. Generate/update project files:
   - `xcodegen generate`
2. Build and run in Xcode:
   - Open `apps/choose-browser/ChooseBrowser.xcodeproj`
   - Select scheme `ChooseBrowser`
   - Run on `My Mac`
3. Optional command-line build:
   - `xcodebuild -project apps/choose-browser/ChooseBrowser.xcodeproj -scheme ChooseBrowser -destination 'platform=macOS' build`

## Test

- Unit tests:
  - `xcodebuild -project apps/choose-browser/ChooseBrowser.xcodeproj -scheme ChooseBrowserTests -destination 'platform=macOS' test`
- Integration tests:
  - `xcodebuild -project apps/choose-browser/ChooseBrowser.xcodeproj -scheme ChooseBrowserIntegrationTests -destination 'platform=macOS' test`
- UI tests:
  - `xcodebuild -project apps/choose-browser/ChooseBrowser.xcodeproj -scheme ChooseBrowserUITests -destination 'platform=macOS' test`

See `docs/runbook.md` for troubleshooting and evidence requirements.

## Release

- Build notarization-ready app and DMG:
  - `bash scripts/release/build-app.sh`
- Verify signing:
  - `bash scripts/release/verify-signing.sh build/ChooseBrowser.app`
- Notarization dry-run (credentials check):
  - `APPLE_ID=... APPLE_TEAM_ID=... APPLE_APP_PASSWORD=... bash scripts/release/notarize.sh --dry-run`
- Full release workflow is defined at:
  - `.github/workflows/release.yml`
