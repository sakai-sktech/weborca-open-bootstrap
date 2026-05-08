#!/usr/bin/env bash
# Phase 00: Preflight check
# - Ubuntu 22.04 (jammy) であること
# - root権限
# - インターネット疎通 (ftp.orca.med.or.jp に到達できる)
# - 既存導入の検出 (情報のみ)

set -Eeuo pipefail

# shellcheck source=../lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

require_root
require_jammy

for c in wget curl ss systemctl awk grep apt-get dpkg-query; do
  need_cmd "$c"
done

# インターネット疎通
log "ORCAサーバーへの疎通を確認します"
if ! curl -sSf --max-time 10 -o /dev/null https://ftp.orca.med.or.jp/pub/ubuntu/ ; then
  die "ftp.orca.med.or.jp に到達できません。ネットワークを確認してください。"
fi
log "疎通OK: ftp.orca.med.or.jp"

# 既存導入の検出 (情報のみ。die しない)
if pkg_installed jma-receipt-weborca; then
  warn "既に jma-receipt-weborca が導入済みです。続行すると一部フェーズが SKIP されます。"
fi

if [[ -d /opt/jma/weborca ]]; then
  warn "/opt/jma/weborca が既に存在します。"
fi

# 管理者ユーザー存在確認 (Phase 60 で必要)
if [[ -n "${WEBORCA_ADMIN_USER:-}" ]]; then
  if ! id "${WEBORCA_ADMIN_USER}" >/dev/null 2>&1; then
    warn "OSユーザー '${WEBORCA_ADMIN_USER}' が存在しません。Phase 60 で問題になる可能性があります。"
  else
    log "OSユーザー確認: ${WEBORCA_ADMIN_USER}"
  fi
fi

log "Phase 00 完了"
