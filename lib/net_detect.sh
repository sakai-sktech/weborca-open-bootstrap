#!/usr/bin/env bash
# ネットワーク管理スタックの判定と nmcli 操作ヘルパ。
# common.sh が既に source されている前提。

if [[ -n "${__WEBORCA_NETDETECT_LOADED:-}" ]]; then return 0; fi
__WEBORCA_NETDETECT_LOADED=1

# デフォルトルートのインターフェース名を返す
detect_default_iface() {
  ip -4 route show default 2>/dev/null \
    | awk '/^default/ {print $5; exit}'
}

# NetworkManager が active か
nm_is_active() {
  systemctl is-active --quiet NetworkManager 2>/dev/null
}

# systemd-networkd が active か
networkd_is_active() {
  systemctl is-active --quiet systemd-networkd 2>/dev/null
}

# /etc/netplan/ の renderer が NetworkManager 以外を使っているか
# (NetworkManager 以外の renderer 行が1つでもあれば 0 を返す = 衝突の可能性あり)
netplan_uses_non_nm_renderer() {
  local d=/etc/netplan
  [[ -d "$d" ]] || return 1
  if grep -RhE '^\s*renderer:\s*(networkd|systemd-networkd)\s*$' "$d" 2>/dev/null \
       | grep -q .; then
    return 0
  fi
  return 1
}

# 指定インターフェース上で active な NM 接続UUIDを返す
nm_active_uuid_for_iface() {
  local iface="$1"
  nmcli -t -f UUID,DEVICE con show --active 2>/dev/null \
    | awk -F: -v ifc="$iface" '$2 == ifc {print $1; exit}'
}

# nmcli で永続的にIPv4を固定設定する
# 引数: UUID IP/PREFIX GATEWAY DNS_LIST_SPACE_SEPARATED
nm_set_static_v4() {
  local uuid="$1" addr="$2" gw="$3" dns="$4"
  # nmcli は ipv4.dns をスペース区切り or カンマ区切りで受ける
  local dns_csv="${dns// /,}"
  run_cmd nmcli con mod "$uuid" \
    ipv4.method manual \
    ipv4.addresses "$addr" \
    ipv4.gateway "$gw" \
    ipv4.dns "$dns_csv" \
    ipv4.ignore-auto-dns yes
}

# 接続を down → up して反映
nm_reapply() {
  local uuid="$1"
  run_cmd nmcli con down "$uuid" || true
  run_cmd nmcli con up "$uuid"
}
