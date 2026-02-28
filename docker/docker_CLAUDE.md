# docker — Claude Code 指示書

## 概要

Docker Compose による vc-control と mumble の統合管理。
Phase0 の最初の作業対象。ここが動けば他のコンポーネント開発が始められる。

## ファイル構成

```
docker/
├── CLAUDE.md
├── docker-compose.yml        # 本番用
├── docker-compose.dev.yml    # 開発用（ポート開放・ホットリロード）
├── build.sh                  # Linux/Mac ビルド・起動スクリプト
├── build.ps1                 # Windows ビルド・起動スクリプト
└── .env.example              # 環境変数テンプレート（.env は .gitignore 対象）
```

## docker-compose.yml

```yaml
version: "3.9"

services:
  vc-control:
    build:
      context: ../vc-control
      dockerfile: Dockerfile
    container_name: rustpvc-vc-control
    restart: unless-stopped
    ports:
      - "8766:8766"
    expose:
      - "8765"
    environment:
      - OXIDE_TOKEN=${OXIDE_TOKEN}
      - SHARED_SECRET=${SHARED_SECRET}
      - OXIDE_PORT=8765
      - CLIENT_PORT=8766
      - SESSION_TTL=14400
      - STATE_TIMEOUT=5.0
      - POS_THRESHOLD=0.1
      - ANGLE_THRESHOLD=1.0
      - SSL_CERT=/certs/server.crt
      - SSL_KEY=/certs/server.key
    volumes:
      - ../mumble/ssl:/certs:ro
    networks:
      - rustpvc-net
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8765/health"]
      interval: 30s
      timeout: 5s
      retries: 3

  mumble:
    build:
      context: ../mumble
      dockerfile: Dockerfile
    container_name: rustpvc-mumble
    restart: unless-stopped
    ports:
      - "64738:64738/tcp"
      - "64738:64738/udp"
    volumes:
      - ../mumble/murmur.ini:/etc/mumble-server/mumble-server.ini:ro
      - ../mumble/ssl:/etc/mumble-server/ssl:ro
      - mumble-data:/var/lib/mumble-server
    networks:
      - rustpvc-net
    healthcheck:
      test: ["CMD-SHELL", "nc -z localhost 64738 || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 3

networks:
  rustpvc-net:
    driver: bridge

volumes:
  mumble-data:
```

## docker-compose.dev.yml

開発時は vc-control のソースをホストからマウントしてホットリロードを有効にする。
`8765` も外部公開して Oxide Plugin から直接接続できるようにする。

```yaml
version: "3.9"

services:
  vc-control:
    extends:
      file: docker-compose.yml
      service: vc-control
    ports:
      - "8765:8765"
      - "8766:8766"
    volumes:
      - ../vc-control:/app
      - ../mumble/ssl:/certs:ro
    environment:
      - DEBUG=1

  mumble:
    extends:
      file: docker-compose.yml
      service: mumble
```

## build.sh（Linux/Mac）

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="${1:-prod}"
ACTION="${2:-up}"

COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
[ "$MODE" = "dev" ] && COMPOSE_FILE="$SCRIPT_DIR/docker-compose.dev.yml"

# .env チェック
if [ ! -f "$SCRIPT_DIR/.env" ]; then
  echo "[ERROR] .env が存在しません。.env.example をコピーして設定してください。"
  exit 1
fi

echo "[RustPVC] mode=$MODE action=$ACTION"

case "$ACTION" in
  up)    docker compose -f "$COMPOSE_FILE" --env-file "$SCRIPT_DIR/.env" up -d --build
         docker compose -f "$COMPOSE_FILE" ps ;;
  down)  docker compose -f "$COMPOSE_FILE" down ;;
  build) docker compose -f "$COMPOSE_FILE" --env-file "$SCRIPT_DIR/.env" build --no-cache ;;
  logs)  docker compose -f "$COMPOSE_FILE" logs -f ;;
  *)     echo "Usage: $0 [prod|dev] [up|down|build|logs]"; exit 1 ;;
