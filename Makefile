GH_USER ?= saisushaman
IMAGE   ?= ghcr.io/$(GH_USER)/gitops-cicd-pipeline
TAG     ?= local

.PHONY: help install test run docker-build cluster-up cluster-down status app-url argo-ui

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

install: ## Install app + dev dependencies
	pip install -r app/requirements-dev.txt

test: ## Run unit tests
	pytest

run: ## Run the service locally on :8000
	uvicorn app.main:app --reload --port 8000

docker-build: ## Build the container image locally
	docker build -t $(IMAGE):$(TAG) \
	  --build-arg APP_VERSION=$(TAG) --build-arg GIT_SHA=local ./app

cluster-up: ## Create kind cluster, install Argo CD, deploy the app (GitOps)
	./cluster/setup.sh

cluster-down: ## Delete the kind cluster
	./cluster/teardown.sh

status: ## Show Argo CD Application + app pods
	@kubectl -n argocd get applications.argoproj.io gitops-demo 2>/dev/null || true
	@kubectl -n demo get deploy,pods 2>/dev/null || true

app-url: ## Port-forward the app to localhost:8080
	@echo "curl http://localhost:8080/healthz"
	kubectl -n demo port-forward svc/gitops-demo 8080:80

argo-ui: ## Port-forward the Argo CD UI to localhost:8443
	@echo "https://localhost:8443  (user: admin)"
	kubectl -n argocd port-forward svc/argocd-server 8443:443
