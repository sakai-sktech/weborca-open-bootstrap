# weborca-bootstrap

WebORCA オンプレ版 (Ubuntu 22.04 LTS / jammy) のベースインストールを自動化するシェルスクリプト群。

## スコープ

公式マニュアル「日医標準レセプトソフト Ubuntu 22.04 LTS のインストールドキュメント」のうち、**サーバー側のベースインストール完了**までを自動化する:

- apt 更新と基本パッケージの導入
- ORCA Keyring と apt-line の追加
- `jma-receipt-weborca` 本体の導入
- `weborca-install` モジュールのDLと配置
- `jma-setup` によるDB初期化
- jma-receipt-weborca サービスの起動と疎通確認
- `passwd_store.sh` による ormaster パスワード設定
- (オプション) IP固定 (nmcli)
- (オプション) IPv6 無効化 (grub)

**スコープ外** (別スクリプトで対応):
- DB移行 (`onpre_db_import.sh`)
- skysh プラグイン (`install_skysh.sh`)
- CUPS / プリンタ設定
- スキーマチェック / 印字テスト
- アクセスキー登録
- クライアント (Chrome / fcitx 等) の設定

## ファイル構成

```
weborca-bootstrap/
├── bootstrap.sh              親オーケストレーター
├── conf/
│   ├── site.env.example      コピーして使う設定テンプレート
│   └── site.env              (案件ごとに作成)
├── lib/
│   ├── common.sh             ログ / 待機 / 確認プロンプト
│   └── net_detect.sh         NetworkManager 判定 + nmcli 操作
└── phases/
    ├── 00_preflight.sh       OS判定 / root / 疎通
    ├── 10_apt_base.sh        apt update/upgrade + git/openssh-server
    ├── 20_jma_repo.sh        keyring + apt-line
    ├── 30_jma_install.sh     jma-receipt-weborca 導入
    ├── 40_weborca_module.sh  weborca-install
    ├── 50_db_init.sh         jma-setup
    ├── 55_first_start.sh     restart + TCP 8000 待機
    ├── 60_password.sh        passwd_store.sh (15秒待機 → 最大3回)
    ├── 80_ip_fixate.sh       nmcli con mod (オプション)
    ├── 90_ipv6_disable.sh    grub 編集 (オプション)
    └── 99_postcheck.sh       最終確認ダンプ
```

## 使い方

### 1. 設定ファイルを作る

```bash
cd weborca-bootstrap
cp conf/site.env.example conf/site.env
$EDITOR conf/site.env
```

最低限の編集:
- `STRICT_MANUAL` (true=マニュアル準拠 / false=実機準拠)
- `STATIC_IP` などのIP固定が必要なら埋める (空ならGUIで設定)
- `ENABLE_IPV6_DISABLE` (true=IPv6無効化)

### 2. 全フェーズ実行

```bash
sudo ./bootstrap.sh
```

`60_password` で対話的にパスワードを聞かれます (8〜16文字)。

### 3. 部分実行 / ドライラン

```bash
# DB初期化からパスワード設定まで再実行
sudo ./bootstrap.sh --phase 50_db_init,55_first_start,60_password

# 何が走るか確認だけ
sudo ./bootstrap.sh --dry-run

# マニュアル準拠モード (apt dist-upgrade のみ、git/ssh 入れない)
sudo ./bootstrap.sh --strict
```

## ログ

各フェーズの stdout/stderr は `/var/log/weborca-bootstrap/<timestamp>/<phase>.log` に保存されます。

## VMでの試し方

VMware Workstation / Fusion などで:

1. Ubuntu 22.04 LTS Desktop (Japanese Remix) の ISO で「最小インストール」
2. 1人目の管理者ユーザー名は `site.env` の `WEBORCA_ADMIN_USER` と一致させる (推奨: `ormaster`)
3. ログイン直後にスナップショットを取っておくと再試行が速い
4. `git clone` か `scp` でこのディレクトリを VM 内に配置
5. `sudo ./bootstrap.sh`

## ベース完了後の手動ステップ

- IPv6 を無効化した場合は `sudo reboot`
- ブラウザから `http://<サーバーIP>:8000` でログイン確認
- 必要に応じて以下を実施:
  - DB移行: `/opt/jma/weborca/app/bin/onpre_db_import.sh /path/to/dump.dmp`
  - skysh: 同梱の `../install_skysh.sh`
  - CUPS: `cupsd.conf` の `MaxJobs 0`、プリンタ追加
  - 動作確認: `jma-receipt-dbscmchk`
