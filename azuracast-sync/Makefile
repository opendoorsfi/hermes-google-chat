.PHONY: test lint validate

SHELL_SCRIPTS := scripts/self_heal_azuracast.sh scripts/github_actions_load_gcp_env.sh

test:
	python3 -m pytest tests/ -v

lint:
	@for s in $(SHELL_SCRIPTS); do bash -n "$$s" || exit 1; done

validate: test lint
	@echo "validate ok"
