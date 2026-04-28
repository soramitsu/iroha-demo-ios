#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SOURCE="${REPO_ROOT}/../iroha/dist/NoritoBridge.xcframework"
DEST_DIR="${REPO_ROOT}/Vendor"
DEST="${DEST_DIR}/NoritoBridge/NoritoBridge.xcframework"

if [[ ! -d "${SOURCE}" ]]; then
  echo "[bootstrap] Missing source xcframework at ${SOURCE}" >&2
  echo "[bootstrap] Make sure the iroha repo is checked out at ../iroha and built." >&2
  exit 1
fi

mkdir -p "${DEST_DIR}/NoritoBridge"
rsync -a --delete "${SOURCE}" "${DEST_DIR}/NoritoBridge/" >/dev/null

echo "[bootstrap] Copied NoritoBridge.xcframework into Vendor/NoritoBridge"
