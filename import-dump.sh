#!/usr/bin/env bash
# import-dump.sh — WebORCA オンプレ版 ダンプ復元 一気通貫スクリプト
#
# 公式手引き (日レセ運用環境移行手引き) の以下のステップを順に実行する:
#   1. onpre_db_import.sh         (ダンプリストア)
#   2. jma-setup                  (DB 構造変更)
#   3. weborca-install            (プログラム最新化、systemctl で再起動)
#   4. jma-receipt-dbscmchk       (スキーマ整合性チェック)
#
# Usage:
#   ./import-dump.sh [DUMP_PATH]
#
#   引数なし: /tmp/*.dmp を自動検出
#     - 0個   → エラー終了
#     - 1個   → 確認プロンプト後に採用
#     - 2個以上 → 番号入力で選択 (新しい順)
#
# このスクリプトは root では実行しないこと。各ステップで必要なときだけ
# sudo を呼ぶ (onpre_db_import.sh は内部で sudo を使うため、外側で
# sudo を被せると公式手引きの想定と外れる)。

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=conf/orca-urls.env
source "${SCRIPT_DIR}/conf/orca-urls.env"

# ---- 実行コンテキスト ------------------------------------------------
if [[ "${EUID}" -eq 0 ]]; then
  die "このスクリプトは root では実行しないでください。一般ユーザーで起動し、各ステップで sudo を使います。"
fi

for c in sudo wget tar systemctl find readlink du; do
  need_cmd "$c"
done

ONPRE_DB_IMPORT="/opt/jma/weborca/app/bin/onpre_db_import.sh"
JMA_SETUP="/opt/jma/weborca/app/bin/jma-setup"
[[ -x "$ONPRE_DB_IMPORT" ]] || die "見つかりません: ${ONPRE_DB_IMPORT} — まず bootstrap.sh で WebORCA を導入してください。"
[[ -x "$JMA_SETUP" ]]       || die "見つかりません: ${JMA_SETUP}"
command -v weborca-install >/dev/null 2>&1 || die "weborca-install が PATH にありません。bootstrap.sh の Phase 30 を完了済みか確認してください。"

# ---- ダンプファイル決定 ----------------------------------------------
DUMP_PATH="${1:-}"

if [[ -n "$DUMP_PATH" ]]; then
  [[ -f "$DUMP_PATH" ]] || die "ダンプファイルが見つかりません: ${DUMP_PATH}"
  DUMP_PATH="$(readlink -f "$DUMP_PATH")"
