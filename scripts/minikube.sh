#!/usr/bin/env bash
# minikube: 3 ноди × 2 CPU × 2 GB у Docker (або Podman), default namespace = dev
# Використання: ./scripts/minikube.sh [up|down|status]
# shellcheck source=scripts/common.sh
source "$(dirname "$0")/common.sh"

PROFILE="${CLUSTER_NAME}-minikube"

up() {
  preflight
  ensure_tool minikube
  ensure_tool kubectl

  local extra=()
  # Для podman minikube рекомендує containerd як runtime
  [[ "$ENGINE" == podman ]] && extra+=(--container-runtime=containerd)

  log "Створюю minikube-кластер '$PROFILE' ($NODES ноди, драйвер $ENGINE)"
  # --cpus / --memory у minikube застосовуються до КОЖНОЇ ноди
  minikube start \
    --profile "$PROFILE" \
    --driver "$ENGINE" \
    --nodes "$NODES" \
    --cpus "$NODE_CPUS" \
    --memory "${NODE_MEMORY_MB}mb" \
    --addons metrics-server \
    ${extra[@]+"${extra[@]}"}

  kubectl config use-context "$PROFILE" >/dev/null
  wait_nodes_ready
  set_default_namespace
  show_summary "$PROFILE"
  echo "Dashboard: minikube dashboard -p $PROFILE"
}

# Профіль існує? '--light' не опитує контейнерний рушій. Результат у змінну (не pipe в 'grep -q'),
# щоб під pipefail не отримати хибний SIGPIPE.
profile_exists() {
  local out
  out="$(minikube profile list --light -o json 2>/dev/null || true)"
  [[ "$out" =~ \"Name\"\ *:\ *\"${PROFILE}\" ]]
}

# 'minikube delete' для неіснуючого профілю все одно шукає рештки в доступних рушіях
# (зокрема у віддаленому docker context) → викликаємо його лише якщо профіль є
down() {
  ensure_tool minikube
  if profile_exists; then
    minikube delete --profile "$PROFILE"
  else
    log "minikube-профіль '$PROFILE' не існує — нічого видаляти"
  fi
}
status() { ensure_tool minikube; minikube status --profile "$PROFILE" || true; kubectl --context "$PROFILE" get nodes -o wide 2>/dev/null || true; }

case "${1:-up}" in
  up) up ;; down) down ;; status) status ;;
  *) die "Використання: $0 [up|down|status]" ;;
esac
