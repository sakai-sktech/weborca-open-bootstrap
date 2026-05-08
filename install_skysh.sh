#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================
# sky.sh ORCAカスタマイズ帳票 導入スクリプト
# 対象: ORCA / WebORCA Ver5.2系
#
# このスクリプトがやること
#  1. jppinfo.list に sky.sh の plugin repo を追加
#  2. 旧 skysh 帳票を削除（入っていれば）
#  3. orca ユーザーに skysh の公開鍵を導入
#  4. jma-receipt-weborca を再起動
#
# このスクリプトがやらないこと
#  - ORCA GUIの「201 プラグイン」での組込
#  - 帳票ごとの詳細設定
# ============================================

JPPINFO="/etc/jma-receipt/jppinfo.list"
PLUGIN_VER="5.2.0"
SKYSH_REPO_URL="http://www.sky.sh/orca/plugin/${PLUGIN_VER}/skysh.yml"
UNINSTALL_URL="http://www.sky.sh/orca/plugin/uninstall_skysh.tar.gz"
PUBKEY_URL="http://www.sky.sh/orca/plugin/skysh.pub"
SERVICE_NAME="jma-receipt-weborca"

log()  { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
die()  { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "command not found: $1"
}

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "sudo で実行してください"
}

backup_file() {
  local f="$1"
  local ts
  ts="$(date +%Y%m%d-%H%M%S)"
  cp -a "$f" "${f}.bak.${ts}"
  log "backup: ${f}.bak.${ts}"
}

check_env() {
  [[ -f "$JPPINFO" ]] || die "$JPPINFO が見つかりません"
  id orca >/dev/null 2>&1 || die "orca ユーザーが見つかりません"

  for cmd in awk grep cp mv chmod wget tar perl gpg psql chown rm; do
    need_cmd "$cmd"
  done

  command -v systemctl >/dev/null 2>&1 || die "systemctl が見つかりません"
}

add_skysh_repo() {
  log "jppinfo.list に sky.sh repo を追加します"

  if grep -Fq "$SKYSH_REPO_URL" "$JPPINFO"; then
    log "すでに登録済みです: $SKYSH_REPO_URL"
    return
  fi

  backup_file "$JPPINFO"

  awk -v add_line=" - ${SKYSH_REPO_URL}" '
    /^:linkprefix:/ && !done {
      print add_line
      done=1
    }
    { print }
  ' "$JPPINFO" > "${JPPINFO}.tmp"

  grep -Fq "$SKYSH_REPO_URL" "${JPPINFO}.tmp" \
    || die "repo 行の挿入に失敗しました"

  mv "${JPPINFO}.tmp" "$JPPINFO"
  chmod 644 "$JPPINFO"

  log "追加完了"
}

remove_old_plugin() {
  log "旧 skysh 帳票を削除します（存在すれば）"

  local workdir
  workdir="$(mktemp -d)"
  cd "$workdir"

  if ! wget -q -O uninstall_skysh.tar.gz "$UNINSTALL_URL"; then
    warn "旧版削除パッケージの取得に失敗。旧版削除はスキップします"
    rm -rf "$workdir"
    return
  fi

  if ! tar zxf uninstall_skysh.tar.gz; then
    warn "展開に失敗。旧版削除をスキップします"
    rm -rf "$workdir"
    return
  fi

  if [[ -f uninstall_skysh/uninstall_skysh.pl ]]; then
    (
      cd uninstall_skysh
      perl uninstall_skysh.pl
    ) || warn "uninstall_skysh.pl が失敗しましたが続行します"
  else
    warn "uninstall_skysh.pl が見つかりません。旧版削除をスキップします"
  fi

  # root が作った一時ディレクトリ内で sudo -u orca すると
  # orca ユーザーがカレントディレクトリに入れず警告が出るため、
  # psql 実行前に /tmp へ移動する。
  (
    cd /tmp
    sudo -u orca psql orca -c "delete from tbl_plugin where name='skysh';"
  ) || warn "tbl_plugin からの削除に失敗しましたが続行します"

  rm -rf "$workdir"
  log "旧版削除処理 完了"
}

import_pubkey() {
  log "orca ユーザーに公開鍵を導入します"

  wget -q -O /tmp/skysh.pub "$PUBKEY_URL" \
    || die "skysh.pub を取得できませんでした"

  chown orca:orca /tmp/skysh.pub

  sudo -u orca gpg --import /tmp/skysh.pub \
    || die "orca ユーザーで公開鍵導入に失敗しました"

  rm -f /tmp/skysh.pub

  log "公開鍵導入 完了"
}

restart_orca() {
  log "${SERVICE_NAME} を再起動します"

  systemctl restart "${SERVICE_NAME}" \
    || die "${SERVICE_NAME} の再起動に失敗しました"

  systemctl status "${SERVICE_NAME}" --no-pager -l || true

  log "再起動 完了"
}

show_finish_message() {
  cat <<'EOF'

========================================
ここまでで GUI 手前まで完了です
========================================

次に ORCA 画面で以下だけ実施してください。

1. 91 マスタ登録
2. 201 プラグイン
3. 「スカイエスエイチカスタマイズ帳票」を選択
4. 「組込」をクリック
5. 「インストール済み」が ○ になれば完了

※ 帳票ごとの詳細設定は配布元マニュアル参照
EOF
}

main() {
  require_root
  check_env
  add_skysh_repo
  remove_old_plugin
  import_pubkey
  restart_orca
  show_finish_message
}

main "$@"