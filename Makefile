# AsciiArtify — локальні Kubernetes-кластери для PoC
# Кожен кластер: 3 ноди × 2 CPU × 2 GB RAM, default namespace = dev, ноди — контейнери Docker.
#
#   make minikube        make kind        make k3d
#   make demo-k3d        make status-kind make delete-minikube   make clean
#
# Параметри можна перевизначити:  make kind NODES=3 NODE_CPUS=2 NODE_MEMORY_MB=2048 NAMESPACE=dev ENGINE=podman

SHELL          := /usr/bin/env bash
SCRIPTS        := ./scripts
CLUSTER_NAME   ?=
NODES          ?= 3
NODE_CPUS      ?= 2
NODE_MEMORY_MB ?= 2048
NAMESPACE      ?=
ENGINE         ?=
AUTO_INSTALL   ?= 1

# ===================================================
ENV                ?= dev-local
ENV_FILE           := deploy/envs/$(ENV).yaml
DOMAIN             ?= localtest.me
AUTHELIA_NAMESPACE ?= authelia
ARGOCD_NAMESPACE   ?= argocd

# ===================================================
export CLUSTER_NAME NODES NODE_CPUS NODE_MEMORY_MB NAMESPACE ENGINE AUTO_INSTALL DOMAIN AUTHELIA_NAMESPACE ARGOCD_NAMESPACE

TOOLS := minikube kind k3d

.DEFAULT_GOAL := help
# Pattern-правила (demo-%, status-%, delete-%) навмисно НЕ в .PHONY: make не шукає
# implicit-правила для phony-цілей, і «make demo-kind» нічого б не зробив.
.PHONY: help $(TOOLS) k3d status clean lint helm-deps dev dev-local dev-gitops

help: ## Показати цю довідку
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_%-]+:.*?## / {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

helm-deps: ## Завантажити залежності локальних Helm-чартів
	@for c in cert-manager traefik authelia argocd; do \
		helm dependency build deploy/platform/$$c; \
	done

dev: dev-local ## Аліас для dev-local (локальний dev-цикл без ArgoCD)

dev-local: helm-deps ## Локальний dev-контур без ArgoCD (cert-manager, mesh-pki, traefik, authelia, demo)
	helm upgrade --install cert-manager deploy/platform/cert-manager --create-namespace --namespace cert-manager --wait
	helm upgrade --install mesh-pki deploy/platform/mesh-pki --namespace cert-manager --wait -f $(ENV_FILE)
	kubectl wait --for=condition=Ready clusterissuer/mesh --timeout=60s
	helm upgrade --install traefik deploy/platform/traefik --create-namespace --namespace traefik --wait -f $(ENV_FILE)
	kubectl wait --for=condition=Ready certificate/traefik-wildcard-tls -n traefik --timeout=60s
	bash $(SCRIPTS)/authelia-secrets.sh
	helm upgrade --install authelia deploy/platform/authelia --create-namespace --namespace $(AUTHELIA_NAMESPACE) --wait -f $(ENV_FILE)
	helm upgrade --install whoami deploy/whoami --create-namespace --namespace whoami --set "ingress.host=app.$(DOMAIN)"

dev-gitops: dev-local ## Зовнішній dev-контур з ArgoCD
	bash $(SCRIPTS)/render-argocd-oidc.sh
	helm upgrade --install argocd deploy/platform/argocd --create-namespace --namespace $(ARGOCD_NAMESPACE) --wait \
		-f $(ENV_FILE) \
		-f state/argocd/oidc-values.yml \
		--set-file 'argo-cd.configs.secret.extra.oidc\.argocd\.clientSecret=state/authelia/argocd_client_secret'
# ---------- Створення кластерів ----------
minikube: ## Кластер minikube (driver docker), 3 ноди
	@$(SCRIPTS)/minikube.sh up

kind: ## Кластер kind, 1 control-plane + 2 workers
	@$(SCRIPTS)/kind.sh up

k3d: ## Кластер k3d, 1 server + 2 agents
	@$(SCRIPTS)/k3d.sh up

# ---------- Демо whoami ----------
demo-%: ## Розгорнути whoami (demo-minikube | demo-kind | demo-k3d)
	@$(SCRIPTS)/demo.sh $*
	
# ---------- Статус / видалення ----------
status-%: ## Стан кластера (status-minikube | status-kind | status-k3d)
	@$(SCRIPTS)/$*.sh status

status: ## Стан усіх кластерів
	@for t in $(TOOLS); do echo "===== $$t ====="; $(SCRIPTS)/$$t.sh status || true; done

delete-%: ## Видалити кластер (delete-minikube | delete-kind | delete-k3d)
	@$(SCRIPTS)/$*.sh down

clean: ## Видалити всі три кластери
	@for t in $(TOOLS); do $(SCRIPTS)/$$t.sh down || true; done

lint: ## Перевірити Helm-чарти та скрипти (helm lint + bash -n + shellcheck)
	helm lint deploy/demo --set "ingress.host=demo.$(DOMAIN)"
	helm lint deploy/platform/cert-manager
	helm lint deploy/platform/mesh-pki -f $(ENV_FILE)
	helm lint deploy/platform/traefik -f $(ENV_FILE)
	helm lint deploy/platform/authelia -f $(ENV_FILE) --skip-schema-validation
	helm lint deploy/platform/argocd -f $(ENV_FILE)
	helm lint deploy/gitops --set repoURL=https://github.com/org/repo.git --set env=staging
	@for f in $(SCRIPTS)/*.sh; do bash -n $$f && echo "ok  $$f"; done
	@if command -v shellcheck >/dev/null; then shellcheck -x $(SCRIPTS)/*.sh && echo "shellcheck: ok"; else echo "shellcheck не встановлено — пропускаю"; fi
