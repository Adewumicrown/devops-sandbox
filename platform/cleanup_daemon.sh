#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

LOG="$ROOT_DIR/logs/cleanup.log"
mkdir -p "$ROOT_DIR/logs"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"
}

log "Cleanup daemon started (pid=$$)"

while true; do
  NOW=$(date +%s)

  for STATE_FILE in "$ROOT_DIR"/envs/*.json; do
    [ -f "$STATE_FILE" ] || continue

    ENV_ID=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d['id'])")
    CREATED_AT=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d['created_at'])")
    TTL=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d['ttl'])")
    EXPIRES_AT=$((CREATED_AT + TTL))

    if [ "$NOW" -ge "$EXPIRES_AT" ]; then
      log "TTL expired for $ENV_ID — destroying..."
      bash "$SCRIPT_DIR/destroy_env.sh" "$ENV_ID" >> "$LOG" 2>&1 \
        && log "✅ $ENV_ID destroyed" \
        || log "❌ Failed to destroy $ENV_ID"
    else
      REMAINING=$((EXPIRES_AT - NOW))
      log "  $ENV_ID ok — ${REMAINING}s remaining"
    fi
  done

  sleep 60
done
