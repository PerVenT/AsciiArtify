# AsciiArtify — локальні Kubernetes-кластери для PoC
# Кожен кластер: 3 ноди × 2 CPU × 2 GB RAM, default namespace = dev, ноди — контейнери Docker.
#
#   make minikube        make kind        make k3s   (alias: make k3d)
#   make demo-k3s        make status-kind make delete-minikube   make clean
#
# Параметри можна перевизначити:  make kind NODES=3 NODE_CPUS=2 NODE_MEMORY_MB=2048 NAMESPACE=dev ENGINE=podman

SHELL          := /usr/bin/env bash
SCRIPTS        := ./scripts
CLUSTER_NAME   ?= asciiartify
NODES          ?= 3
NODE_CPUS      ?= 2
NODE_MEMORY_MB ?= 2048
NAMESPACE      ?= dev
ENGINE         ?= docker
AUTO_INSTALL   ?= 1

export CLUSTER_NAME NODES NODE_CPUS NODE_MEMORY_MB NAMESPACE ENGINE AUTO_INSTALL

TOOLS := minikube kind k3s

.DEFAULT_GOAL := help
# Pattern-правила (demo-%, status-%, delete-%) навмисно НЕ в .PHONY: make не шукає
# implicit-правила для phony-цілей, і «make demo-kind» нічого б не зробив.
.PHONY: help $(TOOLS) k3d demo-k3d status-k3d delete-k3d status clean lint

help: ## Показати цю довідку
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_%-]+:.*?## / {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# ---------- Створення кластерів ----------
minikube: ## Кластер minikube (driver docker), 3 ноди
	@$(SCRIPTS)/minikube.sh up

kind: ## Кластер kind, 1 control-plane + 2 workers
	@$(SCRIPTS)/kind.sh up

k3s: ## Кластер k3d (k3s у Docker), 1 server + 2 agents
	@$(SCRIPTS)/k3s.sh up

k3d: k3s

# ---------- Демо Hello World ----------
demo-%: ## Розгорнути Hello World (demo-minikube | demo-kind | demo-k3s)
	@$(SCRIPTS)/demo.sh $*

demo-k3d: demo-k3s

# ---------- Статус / видалення ----------
status-%: ## Стан кластера (status-minikube | status-kind | status-k3s)
	@$(SCRIPTS)/$*.sh status

status-k3d: status-k3s

status: ## Стан усіх кластерів
	@for t in $(TOOLS); do echo "===== $$t ====="; $(SCRIPTS)/$$t.sh status || true; done

delete-%: ## Видалити кластер (delete-minikube | delete-kind | delete-k3s)
	@$(SCRIPTS)/$*.sh down

delete-k3d: delete-k3s

clean: ## Видалити всі три кластери
	@for t in $(TOOLS); do $(SCRIPTS)/$$t.sh down || true; done

lint: ## Перевірити скрипти (bash -n + shellcheck, якщо є)
	@for f in $(SCRIPTS)/*.sh; do bash -n $$f && echo "ok  $$f"; done
	@if command -v shellcheck >/dev/null; then shellcheck -x $(SCRIPTS)/*.sh && echo "shellcheck: ok"; else echo "shellcheck не встановлено — пропускаю"; fi
