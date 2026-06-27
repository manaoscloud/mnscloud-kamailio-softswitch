#!/usr/bin/env bash
set -Eeuo pipefail

KAMAILIO_CFG="${KAMAILIO_CFG:-/etc/kamailio/kamailio.cfg}"
BACKUP_CFG="${KAMAILIO_CFG}.bkp"

if [[ ! -r "$BACKUP_CFG" ]]; then
  echo "[rollback-kamailio-softswitch] backup not found: ${BACKUP_CFG}" >&2
  exit 1
fi

install -m 0644 "$BACKUP_CFG" "$KAMAILIO_CFG"
kamailio -c -f "$KAMAILIO_CFG"
systemctl restart kamailio

echo "[rollback-kamailio-softswitch] restored ${BACKUP_CFG}"
