#!/usr/bin/env bash
# Демонстрація: розгортання «whoami» у namespace dev поточного кластера
# Використання: ./scripts/demo.sh <minikube|kind|k3s> [deploy|delete]
# shellcheck source=scripts/common.sh
source "$(dirname "$0")/common.sh"

case "${1:-}" in
  minikube) CONTEXT="${CLUSTER_NAME}-minikube" ;;
  kind)     CONTEXT="kind-${CLUSTER_NAME}-kind" ;;
  k3s|k3d)  CONTEXT="k3d-${CLUSTER_NAME}-k3d" ;;
  *) die "Використання: $0 <minikube|kind|k3s> [deploy|delete]" ;;
esac
ACTION="${2:-deploy}"
LOCAL_PORT="${LOCAL_PORT:-8088}"
# -n передаємо лише якщо NAMESPACE задано явно; інакше kubectl бере namespace поточного контексту
K="kubectl --context $CONTEXT${NAMESPACE:+ -n $NAMESPACE}"

ensure_tool kubectl
kubectl config get-contexts "$CONTEXT" >/dev/null 2>&1 || die "Контекст '$CONTEXT' не знайдено — спершу 'make $1'"

if [[ "$ACTION" == delete ]]; then
  $K delete deployment,service whoami --ignore-not-found
  exit 0
fi

TARGET_NS="${NAMESPACE:-$(kubectl --context "$CONTEXT" config view --minify -o jsonpath='{..namespace}' 2>/dev/null)}"
log "Розгортаю whoami у $CONTEXT / namespace ${TARGET_NS:-default}"
$K apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: whoami
  labels: { app: whoami }
spec:
  replicas: 3
  selector:
    matchLabels: { app: whoami }
  template:
    metadata:
      labels: { app: whoami }
    spec:
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels: { app: whoami }
      containers:
        - name: whoami
          image: traefik/whoami:v1.12.0
          args: ["--port=5678"]
          ports: [{ containerPort: 5678 }]
          resources:
            requests: { cpu: 10m, memory: 16Mi }
            limits:   { cpu: 100m, memory: 32Mi }
          readinessProbe:
            httpGet: { path: /, port: 5678 }
---
apiVersion: v1
kind: Service
metadata:
  name: whoami
spec:
  selector: { app: whoami }
  ports:
    - port: 80
      targetPort: 5678
EOF

$K rollout status deployment/whoami --timeout=180s
$K get pods -l app=whoami -o wide

log "Port-forward localhost:${LOCAL_PORT} → svc/whoami:80"
$K port-forward svc/whoami "${LOCAL_PORT}:80" >/dev/null 2>&1 &
PF_PID=$!
trap 'kill $PF_PID 2>/dev/null || true' EXIT

for _ in $(seq 1 20); do
  # перший рядок відповіді whoami: «Hostname: <под>» (sed, а не head — щоб curl не ловив SIGPIPE під pipefail)
  if resp="$(curl -fsS "http://localhost:${LOCAL_PORT}" 2>/dev/null | sed -n 1p)" && [[ -n "$resp" ]]; then
    ok "Відповідь сервісу: $resp"
    exit 0
  fi
  sleep 0.5
done
die "Сервіс не відповів на localhost:${LOCAL_PORT}"
