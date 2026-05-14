# weborca-bootstrap

WebORCA オンプレ版 (Ubuntu 22.04 LTS / jammy) のベースインストールを自動化するシェルスクリプト群。

## スコープ

公式マニュアル「日医標準レセプトソフト Ubuntu 22.04 LTS のインストールドキュメント」および「日レセ運用環境移行手引き」のうち、**サーバー側の構築〜旧データ移行完了**までを自動化する。

### `bootstrap.sh` (ベースインストール)

- apt 更新と基本パッケージの導入
- ORCA Keyring と apt-line の追加
- `jma-receipt-weborca` 本体の導入
- `weborca-install` モジュールのDLと配置
- `jma-setup` によるDB初期化
- jma-receipt-weborca サービスの起動と疎通確認
- `passwd_store.sh` による ormaster パスワード設定
- (オプション) IP固定 (nmcli)
- (オプション) IPv6 無効化 (grub)

### `import-dump.sh` (旧サーバーからのダンプ復元)

旧 ORCA サーバーで取得したダンプファイルを新サーバーに復元する。`bootstrap.sh` の完了後に、必要なら実行する。

- `onpre_db_import.sh` によるリストア (`/tmp/*.dmp` 自動検出 or 引数指定)
- `jma-setup` による DB 構造変更
- `weborca-install` でプログラム最新化 + `systemctl` 再起動
- `jma-receipt-dbscmchk` でスキーマ整合性チェック

### `install_skysh.sh` (sky.sh カスタマイズ帳票プラグイン導入)

ORCA / WebORCA Ver5.2 系向けに sky.sh のカスタマイズ帳票プラグインを導入する。`bootstrap.sh` の完了後に、必要なら実行する。GUI 側の組込手順 (201 プラグイン → 「組込」) は手動で残る。

- `jppinfo.list` に sky.sh の plugin repo 行を追加
- 旧 skysh 帳票が入っていれば削除 (uninstall_skysh.pl + `tbl_plugin` 行削除)
- orca ユーザーへ skysh の GPG 公開鍵をインポート
- `jma-receipt-weborca` を再起動

### `mk_cups-pdf_printer.sh` (CUPS PDF 仮想プリンタ設定)

`cups-pdf` パッケージを使った PDF 仮想プリンタ (lp1=A4 / lp2=A5) を登録する。`bootstrap.sh` 完了後、必要なら実行する。

- 既存の `lp1` / `lp2` を先に削除してから再登録 (冪等)
- `CUPS-PDF_opt.ppd` を使って `cups-pdf:/` デバイスに紐づけ

前提: `sudo apt install -y cups cups-pdf` が済んでいること。

### `set_share-onspdf.sh` (Samba Windows 共有設定)

`/mnt/onshi/pdf` を Samba 共有 `onspdf` として Windows から読み書きできるようにする。`bootstrap.sh` 完了後、必要なら実行する。

- Samba / smbclient のインストール
- `ormaster` ユーザーの Samba パスワード設定 (対話)
- `smb.conf` に共有ブロックを追記 (重複排除・バックアップ付き)
- `smbd` / `nmbd` の再起動

前提: `ormaster` と `orca` ユーザーが存在し、`/mnt/onshi/pdf` ディレクトリが存在すること。

### スコープ外 (別途手動)

- CUPS: 物理プリンタの追加・`cupsd.conf` 調整 (PDF 仮想プリンタは `mk_cups-pdf_printer.sh` で自動化済み)
- アクセスキー登録
- クライアント (Chrome / fcitx 等) の設定

## 前提

Ubuntu 22.04 LTS の **最小インストール直後** では `curl` と `wget` が入っていません。`bootstrap.sh` の preflight (Phase 00) でこれらを必須としているため、先にインストールしてください:

```bash
sudo apt update && sudo apt install -y curl wget
```

