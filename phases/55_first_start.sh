#!/usr/bin/env bash
# Phase 55: jma-receipt-weborca サービスを起動し、TCP 8000 が応答するまで待機
# Phase 60 の passwd_store.sh が早すぎて panic しないようにするため

set -Eeuo pipefail

# shellcheck source=../lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

require_root

SVC="jma-receipt-weborca"

log "${SVC} を再起動"
run_cmd systemctl restart "$SVC"

log "service active 確認"
if [[ "${DRY_RUN:-0}" != "1" ]]; then
  if ! service_active "$SVC"; then
    systemctl status "$SVC" --no-pager -l || true
    die "${SVC} が active になりませんでした。"
  fi
fi

# TCP 8000 が listen するまで待つ
if [[ "${DRY_RUN:-0}" != "1" ]]; then
  wait_for_port 127.0.0.1 8000 60 || die "TCP 8000 が listen しません。"
  # 起動直後のアプリ初期化 (テーブルパッチ適用など) を待つため、追加で HTTP も叩く
  wait_for_http "http://127.0.0.1:8000/" 30 || true
fi

log "${SVC} の状態:"
run_cmd systemctl status "$SVC" --no-pager -l || true

log "Phase 55 完了"
