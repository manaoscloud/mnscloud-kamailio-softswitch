#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CHANNEL="${MNSCLOUD_KAMAILIO_SOFTSWITCH_CHANNEL:-stable}"

if [[ $# -gt 0 ]]; then
  CHANNEL="$1"
fi

cd "$ROOT_DIR"
git fetch origin main --tags --prune

REF="$(git show "origin/main:releases/manifest.json" | awk -v channel="$CHANNEL" '
  $0 ~ "\"" channel "\"" { in_channel = 1; next }
  in_channel && /"ref"[[:space:]]*:/ {
    gsub(/.*"ref"[[:space:]]*:[[:space:]]*"/, "")
    gsub(/".*/, "")
    print
    exit
  }
  in_channel && /^[[:space:]]*}/ { in_channel = 0 }
')"

[[ "$REF" =~ ^v[0-9]+[.][0-9]+[.][0-9]+([-+][0-9A-Za-z.-]+)?$ ]] || {
  echo "[update-latest-kamailio-softswitch] invalid ${CHANNEL} ref: ${REF:-empty}" >&2
  exit 1
}

bash "${SCRIPT_DIR}/update-kamailio-softswitch.sh" --ref "$REF"
