#!/usr/bin/env bash
# Phase 40: weborca モジュール (mw / cobol / receipt) の導入
# マニュアル §「日レセモジュールをインストールします」相当

set -Eeuo pipefail

# shellcheck source=../lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

require_root

WEBORCA_BIN="/opt/jma/weborca"

# 既存導入の判定: mw/cobol/app/etc が揃っていれば導入済とみなす
if [[ -d "${WEBORCA_BIN}/mw" && -d "${WEBORCA_BIN}/cobol" && -d "${WEBORCA_BIN}/app" ]]; then
  log "weborca モジュール導入済み: SKIP"
  log "現バージョン:"
  run_cmd weborca-install -l || true
  log "Phase 40 完了 (SKIP)"
  exit 0
fi

need_cmd weborca-install

log "weborca-install を実行 (mw/cobol/receipt をDLして配置)"
run_cmd weborca-install

log "weborca-install -l でバージョン確認"
run_cmd weborca-install -l || warn "weborca-install -l がエラーを返しました (続行)"

log "Phase 40 完了"
