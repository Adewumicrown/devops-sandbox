#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
source "$ROOT_DIR/.env" 2>/dev/null || true

NGINX_CONTAINER="${NGINX_CONTAINER_NAME:-sandbox-nginx}"
NGINX_PORT="${NGINX_PORT:-8888}"
DEMO_IMAGE="${DEMO_APP_IMAGE:-sandbox-demo-app}"
HOST_DOMAIN="${HOST_DOMAIN:-localhost}"

ENV_NAME="${1:-unnamed}"
TTL="${2:-${DEFAULT_TTL:-1800}}"
ENV_ID="env-$(cat /proc/sys/kernel/random/uuid | cut -c1-8)"
CREATED_AT=$(date +%s)

mkdir -p "$ROOT_DIR/envs" "$ROOT_DIR/logs/$ENV_ID"

echo "▶ Creating environment '$ENV_NAME' (id=$ENV_ID, ttl=${TTL}s)..."

# Build demo image if missing
if ! docker image inspect "$DEMO_IMAGE" &>/dev/null; then
  echo "  Building demo app image..."
  docker build -t "$DEMO_IMAGE" "$ROOT_DIR/app" --quiet
fi

# Pick a free host port in range 10000-19999
HOST_PORT=$(comm -23 \
  <(seq 10000 19999 | sort) \
  <(ss -tlnp | awk '{print $4}' | grep -oP ':\K\d+' | sort) \
  | head -1)
echo "  Assigned host port: $HOST_PORT"

# Create dedicated Docker network
docker network create "sandbox-net-$ENV_ID" \
  --label "sandbox.env=$ENV_ID" >/dev/null
echo "  Network created: sandbox-net-$ENV_ID"

# Start container on its dedicated network
CONTAINER_ID=$(docker run -d \
  --name "sandbox-app-$ENV_ID" \
  --network "sandbox-net-$ENV_ID" \
  --label "sandbox.env=$ENV_ID" \
  --label "sandbox.name=$ENV_NAME" \
  -p "$HOST_PORT:5000" \
  -e "ENV_ID=$ENV_ID" \
  -e "ENV_NAME=$ENV_NAME" \
  "$DEMO_IMAGE")
echo "  Container started: $CONTAINER_ID"

# Also connect container to platform network so Nginx can reach it by name
docker network connect sandbox-platform "sandbox-app-$ENV_ID"
echo "  Connected to sandbox-platform network"

# Write Nginx config
cat > "$ROOT_DIR/nginx/conf.d/$ENV_ID.conf" << NGINX
server {
    listen 80;
    server_name _;

    location /env/$ENV_ID/ {
        proxy_pass http://sandbox-app-$ENV_ID:5000/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Env-ID $ENV_ID;
    }
}
NGINX
echo "  Nginx config written"

# Reload Nginx
docker exec "$NGINX_CONTAINER" nginx -s reload
echo "  Nginx reloaded"

# Start log shipping
docker logs -f "$CONTAINER_ID" >> "$ROOT_DIR/logs/$ENV_ID/app.log" 2>&1 &
LOG_PID=$!
echo "  Log shipping started (pid=$LOG_PID)"

# Write state file atomically
TEMP_FILE=$(mktemp)
cat > "$TEMP_FILE" << JSON
{
  "id": "$ENV_ID",
  "name": "$ENV_NAME",
  "container_id": "$CONTAINER_ID",
  "container_name": "sandbox-app-$ENV_ID",
  "host_port": $HOST_PORT,
  "created_at": $CREATED_AT,
  "ttl": $TTL,
  "status": "running",
  "log_pid": $LOG_PID
}
JSON
mv "$TEMP_FILE" "$ROOT_DIR/envs/$ENV_ID.json"
echo "  State file written"

echo ""
echo "✅ Environment ready!"
echo "   ID:   $ENV_ID"
echo "   Name: $ENV_NAME"
echo "   URL:  http://$HOST_DOMAIN:$NGINX_PORT/env/$ENV_ID/"
echo "   TTL:  ${TTL}s (expires at $(date -d "@$((CREATED_AT + TTL))" '+%H:%M:%S'))"
echo "   Logs: make logs ENV=$ENV_ID"
