#!/usr/bin/env bash
# weborca-bootstrap: WebORCA オンプレ版 ベースインストールの親スクリプト
#
# Usage:
#   sudo ./bootstrap.sh                       # 全フェーズ実行
#   sudo ./bootstrap.sh --phase 50,55,60      # 部分実行
#   sudo ./bootstrap.sh --dry-run             # 実行せず表示のみ
#   sudo ./bootstrap.sh --strict              # マニュアル準拠 (上書き)
#   sudo ./bootstrap.sh --help

set -Eeuo pipefail

# ---- パス解決 ---------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
PHASE_DIR="${SCRIPT_DIR}/phases"
CONF_DIR="${SCRIPT_DIR}/conf"

# shellcheck source=lib/common.sh
source "${LIB_DIR}/common.sh"

# ---- フェーズ定義 -----------------------------------------------------
# 実行順。各要素はファイル名から拡張子を除いたもの。
PHASES=(
  "00_preflight"
  "10_apt_base"
  "20_jma_repo"
  "30_jma_install"
  "40_weborca_module"
  "50_db_init"
  "55_first_start"
  "60_password"
  "80_ip_fixate"
  "90_ipv6_disable"
  "99_postcheck"
)

# ---- 引数パース -------------------------------------------------------
SELECTED_PHASES=""
DRY_RUN=0
STRICT_OVERRIDE=""

usage() {
  cat <<USAGE
weborca-bootstrap

Usage:
  sudo $0 [options]

Options:
  --phase LIST    実行するフェーズをカンマ区切りで指定 (例: 50_db_init,60_password)
  --dry-run       コマンドを実行せず、実行内容のみ表示
  --strict        site.env の STRICT_MANUAL=true を強制 (マニュアル準拠)
  --help          このヘルプを表示

Phases:
$(for p in "${PHASES[@]}"; do echo "  - $p"; done)

Config:
  ${CONF_DIR}/site.env を読み込みます。なければ site.env.example をコピーしてください:
    cp ${CONF_DIR}/site.env.example ${CONF_DIR}/site.env
USAGE
}

while (( $# > 0 )); do
  case "$1" in
    --phase)
      SELECTED_PHASES="$2"; shift 2;;
    --phase=*)
      SELECTED_PHASES="${1#--phase=}"; shift;;
    --dry-run)
      DRY_RUN=1; shift;;
    --strict)
      STRICT_OVERRIDE="true"; shift;;
    --help|-h)
      usage; exit 0;;
    *)
      err "未知のオプション: $1"; usage; exit 2;;
  esac
done
export DRY_RUN

# ---- root チェック ----------------------------------------------------
require_root

# ---- site.env 読み込み ------------------------------------------------
SITE_ENV="${CONF_DIR}/site.env"
if [[ ! -f "$SITE_ENV" ]]; then
  err "${SITE_ENV} が見つかりません。"
  err "  cp ${CONF_DIR}/site.env.example ${SITE_ENV}"
  err "  $EDITOR ${SITE_ENV}"
  exit 2
fi
# shellcheck disable=SC1090
source "$SITE_ENV"

# --strict オプションで上書き
if [[ -n "$STRICT_OVERRIDE" ]]; then
  STRICT_MANUAL="$STRICT_OVERRIDE"
fi

# 環境変数として子プロセスに引き継ぐ
export STRICT_MANUAL EXTRA_PACKAGES \
       WEBORCA_ADMIN_USER WEBORCA_HOSTNAME \
       NET_IFACE STATIC_IP NETMASK_PREFIX GATEWAY DNS_SERVERS \
       NETWORKD_DISABLE_OK ENABLE_IPV6_DISABLE \
       WEBORCA_ORMASTER_PASSWORD

# ---- ログディレクトリ -------------------------------------------------
LOG_TS="$(date +%Y%m%d-%H%M%S)"
LOG_BASE="/var/log/weborca-bootstrap/${LOG_TS}"
ensure_dir "$LOG_BASE"
log "ログ出力先: ${LOG_BASE}"

# ---- 実行対象フェーズの決定 -------------------------------------------
if [[ -n "$SELECTED_PHASES" ]]; then
  IFS=',' read -r -a wanted <<< "$SELECTED_PHASES"
  RUN_LIST=()
  for w in "${wanted[@]}"; do
    matched=0
    for p in "${PHASES[@]}"; do
      if [[ "$p" == "$w" || "$p" == "${w}"* ]]; then
        RUN_LIST+=("$p")
        matched=1
        break
      fi
    done
    (( matched )) || die "未知のフェーズ: ${w}"
  done
else
  RUN_LIST=("${PHASES[@]}")
fi

log "実行予定フェーズ: ${RUN_LIST[*]}"

# ---- 実行 ------------------------------------------------------------
declare -A RESULT
overall_rc=0
for p in "${RUN_LIST[@]}"; do
  script="${PHASE_DIR}/${p}.sh"
  [[ -x "$script" || -f "$script" ]] || die "フェーズスクリプトが見つかりません: ${script}"

  echo
  log "============================================================"
  log "Phase ${p} 開始"
  log "============================================================"

  log_file="${LOG_BASE}/${p}.log"
  set +e
  bash "$script" 2>&1 | tee "$log_file"
  rc="${PIPESTATUS[0]}"
  set -e

  if (( rc == 0 )); then
    RESULT[$p]="OK"
    log "Phase ${p} OK"
  else
    RESULT[$p]="FAIL(${rc})"
    err "Phase ${p} 失敗 (rc=${rc})"
    overall_rc=$rc
    break
  fi
done

# ---- サマリ ----------------------------------------------------------
echo
log "============================================================"
log "Bootstrap サマリ"
log "============================================================"
for p in "${RUN_LIST[@]}"; do
  printf '  %-22s : %s\n' "$p" "${RESULT[$p]:-NOT_RUN}"
done
log "ログ: ${LOG_BASE}"

if (( overall_rc == 0 )); then
  echo
  log "全フェーズ完了。次のステップ:"
  cat <<NEXT
  1. 必要なら IPv6 無効化を反映するために reboot
  2. ブラウザから http://${STATIC_IP:-<サーバーIP>}:8000 でログイン確認
     ユーザー: ormaster / パスワード: Phase 60 で設定したもの
  3. 必要に応じて以下を実施 (本スクリプトの責務外):
     - DB移行    : /opt/jma/weborca/app/bin/onpre_db_import.sh <dump>
     - skysh     : ../install_skysh.sh
     - CUPS設定  : MaxJobs 0 / プリンタ追加
     - スキーマチェック: jma-receipt-dbscmchk
NEXT
else
  echo
  err "一部フェーズが失敗しました。${LOG_BASE}/*.log を確認してください。"
fi

exit "$overall_rc"
