#!/usr/bin/env bash
# Phase 99: 最終確認 (情報のみ。die しない)

set -Eeuo pipefail

# shellcheck source=../lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

require_root

echo "============================================================"
log "WebORCA モジュール バージョン:"
weborca-install -l 2>&1 || warn "weborca-install -l に失敗"

echo "------------------------------------------------------------"
log "jma-receipt-weborca サービス状態:"
systemctl status jma-receipt-weborca --no-pager -l 2>&1 \
  | head -n 20 || true

echo "------------------------------------------------------------"
log "TCP 8000 listen:"
ss -ltn '( sport = :8000 )' 2>&1 || true

echo "------------------------------------------------------------"
log "ネットワーク状態:"
ip -4 addr 2>&1 | grep -E '^[0-9]+:|inet ' || true
echo
ip -4 route 2>&1 || true

echo "------------------------------------------------------------"
log "apt-line:"
ls -la /etc/apt/keyrings/jma.asc 2>&1 || true
ls -la /etc/apt/sources.list.d/jma-receipt-weborca-jammy10.list 2>&1 || true

echo "============================================================"
log "Phase 99 完了"
