#!/usr/bin/env bash
# Ідемпотентна генерація секретів Authelia у state/authelia/ та K8s Secrets.
set -euo pipefail
umask 077

ROOT=$(cd "$(dirname "$0")/.." && pwd)
# Підключаємо detect_engine (docker | podman) та логування
# shellcheck source=scripts/common.sh
source "$ROOT/scripts/common.sh"

DIR="$ROOT/state/authelia"
AUTHELIA_NS="${AUTHELIA_NAMESPACE:-authelia}"
DOMAIN="${DOMAIN:-localtest.me}"
AUTHELIA_IMAGE="${AUTHELIA_IMAGE:-ghcr.io/authelia/authelia:4.39.24}"
AUTHELIA_USERS="${AUTHELIA_USERS:-admin dev qa pm user}"

mkdir -p "$DIR"
chmod 700 "$DIR"

gen_hex() { # gen_hex <file> <bytes>
  [ -s "$DIR/$1" ] || openssl rand -hex "$2" | tr -d '\r\n' > "$DIR/$1"
}

gen_hex session_secret 32
gen_hex storage_key 32
gen_hex reset_jwt 32
gen_hex oidc_hmac 32
gen_hex argocd_client_secret 24

if [ ! -s "$DIR/jwks.pem" ]; then
  openssl genrsa -out "$DIR/jwks.pem" 2048
fi

if [ ! -s "$DIR/argocd_client_secret_hash" ]; then
  "$ENGINE" run --rm --entrypoint authelia "$AUTHELIA_IMAGE" \
    crypto hash generate pbkdf2 --password "$(cat "$DIR/argocd_client_secret")" \
    | grep -oE '\$pbkdf2[^[:space:]]+' | head -n1 | tr -d '\r\n' > "$DIR/argocd_client_secret_hash"
fi

user_displayname() {
  case "$1" in
    admin) echo "Dev Administrator" ;;
    dev)   echo "Developer" ;;
    qa)    echo "QA Engineer" ;;
    pm)    echo "Product Manager" ;;
    *)     echo "$1" ;;
  esac
}
user_groups() {
  case "$1" in
    admin) echo "admins dev" ;;
    *)     echo "$1" ;;
  esac
}
printf 'users:\n' > "$DIR/users_database.yml"
for user in $AUTHELIA_USERS; do
  if [ ! -s "$DIR/${user}_password" ]; then
    openssl rand -hex 18 | tr -d '\r\n' > "$DIR/${user}_password"
  fi
  if [ ! -s "$DIR/${user}_password_hash" ]; then
    hash=$("$ENGINE" run --rm --entrypoint authelia "$AUTHELIA_IMAGE" \
      crypto hash generate argon2 --password "$(cat "$DIR/${user}_password")" \
      | grep -oE '\$argon2id\$[^[:space:]]+' | head -n1)
    [ -n "$hash" ] || die "authelia-secrets: не вдалося згенерувати argon2id-хеш для $user"
    printf '%s' "$hash" > "$DIR/${user}_password_hash"
  fi
  {
    printf '  %s:\n' "$user"
    printf '    displayname: "%s"\n' "$(user_displayname "$user")"
    printf '    password: "%s"\n' "$(cat "$DIR/${user}_password_hash")"
    printf '    email: "%s@%s"\n' "$user" "$DOMAIN"
    printf '    groups:\n'
    for grp in $(user_groups "$user"); do
      printf '      - %s\n' "$grp"
    done
  } >> "$DIR/users_database.yml"
done

cat > "$DIR/server-tls.yml" <<'EOF'
server:
  tls:
    key: /secrets/tls/tls.key
    certificate: /secrets/tls/tls.crt
EOF

chmod 600 "$DIR"/*

kubectl create namespace "$AUTHELIA_NS" --dry-run=client -o yaml | kubectl apply -f -

INTERNAL_ARGS=(
  --from-file=identity_validation.reset_password.jwt.hmac.key="$DIR/reset_jwt"
  --from-file=identity_providers.oidc.hmac.key="$DIR/oidc_hmac"
  --from-file=session.encryption.key="$DIR/session_secret"
  --from-file=storage.encryption.key="$DIR/storage_key"
)
kubectl -n "$AUTHELIA_NS" create secret generic authelia-secrets \
  "${INTERNAL_ARGS[@]}" --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "$AUTHELIA_NS" create secret generic authelia-users \
  --from-file=users_database.yml="$DIR/users_database.yml" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "$AUTHELIA_NS" create secret generic authelia-server-tls \
  --from-file=server-tls.yml="$DIR/server-tls.yml" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "$AUTHELIA_NS" create secret generic authelia-oidc \
  --from-file=jwks.pem="$DIR/jwks.pem" \
  --from-file=argocd_client_secret_hash="$DIR/argocd_client_secret_hash" \
  --dry-run=client -o yaml | kubectl apply -f -

ok "authelia-secrets: готово (користувачі: $AUTHELIA_USERS, паролі у $DIR/*_password)"
