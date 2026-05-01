# Convenience targets for local dev. CI does not call these.

TF_DIRS := bootstrap $(wildcard environments/*)

.PHONY: help fmt fmt-check validate tflint checkov plan-dev plan-staging plan-prod check

help:
	@echo "Targets:"
	@echo "  fmt           — terraform fmt -recursive (write changes)"
	@echo "  fmt-check     — terraform fmt -check -recursive (CI mode)"
	@echo "  validate      — terraform validate every stack (no backend)"
	@echo "  tflint        — tflint --recursive with .tflint.hcl"
	@echo "  checkov       — checkov over modules + envs + bootstrap"
	@echo "  check         — fmt-check + validate + tflint + checkov"
	@echo "  plan-dev      — terraform plan in environments/dev"
	@echo "  plan-staging  — same for staging"
	@echo "  plan-prod     — same for prod"

fmt:
	terraform fmt -recursive

fmt-check:
	terraform fmt -check -recursive

validate:
	@set -e; for d in $(TF_DIRS); do \
	  echo "==> validate $$d"; \
	  ( cd "$$d" && terraform init -backend=false -input=false >/dev/null && terraform validate ); \
	done

tflint:
	tflint --init
	tflint --recursive --config="$(PWD)/.tflint.hcl"

checkov:
	checkov \
	  --directory modules \
	  --directory environments \
	  --directory bootstrap \
	  --config-file .checkov.yml

check: fmt-check validate tflint checkov

plan-dev:
	cd environments/dev && terraform plan

plan-staging:
	cd environments/staging && terraform plan

plan-prod:
	cd environments/prod && terraform plan
