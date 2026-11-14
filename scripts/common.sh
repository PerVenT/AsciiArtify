#!/usr/bin/env bash
# Спільні налаштування та функції для minikube.sh / kind.sh / k3s.sh / demo.sh
# Підключається через: source "$(dirname "$0")/common.sh"

set -euo pipefail

# ---------- Параметри (можна перевизначити через змінні оточення або make VAR=...) ----------
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER_NAME="${CLUSTER_NAME:-$(basename "$ROOT_DIR" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g')}"
NODES="${NODES:-3}"                 # загальна кількість нод (1 control-plane + N-1 workers)
NODE_CPUS="${NODE_CPUS:-2}"         # ядер на ноду
NODE_MEMORY_MB="${NODE_MEMORY_MB:-2048}"  # RAM на ноду, МБ
NAMESPACE="${NAMESPACE:-}"          # порожньо = не задано: при створенні кластера → DEFAULT_NAMESPACE, у demo → поточний namespace контексту
DEFAULT_NAMESPACE="dev"             # default namespace для щойно створеного кластера
ENGINE="${ENGINE:-}"                # docker | podman; порожньо = автовизначення (див. detect_engine)

BIN_DIR="${BIN_DIR:-$ROOT_DIR/bin}"
export PATH="$BIN_DIR:$PATH"

# ---------- Логування ----------
c_info=$'\033[1;34m'; c_ok=$'\033[1;32m'; c_warn=$'\033[1;33m'; c_err=$'\033[1;31m'; c_off=$'\033[0m'
log()  { printf '%s==>%s %s\n' "$c_info" "$c_off" "$*"; }
ok()   { printf '%s ✔ %s %s\n' "$c_ok" "$c_off" "$*"; }
warn() { printf '%s ! %s %s\n' "$c_warn" "$c_off" "$*" >&2; }
die()  { printf '%s ✖ %s %s\n' "$c_err" "$c_off" "$*" >&2; exit 1; }

# ---------- Автовизначення контейнерного рушія ----------
# Пріоритет: локальний Docker → Podman. Docker вважається доступним, лише якщо його активний
# endpoint локальний (unix://) і daemon відповідає: віддалений docker context (ssh://, tcp://)
# ігноруємо, щоб кластери випадково не створювалися на іншому сервері.
# Явний ENGINE=docker|podman завжди має пріоритет.
docker_is_local() {
  command -v docker >/dev/null 2>&1 || return 1
  local host
  host="$(docker context inspect --format '{{.Endpoints.docker.Host}}' 2>/dev/null || true)"
  [[ -z "$host" || "$host" == unix://* ]] || return 1
  docker info >/dev/null 2>&1
}

detect_engine() {
  if docker_is_local; then
    ENGINE=docker
  elif command -v podman >/dev/null 2>&1; then
    ENGINE=podman
    command -v docker >/dev/null 2>&1 && warn "Локального Docker немає (docker вказує на віддалений context) → використовую podman"
  elif command -v docker >/dev/null 2>&1; then
    die "Docker вказує на віддалений context, а podman не встановлено. Якщо справді потрібен цей Docker — вкажіть ENGINE=docker явно"
  else
    die "Не знайдено ні локального docker, ні podman"
  fi
  log "Автовизначено рушій: $ENGINE"
}
[[ -n "$ENGINE" ]] || detect_engine

# ---------- Платформа ----------
detect_platform() {
  OS="$(uname -s | tr '[:upper:]' '[:lower:]')"          # linux | darwin
  case "$(uname -m)" in
    x86_64|amd64) ARCH=amd64 ;;
    aarch64|arm64) ARCH=arm64 ;;
    *) die "Непідтримувана архітектура: $(uname -m)" ;;
  esac
  case "$OS" in linux|darwin) ;; *) die "Скрипти розраховані на Linux/macOS (Windows → WSL2)";; esac
}

# ---------- Встановлення відсутніх утиліт у ./bin ----------
install_tool() {
  local name="$1" url="$2"
  mkdir -p "$BIN_DIR"
  log "Встановлюю $name → $BIN_DIR/$name"
  curl -fsSL -o "$BIN_DIR/$name" "$url" || die "Не вдалося завантажити $name з $url"
  chmod +x "$BIN_DIR/$name"
}

# Helm поставляється архівом (бінарник у <os>-<arch>/helm), тому install_tool не підходить.
# Версія: HELM_VERSION=vX.Y.Z або остання. Контрольну суму звіряємо з get.helm.sh.
install_helm() {
  local v="${HELM_VERSION:-}" file tmp
  [[ -n "$v" ]] || v="$(curl -fsSL -o /dev/null -w '%{url_effective}' https://github.com/helm/helm/releases/latest | sed 's#.*/tag/##')"
  file="helm-${v}-${OS}-${ARCH}.tar.gz"
  tmp="$(mktemp -d)"
  log "Встановлюю helm ${v} → $BIN_DIR/helm"
  curl -fsSL -o "$tmp/$file" "https://get.helm.sh/$file" || die "Не вдалося завантажити $file"
  curl -fsSL -o "$tmp/$file.sha256sum" "https://get.helm.sh/$file.sha256sum" || die "Не вдалося завантажити контрольну суму"
  # sha256sum є в Linux; на macOS його немає → shasum -a 256
  if command -v sha256sum >/dev/null 2>&1; then
    (cd "$tmp" && sha256sum -c "$file.sha256sum" >/dev/null) || die "Контрольна сума $file не збігається"
  else
    (cd "$tmp" && shasum -a 256 -c "$file.sha256sum" >/dev/null) || die "Контрольна сума $file не збігається"
  fi
  tar -xzf "$tmp/$file" -C "$tmp"
  mkdir -p "$BIN_DIR"
  install -m 0755 "$tmp/${OS}-${ARCH}/helm" "$BIN_DIR/helm"
  rm -rf "$tmp"
}

