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
  echo "  cp docker/.env.example docker/.env"
  exit 1
fi

echo "[RustPVC] mode=$MODE action=$ACTION compose=$COMPOSE_FILE"

case "$ACTION" in
  up)
    docker compose -f "$COMPOSE_FILE" --env-file "$SCRIPT_DIR/.env" up -d --build
    docker compose -f "$COMPOSE_FILE" ps
    ;;
  down)
    docker compose -f "$COMPOSE_FILE" down
    ;;
  build)
    docker compose -f "$COMPOSE_FILE" --env-file "$SCRIPT_DIR/.env" build --no-cache
    ;;
  logs)
    docker compose -f "$COMPOSE_FILE" logs -f
    ;;
  *)
    echo "Usage: $0 [prod|dev] [up|down|build|logs]"
    exit 1
    ;;
esac
