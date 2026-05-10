#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "▶ Starting platform..."

docker compose -f "$ROOT_DIR/docker-compose.yml" up nginx -d

mkdir -p "$ROOT_DIR/logs"

pkill -f cleanup_daemon.sh 2>/dev/null || true
pkill -f poller.py 2>/dev/null || true
pkill -f sandbox_api 2>/dev/null || true

sleep 1

nohup bash "$SCRIPT_DIR/cleanup_daemon.sh" >> "$ROOT_DIR/logs/cleanup.log" 2>&1 &
echo "  Cleanup daemon PID: $!"

nohup python3 "$ROOT_DIR/monitor/poller.py" >> "$ROOT_DIR/logs/poller.log" 2>&1 &
echo "  Health poller PID: $!"

nohup bash -c "cd '$ROOT_DIR' && PYTHONPATH=. uvicorn sandbox_api:app --host 0.0.0.0 --port 8000 --app-dir platform" >> "$ROOT_DIR/logs/api.log" 2>&1 &
echo "  API PID: $!"

sleep 3
echo "✅ Platform up!"
echo "   API:   http://localhost:8000"
echo "   Nginx: http://localhost:${NGINX_PORT:-8888}"
