#!/usr/bin/env bash
set -e

SHARE_NAME="onspdf"
SHARE_PATH="/mnt/onshi/pdf"
SMB_USER="ormaster"
FORCE_USER="orca"
FORCE_GROUP="orca"
SMB_CONF="/etc/samba/smb.conf"

echo "=== Samba install ==="
sudo apt update
sudo apt install -y samba smbclient

echo "=== Check users ==="
id "$SMB_USER" >/dev/null
id "$FORCE_USER" >/dev/null

echo "=== Check share path ==="
test -d "$SHARE_PATH" || { echo "ERROR: $SHARE_PATH が存在しません。マウントを確認してください。"; exit 1; }

echo "=== Set Samba password for ${SMB_USER} ==="
echo "Windows接続用のSambaパスワードを入力してください"
sudo smbpasswd -a "$SMB_USER"
sudo smbpasswd -e "$SMB_USER"

echo "=== Backup smb.conf ==="
sudo cp "$SMB_CONF" "${SMB_CONF}.bak.$(date +%Y%m%d-%H%M%S)"

echo "=== Add Samba share block ==="

# 既存の同名共有ブロックがあれば削除してから追加
sudo awk -v share="[$SHARE_NAME]" '
  $0 == share {skip=1; next}
  /^\[/ && skip {skip=0}
  !skip {print}
' "$SMB_CONF" | sudo tee "${SMB_CONF}.tmp" >/dev/null

sudo mv "${SMB_CONF}.tmp" "$SMB_CONF"

sudo tee -a "$SMB_CONF" >/dev/null <<EOF

[$SHARE_NAME]
   path = $SHARE_PATH
   browseable = yes
   writable = yes
   read only = no
   guest ok = no
   valid users = $SMB_USER
   force user = $FORCE_USER
   force group = $FORCE_GROUP
   create mask = 0666
   directory mask = 0777
EOF

echo "=== Test config ==="
sudo testparm -s

echo "=== Restart Samba ==="
sudo systemctl restart smbd
sudo systemctl restart nmbd

echo "=== Show shares ==="
sudo smbclient -L localhost -N

echo "=== Done ==="
echo "Windowsからは以下でアクセス:"
echo "\\\\$(hostname -I | awk '{print $1}')\\$SHARE_NAME"
