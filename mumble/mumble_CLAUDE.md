# mumble — Claude Code 指示書

## 概要

Mumble サーバ（murmur）の Docker 設定管理。
コードは書かない。設定ファイルと Dockerfile のみ管理する。

## ファイル構成

```
mumble/
├── CLAUDE.md
├── Dockerfile
├── murmur.ini          # サーバ設定
└── ssl/                # .gitignore 対象
    ├── server.crt
    └── server.key
```

## Dockerfile

公式イメージをそのまま使う。設定はボリュームマウントで差し込む。

```dockerfile
FROM mumble/mumble-server:1.5

# 設定・SSL証明書は docker-compose.yml のボリュームマウントで差し込む
# このイメージ自体への変更は最小限に留める

EXPOSE 64738/tcp 64738/udp
```

## murmur.ini 設計値

```ini
# ネットワーク
host=0.0.0.0
port=64738

# 音質・遅延最適化
bandwidth=40000          # 40kbps (Opus最適)
opusthreshold=0          # 全クライアントOpus強制

# 接続数
users=60                 # 最大60 (50人 + 余裕)
usersperchannel=60

# SSL（パスは docker-compose.yml のマウントパスに合わせる）
sslCert=/etc/mumble-server/ssl/server.crt
sslKey=/etc/mumble-server/ssl/server.key

# セキュリティ
serverpassword=
allowhtml=false
sendversion=false

# 低遅延チューニング
timeout=30
textmessagelength=0      # テキスト無効
imagemessagelength=0     # 画像無効

# ログ
loglevel=1               # Warning以上のみ
```

## SSL証明書の生成（開発用・自己署名）

```bash
mkdir -p mumble/ssl
openssl req -x509 -newkey rsa:4096 \
  -keyout mumble/ssl/server.key \
  -out mumble/ssl/server.crt \
  -days 365 -nodes \
  -subj "/CN=rustpvc-mumble"
```

本番環境では Let's Encrypt 証明書を使うこと。

## チャンネル構成

Phase0〜2 は手動でチャンネルを作成する（murmur.ini では自動作成できない）。
Mumble クライアントから管理者で接続して以下を作成:

```
Root
└── RustPVC-Main    ← 全員がここに接続する
```

Phase3 でチーム通話を実装する際に追加:

```
Root
├── RustPVC-Main
└── RustPVC-Team-{teamID}    ← チームごとに動的作成（Murmur ICE API）
```

## ホストOS チューニング（本番時）

```bash
# /etc/sysctl.conf に追記
net.rmem_max = 26214400
net.wmem_max = 26214400
```

## Phase0 でやること

1. `docker compose up mumble` で起動すること
2. Mumble クライアント（PC）から `localhost:64738` に接続できること
3. 2台のクライアントで同一チャンネルに入り音声通話できること
4. `RustPVC-Main` チャンネルを手動で作成すること

## 注意事項

- `mumble/ssl/` ディレクトリは `.gitignore` に含めること（証明書をコミットしない）
- `murmur.ini` の `serverpassword` は空のまま（VCアプリ側で接続制御する）
- ChannelListener 機能は Mumble 1.5.x で対応済み（Dockerイメージはそのまま使える）
