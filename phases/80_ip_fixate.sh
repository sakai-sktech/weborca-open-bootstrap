#!/usr/bin/env bash
# Phase 80: nmcli で IPv4 を永続的に固定設定
# 想定: Ubuntu 22.04 Desktop + NetworkManager (Japanese Team ISO 標準構成)
# systemd-networkd が衝突する場合は警告を出して停止する。

set -Eeuo pipefail

# shellcheck source=../lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
# shellcheck source=../lib/net_detect.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/net_detect.sh"

require_root

# 必要な値が揃っていなければスキップ
if [[ -z "${STATIC_IP:-}" || -z "${NETMASK_PREFIX:-}" \
   || -z "${GATEWAY:-}" || -z "${DNS_SERVERS:-}" ]]; then
  log "STATIC_IP 等が未設定: SKIP (IPはGUI設定に委ねます)"
  exit 0
fi

need_cmd nmcli

# NetworkManager が動いているか
if ! nm_is_active; then
  warn "NetworkManager が active ではありません。サービスを起動します。"
  run_cmd systemctl enable --now NetworkManager
fi

# systemd-networkd との衝突チェック
if networkd_is_active; then
  warn "systemd-networkd が active です。NetworkManager と二重管理になります。"
  if [[ "${NETWORKD_DISABLE_OK:-false}" == "true" ]]; then
    log "NETWORKD_DISABLE_OK=true: systemd-networkd を停止して無効化"
    run_cmd systemctl disable --now systemd-networkd
  else
    if ask_yes_no "systemd-networkd を disable して NetworkManager に統一しますか?" "n"; then
      run_cmd systemctl disable --now systemd-networkd
    else
      die "systemd-networkd と NetworkManager が両方 active のままでは IP 固定をスキップします。"
    fi
  fi
fi

if netplan_uses_non_nm_renderer; then
  warn "/etc/netplan/ に renderer: networkd を使う YAML があります。"
  warn "NetworkManager とぶつかる可能性があるため、site.env でネットワーク設定の方針を見直してください。"
  if ! ask_yes_no "それでも nmcli で設定を続けますか?" "n"; then
    die "中止しました。"
  fi
fi

# 対象インターフェース決定
iface="${NET_IFACE:-}"
if [[ -z "$iface" ]]; then
  iface="$(detect_default_iface || true)"
  [[ -n "$iface" ]] || die "デフォルトルートのインターフェースを検出できません。NET_IFACE を site.env に設定してください。"
  log "対象インターフェースを自動検出: ${iface}"
else
  log "対象インターフェース (site.env): ${iface}"
fi

# 対象 NM 接続UUID
uuid="$(nm_active_uuid_for_iface "$iface")"
if [[ -z "$uuid" ]]; then
  die "${iface} 上の active な NM 接続が見つかりません。先にケーブル接続/有線接続を有効化してください。"
fi
log "対象 NM 接続UUID: ${uuid}"

addr="${STATIC_IP}/${NETMASK_PREFIX}"
log "固定IPを書き込み: addr=${addr} gw=${GATEWAY} dns=${DNS_SERVERS}"
nm_set_static_v4 "$uuid" "$addr" "$GATEWAY" "$DNS_SERVERS"

log "接続を再適用"
nm_reapply "$uuid"

# 確認
if [[ "${DRY_RUN:-0}" != "1" ]]; then
  log "現在のIP情報:"
  ip -4 addr show "$iface" || true
  ip -4 route show || true
fi

log "Phase 80 完了"
