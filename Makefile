.PHONY: test lint build validate local-check standalone-check

SHELL_SCRIPTS := infra/setup_gcp.sh infra/setup_tenant_gcp.sh \
	deploy/cloudrun/deploy.sh deploy/entrypoint.sh deploy/host/tailscale-funnel.sh \
	scripts/lib/tenant.sh scripts/bootstrap_github_secrets.sh \
	scripts/bootstrap_hermes_host.sh scripts/bootstrap_hermes_mac.sh \
	scripts/sync_mac_from_registry.sh $(wildcard scripts/*.sh)

test:
	python3 -m pytest tests/ -v

lint:
	@for s in $(SHELL_SCRIPTS); do bash -n "$$s" || exit 1; done
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck -S warning -x $(SHELL_SCRIPTS) && echo "shellcheck ok"; \
	else \
		echo "shellcheck ei asennettu — vain bash -n (asenna: apt-get install shellcheck)"; \
	fi

build:
	docker build -t hermes-google-chat:local -f deploy/Dockerfile .

validate: test lint
	@echo "validate ok"

standalone-check:
	@bash scripts/export_standalone_check.sh

local-check: validate
	@test -f deploy/Dockerfile
	@test -f infra/setup_gcp.sh
	@echo "local-check ok — run 'make build' when Docker is available"
