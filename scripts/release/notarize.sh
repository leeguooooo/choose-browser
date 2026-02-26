#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
APP_PATH="${REPO_ROOT}/build/ChooseBrowser.app"
DRY_RUN=0

for arg in "$@"; do
	case "${arg}" in
	--dry-run)
		DRY_RUN=1
		;;
	--app=*)
		APP_PATH="${arg#--app=}"
		;;
	*)
		echo "error: unknown argument '${arg}'" >&2
		exit 1
		;;
	esac
done

required_vars=(APPLE_ID APPLE_TEAM_ID APPLE_APP_PASSWORD)
missing=()
for name in "${required_vars[@]}"; do
	if [[ -z "${!name:-}" ]]; then
		missing+=("${name}")
	fi
done

if [[ ${#missing[@]} -gt 0 ]]; then
	echo "error: missing required env vars: ${missing[*]}" >&2
	exit 1
fi

if [[ ! -d "${APP_PATH}" ]]; then
	echo "error: app bundle not found: ${APP_PATH}" >&2
	exit 1
fi

ZIP_PATH="${REPO_ROOT}/build/ChooseBrowser-notarize.zip"

if [[ "${DRY_RUN}" == "1" ]]; then
	echo "dry-run ok: notarization prerequisites satisfied"
	echo "app: ${APP_PATH}"
	echo "would submit: ${ZIP_PATH}"
	exit 0
fi

ditto -c -k --keepParent "${APP_PATH}" "${ZIP_PATH}"

xcrun notarytool submit "${ZIP_PATH}" \
	--apple-id "${APPLE_ID}" \
	--team-id "${APPLE_TEAM_ID}" \
	--password "${APPLE_APP_PASSWORD}" \
	--wait

xcrun stapler staple "${APP_PATH}"

echo "notarization complete: ${APP_PATH}"
