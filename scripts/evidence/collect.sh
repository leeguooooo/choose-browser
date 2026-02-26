#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
EVIDENCE_DIR="${REPO_ROOT}/.sisyphus/evidence"
README_FILE="${REPO_ROOT}/README.md"
RUNBOOK_FILE="${REPO_ROOT}/docs/runbook.md"
COLLECT_LOG="${EVIDENCE_DIR}/task-12-collect.log"
INDEX_LOG="${EVIDENCE_DIR}/task-12-evidence-index.log"

while [[ $# -gt 0 ]]; do
	case "$1" in
	--readme)
		if [[ $# -lt 2 ]]; then
			echo "error: --readme requires a path" >&2
			exit 1
		fi
		README_FILE="$2"
		shift 2
		;;
	--runbook)
		if [[ $# -lt 2 ]]; then
			echo "error: --runbook requires a path" >&2
			exit 1
		fi
		RUNBOOK_FILE="$2"
		shift 2
		;;
	*)
		echo "error: unknown argument '$1'" >&2
		exit 1
		;;
	esac
done

mkdir -p "${EVIDENCE_DIR}"

require_section() {
	local file="$1"
	local section="$2"

	if ! grep -E -q "^##[[:space:]]+${section}$" "${file}"; then
		echo "missing section: ${section}" >&2
		return 1
	fi
}

require_file() {
	local file="$1"
	if [[ ! -f "${file}" ]]; then
		echo "error: file not found: ${file}" >&2
		return 1
	fi
}

require_file "${README_FILE}"
require_file "${RUNBOOK_FILE}"

require_section "${README_FILE}" "Architecture"
require_section "${README_FILE}" "Run"
require_section "${README_FILE}" "Test"
require_section "${README_FILE}" "Release"

require_section "${RUNBOOK_FILE}" "Default Browser Setup"
require_section "${RUNBOOK_FILE}" "Failure Triage"
require_section "${RUNBOOK_FILE}" "Evidence Paths"

{
	echo "collect_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	echo "readme=${README_FILE}"
	echo "runbook=${RUNBOOK_FILE}"
	echo "status=ok"
	echo "message=all required sections present"
} >"${COLLECT_LOG}"

ls -1 "${EVIDENCE_DIR}"/*.log 2>/dev/null | sort >"${INDEX_LOG}"

echo "evidence collected"
echo "collect log: ${COLLECT_LOG}"
echo "index log: ${INDEX_LOG}"
