.PHONY: help lint test build deploy-dev deploy-staging deploy-prod helm-lint terraform-plan clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

lint: ## Lint Terraform, Helm charts, and YAML
	terraform -chdir=terraform/environments/dev fmt -check -recursive
	helm lint helm-charts/app/ -f helm-charts/app/ci/test-values.yaml
	yamllint kubernetes/ .github/

test: ## Run Terraform and Helm tests
	cd terraform/modules/vpc/tests && go test -v -timeout 30m
	cd terraform/modules/eks/tests && go test -v -timeout 30m
	helm template app helm-charts/app/ -f helm-charts/app/ci/test-values.yaml > /dev/null

build: ## Build Docker images locally
	docker build -t devops-platform/app:local kubernetes/base/

deploy-dev: ## Deploy to dev environment
	./scripts/deploy.sh dev

deploy-staging: ## Deploy to staging environment
	./scripts/deploy.sh staging

deploy-prod: ## Deploy to production (requires confirmation)
	@echo "WARNING: You are about to deploy to PRODUCTION"
	@read -p "Are you sure? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1
	./scripts/deploy.sh prod

helm-lint: ## Lint and template Helm chart
	helm lint helm-charts/app/
	helm template app helm-charts/app/ -f helm-charts/app/ci/test-values.yaml
	@echo "Helm chart is valid"

terraform-plan: ## Run Terraform plan for dev
	cd terraform/environments/dev && terraform init && terraform plan

terraform-validate: ## Validate all Terraform configs
	cd terraform/environments/dev && terraform init -backend=false && terraform validate
	cd terraform/environments/staging && terraform init -backend=false && terraform validate
	cd terraform/environments/prod && terraform init -backend=false && terraform validate

argocd-sync: ## Sync ArgoCD applications
	argocd app sync devops-platform-dev
	argocd app wait devops-platform-dev --health

local-setup: ## Set up local Minikube environment
	./scripts/setup-local.sh

clean: ## Clean up local resources
	./scripts/cleanup.sh
