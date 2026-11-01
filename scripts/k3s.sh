#!/usr/bin/env bash
# k3d (k3s у Docker): 1 server + 2 agents, кожна нода 2 CPU × 2 GB, default namespace = dev
# Використання: ./scripts/k3s.sh [up|down|status]
# shellcheck source=scripts/common.sh
source "$(dirname "$0")/common.sh"

K3D_CLUSTER="${CLUSTER_NAME}-k3d"
CONTEXT="k3d-${K3D_CLUSTER}"

use_podman_socket() {
  [[ "$ENGINE" == podman ]] || return 0
  # k3d працює через Docker API — направляємо його на сокет Podman
  if [[ -z "${DOCKER_HOST:-}" ]]; then
    local sock
    sock="$(podman info --format '{{.Host.RemoteSocket.Path}}' 2>/dev/null || true)"
    [[ -n "$sock" ]] || die "Не знайдено сокет Podman. Увімкніть: systemctl --user enable --now podman.socket"
    export DOCKER_HOST="unix://${sock#unix://}"
  fi
  export DOCKER_SOCK="${DOCKER_HOST#unix://}"
  log "k3d → Podman через DOCKER_HOST=$DOCKER_HOST"
}

up() {
  preflight
  ensure_tool k3d
  ensure_tool kubectl
  use_podman_socket

  local agents=$(( NODES - 1 ))
  log "Створюю k3d-кластер '$K3D_CLUSTER' (1 server + $agents agents, рушій $ENGINE)"
  # --servers-memory/--agents-memory — нативний ліміт RAM у k3d;
  # ліміт CPU k3d не підтримує → застосовуємо після створення через '$ENGINE update'
  k3d cluster create "$K3D_CLUSTER" \
    --servers 1 \
    --agents "$agents" \
    --servers-memory "${NODE_MEMORY_MB}m" \
    --agents-memory "${NODE_MEMORY_MB}m" \
    --port "8080:80@loadbalancer" \
    --kubeconfig-update-default \
    --kubeconfig-switch-context \
    --wait

  # shellcheck disable=SC2046  # імена нод без пробілів; без mapfile — сумісно з bash 3.2 (macOS)
  limit_node_containers $(k3d node list | awk -v c="$K3D_CLUSTER" 'NR>1 && $3==c && ($2=="server" || $2=="agent") {print $1}')

  kubectl config use-context "$CONTEXT" >/dev/null
  wait_nodes_ready
  set_default_namespace
  show_summary "k3d-${K3D_CLUSTER}-"
  echo "Ingress (Traefik) доступний на http://localhost:8080"
}

down()   { ensure_tool k3d; use_podman_socket; k3d cluster delete "$K3D_CLUSTER"; }
status() { ensure_tool k3d; use_podman_socket; k3d cluster list; k3d node list; kubectl --context "$CONTEXT" get nodes -o wide 2>/dev/null || true; }

case "${1:-up}" in
  up) up ;; down) down ;; status) status ;;
  *) die "Використання: $0 [up|down|status]" ;;
esac
