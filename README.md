# devops-sandbox

A self-service platform for spinning up isolated temporary environments, simulating outages, monitoring health, and auto-destroying everything on TTL expiry. Think of it as a miniature internal Heroku with a chaos engineering toggle.

---

## Architecture
                    ┌─────────────────────────────────────────┐
                    │            Linux VM (Host)               │
                    │                                          │
User / CI             │   ┌─────────┐      ┌─────────────────┐  │
│                  │   │  make   │      │   API :8000     │  │
│  curl/make       │   │ targets │─────▶│  sandbox_api.py │  │
▼                  │   └─────────┘      └────────┬────────┘  │
┌─────────┐             │                            │            │
│  Nginx  │◀────────────│────────────────────────────┘            │
│ :8888   │             │   ┌──────────────┐  ┌────────────────┐  │
│ :21000+ │             │   │cleanup_daemon│  │ health poller  │  │
└────┬────┘             │   │  (60s loop)  │  │   (30s loop)   │  │
│                  │   └──────┬───────┘  └───────┬────────┘  │
│ proxy            │          │                   │           │
▼                  │          ▼                   ▼           │
┌─────────────┐         │   ┌─────────────────────────────────┐   │
│ sandbox-app │         │   │         envs/*.json              │   │
│  container  │         │   │      logs/$ENV_ID/app.log        │   │
│  :5000      │         │   │      logs/$ENV_ID/health.log     │   │
└─────────────┘         │   └─────────────────────────────────┘   │
└─────────────────────────────────────────┘

---

## Prerequisites

- Docker + Docker Compose
- Python 3.10+
- `pip install fastapi uvicorn requests --break-system-packages`
- Ports 8888, 8000, and 21000-21100 available

---

## Quick Start

```bash
git clone https://github.com/adewumicrown/devops-sandbox
cd devops-sandbox
cp .env.example .env
docker build -t sandbox-demo-app app/
make up
make create   # enter a name and TTL when prompted
```

---

## Demo Walkthrough

```bash
# 1. Start the platform
make up

# 2. Create an environment
make create
# → enter name: myapp, TTL: 300

# 3. Check health
make health

# 4. Simulate a crash
make simulate ENV=<env-id> MODE=crash

# 5. Watch health degrade
tail -f logs/<env-id>/health.log

# 6. Recover
make simulate ENV=<env-id> MODE=recover

# 7. Auto-destroy fires when TTL expires
tail -f logs/cleanup.log
```

---

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | /envs | Create environment |
| GET | /envs | List active envs + TTL remaining |
| DELETE | /envs/:id | Destroy environment |
| GET | /envs/:id/logs | Last 100 lines of app.log |
| GET | /envs/:id/health | Last 10 health checks |
| POST | /envs/:id/outage | Trigger simulation |

---

## Makefile Targets

| Target | Description |
|--------|-------------|
| `make up` | Start Nginx, daemon, poller, API |
| `make down` | Stop everything, destroy all envs |
| `make create` | Create new env (interactive) |
| `make destroy ENV=x` | Destroy specific env |
| `make logs ENV=x` | Tail env app logs |
| `make health` | Show all env health statuses |
| `make simulate ENV=x MODE=y` | Run outage simulation |
| `make clean` | Wipe all state, logs, archives |

---

## Outage Modes

| Mode | Effect |
|------|--------|
| `crash` | docker kill — hard stop |
| `pause` | docker pause — freezes process |
| `network` | docker network disconnect |
| `recover` | Restores whatever was broken |
| `stress` | CPU spike with stress-ng (60s) |

---

## Known Limitations

- Nginx port range (21000-21100) supports max 100 concurrent environments
- Log shipping uses `docker logs -f` (Approach A) — not suitable for high-volume logs
- No authentication on the API
- Cleanup daemon runs every 60s so TTL expiry has up to 60s of lag
- Port detection uses state files, not live system scan — stale state files could cause port conflicts
