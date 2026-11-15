#!/usr/bin/env bash
set -euo pipefail
umask 077

DOMAIN="${DOMAIN:?DOMAIN is required}"
DIR="state/argocd"
mkdir -p "$DIR"

TRAEFIK_IP="$(kubectl get svc traefik -n traefik -o jsonpath='{.spec.clusterIP}')"
CA_PEM="$(kubectl get secret mesh-ca-public -n traefik -o jsonpath='{.data.tls\.ca}' | base64 -d)"

{
  cat <<EOF
argo-cd:
  global:
    domain: argocd.${DOMAIN}
    hostAliases:
      - ip: "${TRAEFIK_IP}"
        hostnames:
          - "auth.${DOMAIN}"
  configs:
    cm:
      url: https://argocd.${DOMAIN}
      oidc.config: |
        name: Authelia
        issuer: https://auth.${DOMAIN}
        clientID: argocd
        clientSecret: \$oidc.argocd.clientSecret
        requestedScopes:
          - openid
          - profile
          - email
          - groups
        rootCA: |
EOF
  printf '%s\n' "$CA_PEM" | tr -d '\r' | sed '/^$/d; s/^/          /'
} > "$DIR/oidc-values.yml"
