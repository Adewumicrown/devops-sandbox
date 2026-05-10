#!/usr/bin/env python3
import os, json, glob, time, subprocess
from datetime import datetime
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

app = FastAPI(title="DevOps Sandbox API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Helpers ────────────────────────────────────────────────────────────────────

def load_state(env_id):
    path = os.path.join(ROOT_DIR, "envs", f"{env_id}.json")
    if not os.path.exists(path):
        raise HTTPException(status_code=404, detail=f"Env {env_id} not found")
    with open(path) as f:
        return json.load(f)

def all_envs():
    files = glob.glob(os.path.join(ROOT_DIR, "envs", "*.json"))
    envs = []
    for f in files:
        try:
            with open(f) as fh:
                envs.append(json.load(fh))
        except Exception:
            continue
    return envs

def run_script(cmd):
    result = subprocess.run(
        cmd, shell=True, capture_output=True, text=True, cwd=ROOT_DIR
    )
    return result.stdout.strip(), result.stderr.strip(), result.returncode

# ── Models ─────────────────────────────────────────────────────────────────────

class CreateEnvRequest(BaseModel):
    name: str
    ttl: int = 1800

class OutageRequest(BaseModel):
    mode: str

# ── Routes ────────────────────────────────────────────────────────────────────

@app.post("/envs", status_code=201)
def create_env(req: CreateEnvRequest):
    stdout, stderr, code = run_script(
        f"bash platform/create_env.sh '{req.name}' '{req.ttl}'"
    )
    if code != 0:
        raise HTTPException(status_code=500, detail=stderr or stdout)

    # Parse env ID from output
    env_id = None
    for line in stdout.splitlines():
        if "ID:" in line:
            env_id = line.split("ID:")[-1].strip()
            break

    if not env_id:
        raise HTTPException(status_code=500, detail="Could not parse env ID from output")

    return load_state(env_id)


@app.get("/envs")
def list_envs():
    now = int(time.time())
    result = []
    for env in all_envs():
        ttl_remaining = (env["created_at"] + env["ttl"]) - now
        result.append({**env, "ttl_remaining": max(0, ttl_remaining)})
    return result


@app.delete("/envs/{env_id}")
def destroy_env(env_id: str):
    load_state(env_id)  # raises 404 if not found
    stdout, stderr, code = run_script(f"bash platform/destroy_env.sh '{env_id}'")
    if code != 0:
        raise HTTPException(status_code=500, detail=stderr or stdout)
    return {"message": f"Environment {env_id} destroyed"}


@app.get("/envs/{env_id}/logs")
def get_logs(env_id: str):
    load_state(env_id)
    log_path = os.path.join(ROOT_DIR, "logs", env_id, "app.log")
    if not os.path.exists(log_path):
        return {"env_id": env_id, "lines": []}
    with open(log_path) as f:
        lines = f.readlines()[-100:]
    return {"env_id": env_id, "lines": [l.rstrip() for l in lines]}


@app.get("/envs/{env_id}/health")
def get_health(env_id: str):
    load_state(env_id)
    log_path = os.path.join(ROOT_DIR, "logs", env_id, "health.log")
    if not os.path.exists(log_path):
        return {"env_id": env_id, "checks": []}
    with open(log_path) as f:
        lines = f.readlines()[-10:]
    return {"env_id": env_id, "checks": [l.rstrip() for l in lines]}


@app.post("/envs/{env_id}/outage")
def trigger_outage(env_id: str, req: OutageRequest):
    load_state(env_id)
    valid_modes = ["crash", "pause", "network", "recover", "stress"]
    if req.mode not in valid_modes:
        raise HTTPException(status_code=400, detail=f"Invalid mode. Options: {valid_modes}")
    stdout, stderr, code = run_script(
        f"bash platform/simulate_outage.sh --env '{env_id}' --mode '{req.mode}'"
    )
    if code != 0:
        raise HTTPException(status_code=500, detail=stderr or stdout)
    return {"env_id": env_id, "mode": req.mode, "output": stdout}


@app.get("/")
def root():
    return {
        "service": "DevOps Sandbox API",
        "endpoints": [
            "POST   /envs",
            "GET    /envs",
            "DELETE /envs/:id",
            "GET    /envs/:id/logs",
            "GET    /envs/:id/health",
            "POST   /envs/:id/outage"
        ]
    }
