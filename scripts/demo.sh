#!/usr/bin/env bash
# Демонстрація: розгортання «Hello World» у namespace dev поточного кластера
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
K="kubectl --context $CONTEXT -n $NAMESPACE"

ensure_tool kubectl
kubectl config get-contexts "$CONTEXT" >/dev/null 2>&1 || die "Контекст '$CONTEXT' не знайдено — спершу 'make $1'"

if [[ "$ACTION" == delete ]]; then
  $K delete deployment,service hello-world --ignore-not-found
  exit 0
fi

log "Розгортаю hello-world у $CONTEXT / namespace $NAMESPACE"
$K apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-world
  labels: { app: hello-world }
spec:
  replicas: 3
  selector:
    matchLabels: { app: hello-world }
  template:
    metadata:
      labels: { app: hello-world }
    spec:
      # розносимо репліки по різних нодах, щоб побачити роботу мультинодового кластера
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels: { app: hello-world }
      containers:
        - name: hello
          image: hashicorp/http-echo:1.0
          args: ["-listen=:5678", "-text=Hello World from AsciiArtify!"]
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
  name: hello-world
spec:
  selector: { app: hello-world }
  ports:
    - port: 80
      targetPort: 5678
EOF

$K rollout status deployment/hello-world --timeout=180s
$K get pods -l app=hello-world -o wide

log "Port-forward localhost:${LOCAL_PORT} → svc/hello-world:80"
$K port-forward svc/hello-world "${LOCAL_PORT}:80" >/dev/null 2>&1 &
PF_PID=$!
trap 'kill $PF_PID 2>/dev/null || true' EXIT

for _ in $(seq 1 20); do
  if resp="$(curl -fsS "http://localhost:${LOCAL_PORT}" 2>/dev/null)"; then
    ok "Відповідь сервісу: $resp"
    exit 0
  fi
  sleep 0.5
done
die "Сервіс не відповів на localhost:${LOCAL_PORT}"
