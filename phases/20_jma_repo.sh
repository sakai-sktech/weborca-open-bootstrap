#!/usr/bin/env bash
# Phase 20: ORCA Keyring と apt-line を追加
# マニュアル §「Keyringとapt-lineの追加」相当

set -Eeuo pipefail

# shellcheck source=../lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

require_root

KEYRING_DIR="/etc/apt/keyrings"
KEYRING_FILE="${KEYRING_DIR}/jma.asc"
KEYRING_URL="https://ftp.orca.med.or.jp/pub/ubuntu/archive.key"

LIST_DIR="/etc/apt/sources.list.d"
LIST_FILE="${LIST_DIR}/jma-receipt-weborca-jammy10.list"
LIST_URL="https://ftp.orca.med.or.jp/pub/ubuntu/jma-receipt-weborca-jammy10.list"

ensure_dir "$KEYRING_DIR"

if [[ -s "$KEYRING_FILE" ]]; then
  log "keyring 導入済み: $KEYRING_FILE"
else
  log "keyring 取得: $KEYRING_URL"
  run_cmd wget -q -O "$KEYRING_FILE" "$KEYRING_URL"
  [[ -s "$KEYRING_FILE" ]] || die "keyring 取得後の検証に失敗"
fi

if [[ -s "$LIST_FILE" ]]; then
  log "apt-line 導入済み: $LIST_FILE"
else
  log "apt-line 取得: $LIST_URL"
  run_cmd wget -q -O "$LIST_FILE" "$LIST_URL"
  [[ -s "$LIST_FILE" ]] || die "apt-line 取得後の検証に失敗"
fi

log "apt update を実行"
run_cmd apt-get update

log "Phase 20 完了"
