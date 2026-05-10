#!/usr/bin/env python3
import json, time, os, glob, requests
from datetime import datetime

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
POLL_INTERVAL = 30
FAILURE_THRESHOLD = 3

# Track consecutive failures per env in memory
failure_counts = {}

def log(env_id, status_code, latency, note=""):
    line = f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] status={status_code} latency={latency:.3f}s {note}\n"
    log_path = os.path.join(ROOT_DIR, "logs", env_id, "health.log")
    os.makedirs(os.path.dirname(log_path), exist_ok=True)
    with open(log_path, "a") as f:
        f.write(line)

def update_status(state_file, status):
    with open(state_file, "r+") as f:
        d = json.load(f)
        d["status"] = status
        f.seek(0); json.dump(d, f, indent=2); f.truncate()

def poll():
    state_files = glob.glob(os.path.join(ROOT_DIR, "envs", "*.json"))
    for state_file in state_files:
        try:
            with open(state_file) as f:
                env = json.load(f)
        except Exception:
            continue

        env_id   = env["id"]
        port     = env["host_port"]
        url      = f"http://localhost:{port}/health"
        status_code = 0
        latency     = 0.0
        note        = ""

        try:
            start = time.time()
            r = requests.get(url, timeout=5)
            latency = time.time() - start
            status_code = r.status_code

            if status_code == 200:
                failure_counts[env_id] = 0
                note = "OK"
                if env.get("status") == "degraded":
                    update_status(state_file, "running")
            else:
                raise Exception(f"non-200: {status_code}")

        except Exception as e:
            latency = time.time() - start if latency == 0 else latency
            failure_counts[env_id] = failure_counts.get(env_id, 0) + 1
            note = f"FAIL({failure_counts[env_id]}) {e}"

            if failure_counts[env_id] >= FAILURE_THRESHOLD:
                update_status(state_file, "degraded")
                print(f"⚠  [{datetime.now().strftime('%H:%M:%S')}] {env_id} is DEGRADED after {failure_counts[env_id]} failures")

        log(env_id, status_code, latency, note)

if __name__ == "__main__":
    print(f"Health poller started — polling every {POLL_INTERVAL}s")
    while True:
        poll()
        time.sleep(POLL_INTERVAL)
