#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PROJECT_ROOT="${REPO_ROOT}/apps/choose-browser"
PROJECT_FILE="${PROJECT_ROOT}/ChooseBrowser.xcodeproj"
SCHEME="ChooseBrowser"
DERIVED_DATA="${REPO_ROOT}/.build/deriveddata-release"
OUTPUT_DIR="${REPO_ROOT}/build"
APP_PATH="${OUTPUT_DIR}/ChooseBrowser.app"
DMG_PATH="${OUTPUT_DIR}/ChooseBrowser.dmg"
PKG_PATH="${OUTPUT_DIR}/ChooseBrowser.pkg"

mkdir -p "${OUTPUT_DIR}"
rm -rf "${APP_PATH}" "${DMG_PATH}" "${PKG_PATH}"

xcodebuild \
	-project "${PROJECT_FILE}" \
	-scheme "${SCHEME}" \
	-configuration Release \
	-destination 'platform=macOS' \
	-derivedDataPath "${DERIVED_DATA}" \
	build

BUILT_APP_PATH="${DERIVED_DATA}/Build/Products/Release/ChooseBrowser.app"
if [[ ! -d "${BUILT_APP_PATH}" ]]; then
	echo "error: built app not found at ${BUILT_APP_PATH}" >&2
	exit 1
fi

ditto "${BUILT_APP_PATH}" "${APP_PATH}"

if command -v hdiutil >/dev/null 2>&1; then
	TMP_DMG_DIR="${OUTPUT_DIR}/.dmg-root"
	rm -rf "${TMP_DMG_DIR}"
	mkdir -p "${TMP_DMG_DIR}"
	ditto "${APP_PATH}" "${TMP_DMG_DIR}/ChooseBrowser.app"
	ln -s /Applications "${TMP_DMG_DIR}/Applications"

	hdiutil create \
		-volname "ChooseBrowser" \
		-srcfolder "${TMP_DMG_DIR}" \
		-ov \
		-format UDZO \
		"${DMG_PATH}" >/dev/null

	rm -rf "${TMP_DMG_DIR}"
fi

if command -v productbuild >/dev/null 2>&1; then
	productbuild \
		--component "${APP_PATH}" /Applications \
		"${PKG_PATH}" >/dev/null
fi

echo "build artifact: ${APP_PATH}"
if [[ -f "${DMG_PATH}" ]]; then
	echo "dmg artifact: ${DMG_PATH}"
fi
if [[ -f "${PKG_PATH}" ]]; then
	echo "pkg artifact: ${PKG_PATH}"
fi
