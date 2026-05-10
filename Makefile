-include .env
export

.PHONY: up down create destroy logs health simulate clean

up:
	bash platform/start.sh

down:
	@echo "▶ Stopping platform..."
	@for f in envs/*.json; do \
		[ -f "$$f" ] || continue; \
		id=$$(python3 -c "import json; print(json.load(open('$$f'))['id'])"); \
		bash platform/destroy_env.sh "$$id"; \
	done
	@pkill -f cleanup_daemon.sh 2>/dev/null || true
	@pkill -f poller.py 2>/dev/null || true
	@pkill -f sandbox_api 2>/dev/null || true
	@docker compose down
	@echo "✅ Platform down"

create:
	@read -p "Env name: " name; \
	 read -p "TTL in seconds [1800]: " ttl; \
	 ttl=$${ttl:-1800}; \
	 bash platform/create_env.sh "$$name" "$$ttl"

destroy:
	@[ -n "$(ENV)" ] || (echo "❌ Usage: make destroy ENV=<env-id>" && exit 1)
	@bash platform/destroy_env.sh "$(ENV)"

logs:
	@[ -n "$(ENV)" ] || (echo "❌ Usage: make logs ENV=<env-id>" && exit 1)
	@tail -f logs/$(ENV)/app.log

health:
	@echo "ENV ID             NAME         STATUS     TTL LEFT"
	@echo "─────────────────────────────────────────────────────"
	@for f in envs/*.json; do \
		[ -f "$$f" ] || continue; \
		python3 -c "\
import json, time; \
d=json.load(open('$$f')); \
left=max(0,(d['created_at']+d['ttl'])-int(time.time())); \
print(f\"{d['id']:<18} {d['name']:<12} {d['status']:<10} {left}s\") \
"; \
	done

simulate:
	@[ -n "$(ENV)" ] || (echo "❌ Usage: make simulate ENV=<env-id> MODE=<crash|pause|network|recover>" && exit 1)
	@[ -n "$(MODE)" ] || (echo "❌ MODE required: crash|pause|network|recover|stress" && exit 1)
	@bash platform/simulate_outage.sh --env "$(ENV)" --mode "$(MODE)"

clean:
	@echo "▶ Wiping all state, logs, and archives..."
	@rm -rf logs/* envs/*
	@mkdir -p logs/archived
	@echo "✅ Cleaned"