esac
```

## build.ps1（Windows）

```powershell
param(
    [string]$Mode   = "prod",
    [string]$Action = "up"
)
$ErrorActionPreference = "Stop"
$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$EnvFile     = Join-Path $ScriptDir ".env"
$ComposeFile = Join-Path $ScriptDir "docker-compose.yml"
if ($Mode -eq "dev") { $ComposeFile = Join-Path $ScriptDir "docker-compose.dev.yml" }

if (-not (Test-Path $EnvFile)) {
    Write-Error "[ERROR] .env が存在しません。.env.example をコピーして設定してください。"
    exit 1
}

switch ($Action) {
    "up"    { docker compose -f $ComposeFile --env-file $EnvFile up -d --build
              docker compose -f $ComposeFile ps }
    "down"  { docker compose -f $ComposeFile down }
    "build" { docker compose -f $ComposeFile --env-file $EnvFile build --no-cache }
    "logs"  { docker compose -f $ComposeFile logs -f }
    default { Write-Host "Usage: build.ps1 [-Mode prod|dev] [-Action up|down|build|logs]"; exit 1 }
}
```

## .env.example

```dotenv
# このファイルを .env にコピーして値を設定すること
# .env は .gitignore に含まれており、リポジトリにコミットしない

# openssl rand -hex 32 で生成すること
OXIDE_TOKEN=CHANGE_ME_OXIDE_TOKEN
SHARED_SECRET=CHANGE_ME_SHARED_SECRET
```

## Phase0 手順（このディレクトリから始める）

### ステップ1: 環境準備

```bash
# リポジトリルートで実行
cp docker/.env.example docker/.env
vi docker/.env   # OXIDE_TOKEN と SHARED_SECRET を設定

# SSL証明書生成（開発用・自己署名）
mkdir -p mumble/ssl
openssl req -x509 -newkey rsa:4096 \
  -keyout mumble/ssl/server.key \
  -out mumble/ssl/server.crt \
  -days 365 -nodes \
  -subj "/CN=rustpvc-mumble"
```

### ステップ2: 起動

```bash
cd docker
./build.sh dev up        # Linux/Mac
# または
.\build.ps1 -Mode dev -Action up   # Windows
```

### ステップ3: 疎通確認

```bash
# コンテナ状態確認
docker compose ps

# vc-control ヘルスチェック
curl http://localhost:8765/health
# 期待値: {"status": "ok", "clients": 0, "tick": 0}

# Mumble ポート確認
nc -zv localhost 64738
```

### ステップ4: Mumble 通話テスト

1. Mumble クライアント（PC）を2台起動
2. `localhost:64738` に接続（証明書警告は許可）
3. `Root` チャンネルで音声通話できることを確認
4. 管理者で `RustPVC-Main` チャンネルを作成

### Phase0 完了条件チェックリスト

- [ ] `docker compose ps` で vc-control / mumble が `healthy` になる
- [ ] `curl http://localhost:8765/health` が 200 を返す
- [ ] Mumble クライアント2台で通話できる
- [ ] `RustPVC-Main` チャンネルが作成されている

## .gitignore に含めるもの

```gitignore
docker/.env
mumble/ssl/server.crt
mumble/ssl/server.key
```

## よくあるエラーと対処

| エラー | 原因 | 対処 |
|-------|------|------|
| `vc-control` が起動しない | .env 未設定 | `.env` に OXIDE_TOKEN / SHARED_SECRET を設定 |
| `mumble` が起動しない | SSL証明書なし | openssl で証明書を生成する |
| Mumble 接続できない | ポートブロック | `ufw allow 64738` または Windows Defender で許可 |
| health チェック失敗 | vc-control コード未実装 | Phase0では `/health` の最小実装から始める |
