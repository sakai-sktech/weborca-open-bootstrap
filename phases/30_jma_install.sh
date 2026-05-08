#!/usr/bin/env bash
# Phase 30: jma-receipt-weborca 本体パッケージの導入
# マニュアル §「日レセのインストール」相当

set -Eeuo pipefail

# shellcheck source=../lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

require_root

if pkg_installed jma-receipt-weborca; then
  log "jma-receipt-weborca 導入済み: SKIP"
  log "Phase 30 完了 (SKIP)"
  exit 0
fi

log "jma-receipt-weborca を導入 (依存パッケージ多数)"
run_cmd env DEBIAN_FRONTEND=noninteractive apt-get install -y \
  -o Dpkg::Options::="--force-confdef" \
  -o Dpkg::Options::="--force-confold" \
  jma-receipt-weborca

pkg_installed jma-receipt-weborca || die "jma-receipt-weborca の導入に失敗しました"

log "Phase 30 完了"
