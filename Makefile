.PHONY: test lint build validate local-check

test:
	python3 -m pytest tests/ -v

lint:
	@bash -n infra/setup_gcp.sh
	@bash -n infra/setup_tenant_gcp.sh
	@bash -n deploy/cloudrun/deploy.sh
	@bash -n deploy/entrypoint.sh
	@bash -n deploy/host/tailscale-funnel.sh
	@bash -n scripts/lib/tenant.sh
	@bash -n scripts/print_tenant_env.sh
	@bash -n scripts/verify_tenant.sh
	@bash -n scripts/install_hermes_host.sh
	@bash -n scripts/provision_tenant.sh
	@bash -n scripts/*.sh
	@echo "shellcheck ok (bash -n)"

build:
	docker build -t hermes-google-chat:local -f deploy/Dockerfile .

validate: test lint
	@echo "validate ok"

local-check: validate
	@test -f deploy/Dockerfile
	@test -f infra/setup_gcp.sh
	@echo "local-check ok — run 'make build' when Docker is available"
