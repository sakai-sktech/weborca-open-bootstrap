#!/usr/bin/env bash
# Phase 10: apt update + upgrade + 基本パッケージ
# STRICT_MANUAL=true : マニュアル準拠 (apt dist-upgrade のみ、追加パッケージなし)
# STRICT_MANUAL=false: 実機準拠 (apt upgrade + autoremove + git + openssh-server)

set -Eeuo pipefail

# shellcheck source=../lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

require_root

log "apt update を実行"
run_cmd apt-get update

if [[ "${STRICT_MANUAL:-false}" == "true" ]]; then
  log "STRICT_MANUAL=true: apt dist-upgrade を実行 (時間がかかります)"
  run_cmd env DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold"
else
  log "apt upgrade を実行 (時間がかかります)"
  run_cmd env DEBIAN_FRONTEND=noninteractive apt-get upgrade -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold"

  log "apt autoremove を実行"
  run_cmd env DEBIAN_FRONTEND=noninteractive apt-get autoremove -y

  # 運用上必要なパッケージを最初期に導入 (実機ログでもここで入れている)
  local_extras=(git openssh-server)
  log "基本パッケージ導入: ${local_extras[*]}"
  run_cmd env DEBIAN_FRONTEND=noninteractive apt-get install -y "${local_extras[@]}"
fi

# site.env で指定された追加パッケージ
if [[ -n "${EXTRA_PACKAGES:-}" ]]; then
  # 単純な空白区切り。シェルの単語分割を意図的に使用。
  # shellcheck disable=SC2086
  log "追加パッケージ導入: ${EXTRA_PACKAGES}"
  # shellcheck disable=SC2086
  run_cmd env DEBIAN_FRONTEND=noninteractive apt-get install -y ${EXTRA_PACKAGES}
fi

log "Phase 10 完了"
