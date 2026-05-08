#!/usr/bin/env bash
# Phase 90: IPv6 を grub レベルで無効化
# マニュアル §「IPv6アドレスの無効化」相当
# 反映には reboot が必須。スクリプトでは自動 reboot しない。

set -Eeuo pipefail

# shellcheck source=../lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

require_root

if [[ "${ENABLE_IPV6_DISABLE:-false}" != "true" ]]; then
  warn "ENABLE_IPV6_DISABLE!=true のため SKIP — IPv6 無効化は実施されません"
  warn "有効化するには conf/site.env で ENABLE_IPV6_DISABLE=\"true\" にしてください"
  exit 0
fi

GRUB_FILE="/etc/default/grub"
[[ -f "$GRUB_FILE" ]] || die "$GRUB_FILE が見つかりません。"

if grep -Eq '^[[:space:]]*GRUB_CMDLINE_LINUX="[^"]*ipv6\.disable=1' "$GRUB_FILE"; then
  log "GRUB_CMDLINE_LINUX に ipv6.disable=1 が既に設定済み: SKIP"
else
  backup_file "$GRUB_FILE"

  if grep -Eq '^[[:space:]]*GRUB_CMDLINE_LINUX=' "$GRUB_FILE"; then
    log "既存の GRUB_CMDLINE_LINUX に ipv6.disable=1 を追記"
    # 既存の値の末尾に " ipv6.disable=1" を追加
    run_cmd sed -i -E 's/^([[:space:]]*GRUB_CMDLINE_LINUX=")([^"]*)"/\1\2 ipv6.disable=1"/' "$GRUB_FILE"
    # 先頭スペースが入ってしまった場合の整形
    run_cmd sed -i -E 's/^([[:space:]]*GRUB_CMDLINE_LINUX=") +/\1/' "$GRUB_FILE"
  else
    log "新規に GRUB_CMDLINE_LINUX 行を追加"
    run_cmd bash -c "printf '\nGRUB_CMDLINE_LINUX=\"ipv6.disable=1\"\n' >> '$GRUB_FILE'"
  fi
fi

log "update-grub を実行"
run_cmd update-grub

warn "IPv6 無効化の反映には再起動が必要です。bootstrap 完了後に手動で reboot してください。"
log "Phase 90 完了"
