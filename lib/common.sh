#!/usr/bin/env bash
# 共通ユーティリティ。各フェーズスクリプトから source される。
# 直接実行はしない。

# 二重 source 防止
if [[ -n "${__WEBORCA_COMMON_LOADED:-}" ]]; then return 0; fi
__WEBORCA_COMMON_LOADED=1

# ---- ログ出力 ---------------------------------------------------------
# 色は端末がTTYのときだけ
if [[ -t 1 ]]; then
  __C_RED=$'\e[31m'; __C_YEL=$'\e[33m'; __C_GRN=$'\e[32m'; __C_DIM=$'\e[2m'; __C_RST=$'\e[0m'
else
  __C_RED=""; __C_YEL=""; __C_GRN=""; __C_DIM=""; __C_RST=""
fi

log()  { printf '%s[INFO]%s %s\n'  "${__C_GRN}" "${__C_RST}" "$*"; }
warn() { printf '%s[WARN]%s %s\n'  "${__C_YEL}" "${__C_RST}" "$*" >&2; }
err()  { printf '%s[ERROR]%s %s\n' "${__C_RED}" "${__C_RST}" "$*" >&2; }
dim()  { printf '%s%s%s\n'         "${__C_DIM}" "$*" "${__C_RST}"; }
die()  { err "$*"; exit 1; }

# ---- 前提チェック -----------------------------------------------------
need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "必要なコマンドが見つかりません: $1"
}

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "root権限が必要です。sudo で実行してください。"
}

require_jammy() {
  if ! command -v lsb_release >/dev/null 2>&1; then
    warn "lsb_release が見つかりません。Ubuntu 22.04 (jammy) であることをユーザーが確認してください。"
    return 0
  fi
  local codename
  codename="$(lsb_release -cs 2>/dev/null || true)"
  [[ "$codename" == "jammy" ]] \
    || die "Ubuntu 22.04 (jammy) 以外で実行されています: codename=$codename"
}

# ---- ファイル操作 -----------------------------------------------------
backup_file() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  local ts
  ts="$(date +%Y%m%d-%H%M%S)"
  cp -a "$f" "${f}.bak.${ts}"
  log "バックアップ: ${f}.bak.${ts}"
}

ensure_dir() {
  local d="$1"
  [[ -d "$d" ]] || install -d -m 0755 "$d"
}

# ---- 待機ロジック -----------------------------------------------------
# wait_for_port HOST PORT TIMEOUT_SEC
wait_for_port() {
  local host="$1" port="$2" timeout="${3:-60}"
  local i=0
  while ! ss -ltn "( sport = :$port )" 2>/dev/null | grep -q ":$port"; do
    sleep 1
    i=$((i + 1))
    if (( i >= timeout )); then
      err "${host}:${port} が ${timeout}秒 以内に listen されませんでした。"
      return 1
    fi
  done
  log "${host}:${port} が listen を開始しました (${i}秒)"
}

# wait_for_http URL TIMEOUT_SEC
wait_for_http() {
  local url="$1" timeout="${2:-30}"
  local i=0
  while :; do
    # 200/30x なら成功扱い、500台でも応答が返るならアプリ起動済とみなす
    local code
    code="$(curl -4 -s -o /dev/null -w '%{http_code}' --max-time 3 "$url" 2>/dev/null || echo 000)"
    if [[ "$code" =~ ^(2|3|4|5)[0-9][0-9]$ ]] && [[ "$code" != "000" ]]; then
      log "${url} がHTTP応答を返しました (code=$code, ${i}秒)"
      return 0
    fi
    sleep 1
    i=$((i + 1))
    if (( i >= timeout )); then
      warn "${url} がHTTP応答を返しませんでした (${timeout}秒)。続行します。"
      return 1
    fi
  done
}

# ---- 確認プロンプト ---------------------------------------------------
# ask_yes_no PROMPT DEFAULT(y|n)
# 非対話 (TTYでない) のときは DEFAULT を返す
ask_yes_no() {
  local prompt="$1" default="${2:-n}"
  if [[ ! -t 0 ]]; then
    log "(非対話) デフォルトの ${default} を採用: ${prompt}"
    [[ "$default" == "y" ]]
    return $?
  fi
  local hint
  if [[ "$default" == "y" ]]; then hint="[Y/n]"; else hint="[y/N]"; fi
  local ans
  read -r -p "${prompt} ${hint} " ans || true
  ans="${ans:-$default}"
  [[ "$ans" =~ ^[Yy]([Ee][Ss])?$ ]]
}

# ---- dpkg / systemd ヘルパ --------------------------------------------
pkg_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

service_active() {
  systemctl is-active --quiet "$1"
}

service_enabled() {
  systemctl is-enabled --quiet "$1" 2>/dev/null
}

# ---- フェーズ実行ヘルパ ------------------------------------------------
# DRY_RUN=1 のとき、コマンドを実行せず表示のみ
run_cmd() {
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    dim "[DRY] $*"
    return 0
  fi
  "$@"
}
