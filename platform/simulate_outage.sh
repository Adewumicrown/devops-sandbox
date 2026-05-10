#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
source "$ROOT_DIR/.env" 2>/dev/null || true

ENV_ID=""
MODE=""

# Parse flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)  ENV_ID="$2";  shift 2 ;;
    --mode) MODE="$2";    shift 2 ;;
    *) echo "❌ Unknown flag: $1"; exit 1 ;;
  esac
done

[ -n "$ENV_ID" ] || { echo "❌ --env is required"; exit 1; }
[ -n "$MODE"   ] || { echo "❌ --mode is required (crash|pause|network|recover|stress)"; exit 1; }

STATE_FILE="$ROOT_DIR/envs/$ENV_ID.json"
[ -f "$STATE_FILE" ] || { echo "❌ No state file found for $ENV_ID"; exit 1; }

CONTAINER_NAME="sandbox-app-$ENV_ID"
NETWORK_NAME="sandbox-net-$ENV_ID"

# ── Safety guard — never touch system containers ──────────────────────────────
SYSTEM_CHECK=$(docker inspect "$CONTAINER_NAME" \
  --format '{{index .Config.Labels "sandbox.system"}}' 2>/dev/null || echo "")
if [ "$SYSTEM_CHECK" = "true" ]; then
  echo "❌ REFUSED: cannot simulate outage on a system container"
  exit 1
fi

# Also block by name pattern
if echo "$CONTAINER_NAME" | grep -qE '(nginx|daemon|api)'; then
  echo "❌ REFUSED: cannot simulate outage on nginx/daemon/api container"
  exit 1
fi

echo "▶ Simulating '$MODE' on $ENV_ID..."

case "$MODE" in
  crash)
    docker kill "$CONTAINER_NAME"
    echo "💥 Container killed. Health monitor should detect within 90s."
    ;;
  pause)
    docker pause "$CONTAINER_NAME"
    echo "⏸  Container paused. Recover with: make simulate ENV=$ENV_ID MODE=recover"
    ;;
  network)
    docker network disconnect "$NETWORK_NAME" "$CONTAINER_NAME"
    echo "🔌 Network disconnected. Recover with: make simulate ENV=$ENV_ID MODE=recover"
    ;;
  recover)
    # Try to restart if stopped/killed
    STATUS=$(docker inspect "$CONTAINER_NAME" --format '{{.State.Status}}' 2>/dev/null || echo "missing")
    case "$STATUS" in
      exited|dead)
        docker start "$CONTAINER_NAME"
        echo "▶  Container restarted"
        ;;
      paused)
        docker unpause "$CONTAINER_NAME"
        echo "▶  Container unpaused"
        ;;
      running)
        # Might be network-disconnected — reconnect
        docker network connect "$NETWORK_NAME" "$CONTAINER_NAME" 2>/dev/null || true
        docker network connect sandbox-platform "$CONTAINER_NAME" 2>/dev/null || true
        echo "▶  Network reconnected"
        ;;
    esac

    # Update state to running
    python3 -c "
import json
with open('$STATE_FILE', 'r+') as f:
    d = json.load(f)
    d['status'] = 'running'
    f.seek(0); json.dump(d, f, indent=2); f.truncate()
"
    echo "✅ Environment $ENV_ID recovered"
    ;;
  stress)
    if ! docker exec "$CONTAINER_NAME" which stress-ng &>/dev/null; then
      docker exec "$CONTAINER_NAME" apt-get install -y stress-ng -qq
    fi
    docker exec -d "$CONTAINER_NAME" stress-ng --cpu 2 --timeout 60s
    echo "🔥 CPU stress started for 60s"
    ;;
  *)
    echo "❌ Unknown mode: $MODE. Options: crash, pause, network, recover, stress"
    exit 1
    ;;
esac