ensure_tool() {
  local name="$1"
  command -v "$name" >/dev/null 2>&1 && return 0
  [[ "${AUTO_INSTALL:-1}" == "1" ]] || die "Не знайдено '$name'. Встановіть вручну або запустіть з AUTO_INSTALL=1"
  detect_platform
  case "$name" in
    kubectl)
      local v; v="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
      install_tool kubectl "https://dl.k8s.io/release/${v}/bin/${OS}/${ARCH}/kubectl" ;;
    kind)
      install_tool kind "https://kind.sigs.k8s.io/dl/latest/kind-${OS}-${ARCH}" ;;
    minikube)
      install_tool minikube "https://storage.googleapis.com/minikube/releases/latest/minikube-${OS}-${ARCH}" ;;
    k3d)
      local v; v="$(curl -fsSL -o /dev/null -w '%{url_effective}' https://github.com/k3d-io/k3d/releases/latest | sed 's#.*/tag/##')"
      install_tool k3d "https://github.com/k3d-io/k3d/releases/download/${v}/k3d-${OS}-${ARCH}" ;;
    helm)
      install_helm ;;
    *) die "Не знаю, як встановити '$name'" ;;
  esac
}

# ---------- Перевірка контейнерного рушія та ресурсів ----------
preflight() {
  case "$ENGINE" in docker|podman) ;; *) die "ENGINE має бути docker або podman (отримано: $ENGINE)";; esac
  command -v "$ENGINE" >/dev/null 2>&1 || die "'$ENGINE' не встановлено"
  "$ENGINE" info >/dev/null 2>&1 || die "'$ENGINE' не відповідає. Запустіть daemon / 'podman machine start'"

  local host_cpus host_mem_mb need_cpus need_mem
  if [[ "$ENGINE" == docker ]]; then
    host_cpus="$(docker info --format '{{.NCPU}}')"
    host_mem_mb="$(( $(docker info --format '{{.MemTotal}}') / 1024 / 1024 ))"
  else
    host_cpus="$(podman info --format '{{.Host.CPUs}}')"
    host_mem_mb="$(( $(podman info --format '{{.Host.MemTotal}}') / 1024 / 1024 ))"
  fi
  need_cpus="$NODE_CPUS"                          # ліміт CPU не може перевищувати кількість ядер хоста
  need_mem="$(( NODES * NODE_MEMORY_MB ))"
  log "Рушій: $ENGINE | хост: ${host_cpus} CPU, ${host_mem_mb} MB | потрібно: ${NODES}×${NODE_CPUS} CPU, ${NODES}×${NODE_MEMORY_MB} MB"
  (( host_cpus >= need_cpus )) || die "Хост має лише $host_cpus CPU, а на ноду потрібно $NODE_CPUS"
  (( host_mem_mb >= need_mem )) || warn "Сумарна RAM нод (${need_mem} MB) більша за доступну рушію (${host_mem_mb} MB) — можливий OOM. Збільште пам'ять Docker Desktop / podman machine."
  if [[ "$ENGINE" == podman ]]; then
    warn "Podman-провайдер у kind/k3d/minikube позначений як experimental — див. README, розділ «Podman»."
  fi
}

# ---------- Обмеження ресурсів контейнерів-нод (для kind і k3d) ----------
# $@ — імена контейнерів
limit_node_containers() {
  local c
  for c in "$@"; do
    if "$ENGINE" update --cpus "$NODE_CPUS" --memory "${NODE_MEMORY_MB}m" --memory-swap "${NODE_MEMORY_MB}m" "$c" >/dev/null; then
      ok "Ліміти ${NODE_CPUS} CPU / ${NODE_MEMORY_MB} MB застосовано до $c"
    else
      warn "Не вдалося застосувати ліміти до $c (rootless/cgroup v1?)"
    fi
  done
}

# ---------- Kubernetes ----------
wait_nodes_ready() {
  log "Чекаю готовності нод..."
  kubectl wait --for=condition=Ready nodes --all --timeout=300s
}

# Жоден із трьох інструментів не дозволяє задати default namespace при створенні кластера,
# тому створюємо його та прописуємо в контекст kubeconfig.
set_default_namespace() {
  local ns="${NAMESPACE:-$DEFAULT_NAMESPACE}"
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl config set-context --current --namespace="$ns" >/dev/null
  ok "Namespace '$ns' створено та встановлено за замовчуванням для контексту $(kubectl config current-context)"
}

show_summary() {
  echo
  log "Контекст: $(kubectl config current-context)"
  kubectl get nodes -o wide
  echo
  log "Фактичні ліміти контейнерів-нод (з боку рушія):"
  "$ENGINE" ps --filter "name=$1" --format '{{.Names}}' | sort | while read -r c; do
    "$ENGINE" inspect "$c" --format "  {{.Name}}  cpus={{.HostConfig.NanoCpus}}  memory={{.HostConfig.Memory}}" \
      | awk '{ split($2,a,"="); split($3,b,"="); printf "  %-40s CPU=%s  RAM=%s MB\n", $1, a[2]/1e9, b[2]/1024/1024 }'
  done
  echo
  ok "Готово. Перевірка: kubectl get pods  (namespace: ${NAMESPACE:-$DEFAULT_NAMESPACE})"
}
