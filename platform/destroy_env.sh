#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
source "$ROOT_DIR/.env" 2>/dev/null || true

NGINX_CONTAINER="${NGINX_CONTAINER_NAME:-sandbox-nginx}"
ENV_ID="${1:-}"

[ -n "$ENV_ID" ] || { echo "❌ Usage: destroy_env.sh <env-id>"; exit 1; }

STATE_FILE="$ROOT_DIR/envs/$ENV_ID.json"
[ -f "$STATE_FILE" ] || { echo "❌ No state file found for $ENV_ID"; exit 1; }

echo "▶ Destroying environment $ENV_ID..."

# Parse state file
LOG_PID=$(python3 -c "import json,sys; d=json.load(open('$STATE_FILE')); print(d.get('log_pid',''))")
CONTAINER_NAME="sandbox-app-$ENV_ID"

# Kill log shipping process
if [ -n "$LOG_PID" ] && kill -0 "$LOG_PID" 2>/dev/null; then
  kill "$LOG_PID" 2>/dev/null || true
  echo "  Log shipping stopped (pid=$LOG_PID)"
fi

# Stop and remove container
if docker ps -a --format '{{.Names}}' | grep -q "^$CONTAINER_NAME$"; then
  docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
  docker rm   "$CONTAINER_NAME" >/dev/null 2>&1 || true
  echo "  Container removed: $CONTAINER_NAME"
fi

# Remove Docker network
if docker network ls --format '{{.Name}}' | grep -q "sandbox-net-$ENV_ID"; then
  docker network rm "sandbox-net-$ENV_ID" >/dev/null 2>&1 || true
  echo "  Network removed: sandbox-net-$ENV_ID"
fi

# Remove Nginx config and reload
NGINX_CONF="$ROOT_DIR/nginx/conf.d/$ENV_ID.conf"
if [ -f "$NGINX_CONF" ]; then
  rm "$NGINX_CONF"
  docker exec "$NGINX_CONTAINER" nginx -s reload
  echo "  Nginx config removed and reloaded"
fi

# Archive logs
if [ -d "$ROOT_DIR/logs/$ENV_ID" ]; then
  mkdir -p "$ROOT_DIR/logs/archived/$ENV_ID"
  cp -r "$ROOT_DIR/logs/$ENV_ID/." "$ROOT_DIR/logs/archived/$ENV_ID/"
  rm -rf "$ROOT_DIR/logs/$ENV_ID"
  echo "  Logs archived to logs/archived/$ENV_ID/"
fi

# Delete state file
rm -f "$STATE_FILE"

echo "✅ Environment $ENV_ID destroyed"