その他の前提コマンド (`ss`, `systemctl`, `awk`, `grep`, `apt-get`, `dpkg-query`, `tar`, `find`, `sudo`) は通常の Ubuntu に標準で入っています。

## ファイル構成

```
weborca-bootstrap/
├── bootstrap.sh              ベースインストール 親オーケストレーター
├── import-dump.sh            旧 ORCA からのダンプ復元 (一気通貫)
├── install_skysh.sh          sky.sh プラグイン導入 (GUI 組込手前まで)
├── mk_cups-pdf_printer.sh    CUPS PDF 仮想プリンタ登録 (lp1=A4 / lp2=A5)
├── set_share-onspdf.sh       Samba Windows 共有設定 (onspdf)
├── conf/
│   ├── orca-urls.env         ORCA サーバー URL の単一ソース
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

## ベース完了後の流れ

```
[bootstrap.sh] → (旧サーバーから dump.dmp を /tmp/ に配置) → [import-dump.sh]
                                                                     ↓ (任意・独立)
                                                          [install_skysh.sh]
                                                          [mk_cups-pdf_printer.sh]
                                                          [set_share-onspdf.sh]
```

### 1. ベースインストール完了

- IPv6 を無効化した場合は `sudo reboot`
- ブラウザから `http://<サーバーIP>:8000` でログイン確認 (空の DB が立ち上がる)

### 2. 旧 ORCA サーバーから取得したダンプを `/tmp/` に置く

```bash
# 例: 旧サーバーで pg_dump 等で取得したファイルを scp / USB 等で持ち込み
scp old-orca.example.lan:/var/backup/orca-20260508.dmp /tmp/
```

公式手引きの制約: ダンプは **ホームディレクトリではリストアできない** ので必ず `/tmp/` 配下に置く。

### 3. ダンプ復元スクリプトを実行

```bash
# /tmp/*.dmp を自動検出 (1個なら確認、2個以上なら番号で選択)
./import-dump.sh

# 明示指定する場合
./import-dump.sh /tmp/orca-20260508.dmp
```

`import-dump.sh` は **root では実行しない**。必要なステップで内部から `sudo` を呼ぶ。
処理内容: リストア → `jma-setup` → `weborca-install` 最新化 + 再起動 → スキーマ整合性チェック。

完了後に再度 `http://<サーバーIP>:8000` を開いて、移行されたデータが見えていれば成功。

### 4. (任意) sky.sh プラグインを入れる

sky.sh のカスタマイズ帳票を使う案件の場合のみ。`bootstrap.sh` と `import-dump.sh` で WebORCA が動いている前提。

```bash
sudo ./install_skysh.sh
```

実行後、ブラウザで ORCA 画面を開いて以下を手動で実施 (スクリプトでは自動化していない):

1. 91 マスタ登録
2. 201 プラグイン
3. 「スカイエスエイチカスタマイズ帳票」を選択
4. 「組込」をクリック
5. 「インストール済み」が ○ になれば完了

### 5. (任意) CUPS PDF 仮想プリンタを登録する

`cups-pdf` による PDF 出力プリンタを使う案件の場合のみ。

```bash
sudo apt install -y cups cups-pdf
sudo ./mk_cups-pdf_printer.sh
```

lp1 (A4) と lp2 (A5) が登録される。物理プリンタは別途 `lpadmin` で追加すること。

### 6. (任意) Windows 共有を設定する

オンシ PDF (`/mnt/onshi/pdf`) を Windows から参照する場合のみ。`/mnt/onshi/pdf` ディレクトリが存在することを先に確認すること。

```bash
sudo ./set_share-onspdf.sh
```

途中で `ormaster` の Samba パスワード入力を求められる。完了後、Windows から `\\<サーバーIP>\onspdf` でアクセスできる。

### スコープ外の手動ステップ

- CUPS: 物理プリンタの追加・`cupsd.conf` 調整 (`MaxJobs 0` 等)
- アクセスキー登録
- クライアント (Chrome / fcitx 等) の設定
