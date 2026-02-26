#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
APP_PATH="${1:-${REPO_ROOT}/build/ChooseBrowser.app}"

if [[ ! -d "${APP_PATH}" ]]; then
	echo "error: app bundle not found: ${APP_PATH}" >&2
	exit 1
fi

codesign --verify --deep --strict "${APP_PATH}"
codesign --display --verbose=2 "${APP_PATH}" >/dev/null

if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
	SIGN_INFO="$(codesign --display --verbose=4 "${APP_PATH}" 2>&1 || true)"
	if [[ "${SIGN_INFO}" != *"${SIGNING_IDENTITY}"* ]]; then
		echo "error: signing identity mismatch; expected '${SIGNING_IDENTITY}'" >&2
		exit 1
	fi
fi

echo "signing verified: ${APP_PATH}"
