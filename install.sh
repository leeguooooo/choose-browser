#!/bin/sh
# ChooseBrowser installer.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/leeguooooo/choose-browser/main/install.sh | sh
#
# Why this exists: ChooseBrowser ships ad-hoc-signed (not notarized), so a copy
# downloaded through a *browser* gets a com.apple.quarantine attribute and macOS
# refuses to open it ("Apple could not verify ... Move to Trash"). A file fetched
# with curl is NOT quarantined, so installing this way sidesteps the prompt
# entirely. We also clear any stray quarantine and re-register with LaunchServices
# for good measure.
set -eu

REPO="leeguooooo/choose-browser"
APP="/Applications/ChooseBrowser.app"
PKG_URL="https://github.com/${REPO}/releases/latest/download/ChooseBrowser.pkg"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

if [ "$(uname -s)" != "Darwin" ]; then
	echo "error: ChooseBrowser is macOS only." >&2
	exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PKG="${TMP}/ChooseBrowser.pkg"

echo "Downloading the latest ChooseBrowser release..."
curl -fsSL -o "$PKG" "$PKG_URL"

# Quit any running copy so the new build takes over cleanly.
pkill -x ChooseBrowser 2>/dev/null || true

echo "Installing to /Applications (you may be asked for your password)..."
sudo installer -pkg "$PKG" -target /

# curl downloads aren't quarantined, but clear attributes defensively and make
# sure LaunchServices points at this copy (not a stale dev build).
sudo xattr -cr "$APP" 2>/dev/null || true
"$LSREGISTER" -f "$APP" 2>/dev/null || true

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "${APP}/Contents/Info.plist" 2>/dev/null || echo '?')"
echo ""
echo "✅ ChooseBrowser v${VERSION} installed."
echo "   Set it as default: System Settings → Desktop & Dock → Default web browser → ChooseBrowser."
