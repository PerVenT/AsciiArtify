#!/usr/bin/env bash
# kind: 1 control-plane + 2 workers, кожна нода 2 CPU × 2 GB, default namespace = dev
# Використання: ./scripts/kind.sh [up|down|status]
# shellcheck source=scripts/common.sh
source "$(dirname "$0")/common.sh"

KIND_CLUSTER="${CLUSTER_NAME}-kind"
CONTEXT="kind-${KIND_CLUSTER}"

up() {
  preflight
  ensure_tool kind
  ensure_tool kubectl
  [[ "$ENGINE" == podman ]] && export KIND_EXPERIMENTAL_PROVIDER=podman

  # Конфіг генерується з урахуванням NODES (1 control-plane + решта workers)
  local cfg; cfg="$(mktemp)"
  {
    echo "kind: Cluster"
    echo "apiVersion: kind.x-k8s.io/v1alpha4"
    echo "name: ${KIND_CLUSTER}"
    echo "nodes:"
    echo "  - role: control-plane"
    for ((i = 1; i < NODES; i++)); do echo "  - role: worker"; done
  } >"$cfg"

  log "Створюю kind-кластер '$KIND_CLUSTER' ($NODES ноди, провайдер $ENGINE)"
  kind create cluster --config "$cfg" --wait 300s
  rm -f "$cfg"

  # kind не має власних параметрів CPU/RAM для нод — обмежуємо контейнери засобами рушія
  # shellcheck disable=SC2046  # імена нод без пробілів; без mapfile — сумісно з bash 3.2 (macOS)
  limit_node_containers $(kind get nodes --name "$KIND_CLUSTER")
  # Встановити Gateway API CRDs у кластер
  kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.7.0/standard-install.yaml
  kubectl config use-context "$CONTEXT" >/dev/null
  wait_nodes_ready
  set_default_namespace
  show_summary "$KIND_CLUSTER"
  warn "kind: kubelet бачить ресурси хоста (kubectl describe node), фактичний ліміт тримає cgroup контейнера."
}

down() {
  ensure_tool kind
  [[ "$ENGINE" == podman ]] && export KIND_EXPERIMENTAL_PROVIDER=podman
  kind delete cluster --name "$KIND_CLUSTER"
}

status() {
  ensure_tool kind
  [[ "$ENGINE" == podman ]] && export KIND_EXPERIMENTAL_PROVIDER=podman
  kind get clusters
  kubectl --context "$CONTEXT" get nodes -o wide 2>/dev/null || true
}

case "${1:-up}" in
  up) up ;; down) down ;; status) status ;;
  *) die "Використання: $0 [up|down|status]" ;;
esac