else
  # /tmp 直下の *.dmp を mtime 新しい順に列挙 (TAB 区切りで空白入りファイル名にも対応)
  mapfile -t CANDIDATES < <(
    find /tmp -maxdepth 1 -name '*.dmp' -type f -printf '%T@\t%p\n' \
      | sort -rn | cut -f2-
  )

  if (( ${#CANDIDATES[@]} == 0 )); then
    die "/tmp/*.dmp が見つかりません。引数でパスを指定してください: $0 /path/to/dump.dmp"
  elif (( ${#CANDIDATES[@]} == 1 )); then
    DUMP_PATH="${CANDIDATES[0]}"
    log "検出: ${DUMP_PATH}"
  else
    log "/tmp/*.dmp が複数見つかりました。番号を入力して選んでください (新しい順):"
    PS3=$'\n番号を入力 (q で中止): '
    select c in "${CANDIDATES[@]}"; do
      if [[ "${REPLY:-}" == "q" ]]; then
        die "ユーザー中止"
      fi
      if [[ -n "${c:-}" ]]; then
        DUMP_PATH="$c"
        break
      fi
      warn "番号が不正です。一覧の番号を入力してください。"
    done
  fi
fi

# 公式手引きの制約: ホームディレクトリに置いたダンプは復元できない。/tmp 配下を強く推奨。
case "$DUMP_PATH" in
  /tmp/*) : ;;
  *)
    warn "ダンプファイルが /tmp/ 配下にありません: ${DUMP_PATH}"
    warn "公式手引きでは /tmp/ 以下に配置することが要件です (ホームディレクトリは不可)。"
    ask_yes_no "それでも続行しますか?" n || die "中止しました。/tmp/ にコピーしてから再実行してください。"
    ;;
esac

DUMP_SIZE="$(du -h "$DUMP_PATH" | cut -f1)"

cat <<INFO

============================================================
  WebORCA オンプレ版 ダンプ復元
============================================================
  対象ダンプ : ${DUMP_PATH} (${DUMP_SIZE})
  実行ステップ:
    1. onpre_db_import.sh   (DB を drop して dump をリストア)
    2. jma-setup            (DB 構造変更)
    3. weborca-install      (プログラム最新化 + 再起動)
    4. jma-receipt-dbscmchk (スキーマ整合性チェック)

  注意: 既存の orca データベースは drop されます。
============================================================

INFO

ask_yes_no "上記内容で復元処理を開始してよろしいですか?" n || { log "中止しました。"; exit 0; }

# 以後の sudo を 1 回のパスワード入力でまかなえるよう、先に認証
log "sudo 認証を更新します..."
sudo -v

# ---- Step 1: ダンプ復元 ---------------------------------------------
echo
log "============================================================"
log "Step 1/4: ダンプ復元"
log "  ${ONPRE_DB_IMPORT} ${DUMP_PATH}"
log "============================================================"
# onpre_db_import.sh は内部で sudo を使うので、ここでは sudo を被せない。
# また自分で y/n プロンプトを出す。
"${ONPRE_DB_IMPORT}" "${DUMP_PATH}"

# ---- Step 2: jma-setup ----------------------------------------------
echo
log "============================================================"
log "Step 2/4: DB 構造変更 (jma-setup)"
log "============================================================"
sudo "${JMA_SETUP}"

# ---- Step 3: プログラム最新化 + 再起動 -------------------------------
echo
log "============================================================"
log "Step 3/4: プログラム最新化 + 再起動"
log "============================================================"
log "jma-receipt-weborca を停止"
sudo systemctl stop jma-receipt-weborca
log "weborca-install を実行 (最新化)"
sudo weborca-install
log "現在のバージョン:"
sudo weborca-install -l || true
log "jma-receipt-weborca を起動"
sudo systemctl start jma-receipt-weborca

log "8000/tcp の listen を待機..."
wait_for_port 127.0.0.1 8000 60 || warn "8000/tcp が listen していません。後続のスキーマチェックは継続します。"

# ---- Step 4: スキーマ整合性チェック ----------------------------------
echo
log "============================================================"
log "Step 4/4: スキーマ整合性チェック"
log "============================================================"

WORK_DIR="/tmp/jma-receipt-dbscmchk"
TGZ_PATH="/tmp/jma-receipt-dbscmchk.tgz"

# 再実行時に古い展開が残っていれば退避 (削除はしない)
if [[ -d "$WORK_DIR" ]]; then
  ts="$(date +%Y%m%d-%H%M%S)"
  warn "${WORK_DIR} が既に存在します。${WORK_DIR}.bak.${ts} に退避します。"
  mv "$WORK_DIR" "${WORK_DIR}.bak.${ts}"
fi

cd /tmp
log "取得: ${DBSCMCHK_URL}"
wget -q -O "$TGZ_PATH" "$DBSCMCHK_URL"
log "展開: ${TGZ_PATH}"
tar xzf "$TGZ_PATH"

cd "$WORK_DIR"
sudo bash jma-receipt-dbscmchk.sh

LOG_PATH="${WORK_DIR}/jma-receipt-dbscmchk.log"
if [[ -f "$LOG_PATH" ]]; then
  if grep -q "正常に終了" "$LOG_PATH"; then
    log "スキーマ整合性チェック: 正常に終了"
  else
    warn 'スキーマ整合性チェックの結果に「正常に終了」が見当たりません。'
    warn "ログを確認してください: ${LOG_PATH}"
  fi
else
  warn "チェックスクリプトのログが生成されませんでした (${LOG_PATH})。"
fi

# ---- 完了サマリ ------------------------------------------------------
echo
log "============================================================"
log "ダンプ復元 完了"
log "============================================================"
printf '  %-12s : %s\n' "ダンプ"   "${DUMP_PATH}"
printf '  %-12s : %s\n' "ログ"     "${LOG_PATH:-(未生成)}"
echo
log "次のステップ:"
log "  1. ブラウザで http://<サーバーIP>:8000 にログインして動作確認"
log "  2. ログイン後、メニューが表示され帳票が引けることを確認"
log "  3. 整合性ログにエラー/警告があれば内容を確認 (${LOG_PATH:-該当ファイル})"
