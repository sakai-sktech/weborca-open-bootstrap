#!/usr/bin/env bash
# Phase 50: jma-setup によるDB初期化
# マニュアル §「データベースのセットアップ」相当
# 終端: 「データベース構造変更処理は終了しました」

set -Eeuo pipefail

# shellcheck source=../lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

require_root

JMA_SETUP="/opt/jma/weborca/app/bin/jma-setup"

[[ -x "$JMA_SETUP" ]] || die "$JMA_SETUP が見つからないか実行不可。Phase 40 を先に実行してください。"

log "jma-setup を実行 (DB構造の初期化/更新)"
# jma-setup は idempotent。再実行しても安全 (テーブルがあれば OK 表示)。
run_cmd "$JMA_SETUP"

log "Phase 50 完了"
