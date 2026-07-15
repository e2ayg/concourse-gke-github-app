# Developer convenience targets. Run `make help` for the list.
# None of these run `terraform apply`/`destroy`.

TF_DIRS := modules/concourse-gke-github-app examples/basic

.DEFAULT_GOAL := help
.PHONY: help fmt fmt-check validate tflint checkov trivy gitleaks bandit ruff \
        shellcheck hadolint precommit lint security all

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

fmt: ## terraform fmt (write)
	terraform fmt -recursive

fmt-check: ## terraform fmt (check only)
	terraform fmt -check -recursive

validate: ## terraform init (no backend) + validate for each dir
	@for d in $(TF_DIRS); do \
	  echo "== validate $$d =="; \
	  terraform -chdir=$$d init -backend=false -input=false >/dev/null && \
	  terraform -chdir=$$d validate; \
	done

tflint: ## Lint Terraform with tflint
	tflint --init
	tflint --recursive -f compact

checkov: ## Static security scan (Terraform/Docker/Actions/secrets)
	checkov --config-file .checkov.yaml

trivy: ## Vulnerability + misconfig + secret scan
	trivy fs --config trivy.yaml .

gitleaks: ## Secret scan of the working tree
	gitleaks dir --config .gitleaks.toml .

bandit: ## Python security scan (via uv)
	uvx --from "bandit[toml]" bandit -c pyproject.toml -r token-refresher

ruff: ## Python lint + format check (via uv)
	uvx ruff check token-refresher
	uvx ruff format --check token-refresher

shellcheck: ## Shell script lint
	shellcheck scripts/*.sh

hadolint: ## Dockerfile lint
	hadolint --config .hadolint.yaml token-refresher/Dockerfile

precommit: ## Run all pre-commit hooks
	pre-commit run --all-files

lint: fmt-check validate tflint ruff shellcheck hadolint ## Run all linters

security: checkov trivy gitleaks bandit ## Run all security scanners

all: lint security ## Run everything
