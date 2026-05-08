#!/usr/bin/env bash
# Phase 60: ormaster パスワードの設定
# マニュアル §「ormasterパスワードの設定」相当
# 失敗 (実機ログ参照: connection refused / panic) に備えて 15秒待機 → 最大3回試行

set -Eeuo pipefail

# shellcheck source=../lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

require_root

PASSWD_BIN="/opt/jma/weborca/app/bin/passwd_store.sh"
RETRY_WAIT=15
MAX_TRIES=3

[[ -x "$PASSWD_BIN" ]] || die "$PASSWD_BIN が見つからないか実行不可。"

# サービスが正しく起動しているか念のため確認
service_active jma-receipt-weborca \
  || die "jma-receipt-weborca が active ではありません。Phase 55 を先に実行してください。"

# 自動投入モード (テスト用)
auto_password=""
if [[ -n "${WEBORCA_ORMASTER_PASSWORD:-}" ]]; then
  auto_password="${WEBORCA_ORMASTER_PASSWORD}"
  warn "WEBORCA_ORMASTER_PASSWORD 経由で自動投入します (テスト用)。本番では空のままを推奨。"
  # 8〜16文字の範囲チェック
  local_len=${#auto_password}
  if (( local_len < 8 || local_len > 16 )); then
    die "WEBORCA_ORMASTER_PASSWORD は 8〜16文字 でなければなりません (現在 ${local_len} 文字)"
  fi
fi

attempt=0
while :; do
  attempt=$((attempt + 1))
  log "passwd_store.sh 試行 ${attempt}/${MAX_TRIES}"

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    dim "[DRY] sudo -u orca $PASSWD_BIN"
    log "Phase 60 完了 (DRY)"
    exit 0
  fi

  if [[ -n "$auto_password" ]]; then
    # 2回入力 (パスワード + 確認) を流し込む
    if printf '%s\n%s\n' "$auto_password" "$auto_password" \
         | sudo -u orca "$PASSWD_BIN"; then
      log "passwd_store.sh 成功"
      break
    fi
  else
    # 対話TTYで実行
    if sudo -u orca "$PASSWD_BIN"; then
      log "passwd_store.sh 成功"
      break
    fi
  fi

  if (( attempt >= MAX_TRIES )); then
    die "passwd_store.sh が ${MAX_TRIES} 回失敗しました。"
  fi
  warn "失敗。${RETRY_WAIT}秒 待機して再試行します..."
  sleep "$RETRY_WAIT"
done

log "Phase 60 完了"
