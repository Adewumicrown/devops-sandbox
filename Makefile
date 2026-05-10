-include .env
export

.PHONY: up down create destroy logs health simulate clean

up:
	@echo "▶ Starting Nginx, cleanup daemon, health poller, and API..."
	@echo "TODO: implement"

down:
	@echo "▶ Stopping everything and destroying all envs..."
	@echo "TODO: implement"

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
	@echo "▶ Health status of all active environments:"
	@echo "TODO: implement"

simulate:
	@[ -n "$(ENV)" ] || (echo "❌ Usage: make simulate ENV=<env-id> MODE=<mode>" && exit 1)
	@[ -n "$(MODE)" ] || (echo "❌ MODE required: crash|pause|network|recover|stress" && exit 1)
	@bash platform/simulate_outage.sh --env "$(ENV)" --mode "$(MODE)"

clean:
	@echo "▶ Wiping all state, logs, and archives..."
	@rm -rf logs/* envs/*
	@echo "✅ Cleaned"
