---
---
# AsciiArtify — Proof of Concept: ArgoCD на Kubernetes (k3d)

## Мета PoC

Встановити та налаштувати GitOps-систему **ArgoCD**, готову до реалізації MVP, і забезпечити команді захищений доступ до її графічного інтерфейсу (Web UI) через **Traefik + ForwardAuth + OIDC SSO (Authelia)** з однаковою конфігурацією для локального, `staging` і `prod` середовищ.

| Компонент | Вибір |
|---|---|
| Kubernetes | `k3d` (k3s у Docker, вбудований Traefik вимкнено) |
| PKI / CA | `cert-manager` (`v1.21.3`) + `trust-manager` (`v0.26.0`, `ClusterIssuer: mesh`, `Bundle: mesh-ca-public`) |
| Ingress | `traefik` (`42.1.0`, wildcard TLS `*.localtest.me`, `ForwardAuth`) |
| Автентифікація (IdP) | `authelia` (`0.11.22`, `ForwardAuth` + `OIDC`) |
| GitOps | `argo-cd` (`10.10.3`, локальний `admin` вимкнено, RBAC `admins -> role:admin`) |
| Доступ до Web UI | `https://argocd.localtest.me` |

---

## 1. Передумови

На робочій станції потрібні:
- **Docker Engine/Desktop** (або **Podman** з `ENGINE=podman`)
- **`make`**, **`curl`**, **`openssl`**, **`bash`**

Утиліти `kubectl`, `helm`, `k3d` автоматично завантажуються в `./bin` під час запуску `make` (вимкнути: `AUTO_INSTALL=0`).

Перевірка базових залежностей:

```bash
docker version
make --version
openssl version
```

---

## 2. Створення кластера k3d

```bash
make k3d
```

Скрипт `scripts/k3d.sh` піднімає 3 ноди (1 server + 2 agents, по 2 CPU і 2048 MB RAM), вимикає вбудований Traefik у k3s (`--disable=traefik@server:*`), прокидає порти `80` і `443` на `@loadbalancer` і встановлює namespace `dev` за замовчуванням.

Перевірка стану нод:

```bash
kubectl get nodes -o wide
```

Очікувано: усі 3 вузли (`server-0`, `agent-0`, `agent-1`) у статусі `Ready`.

---

## 3. Розгортання платформи та ArgoCD

У `Makefile` передбачено два контури поверх спільних Helm-чартів (`deploy/platform/*`) і конфігу `deploy/envs/dev-local.yaml`:
- `make dev-local` — локальний цикл розробки **без ArgoCD** (`cert-manager`, `mesh-pki`, `traefik`, `authelia`, `demo`).
- `make dev-gitops` — повний контур **з ArgoCD** (виконує `dev-local`, формує `state/argocd/oidc-values.yml` через `scripts/render-argocd-oidc.sh` і ставить чарт `deploy/platform/argocd`).

Запуск PoC з ArgoCD:

```bash
make dev-gitops
```

Під час виконання автоматично відбувається:
1. Встановлення `cert-manager` і `trust-manager` у namespace `cert-manager`.
2. Створення внутрішнього кореневого CA `mesh-ca`, `ClusterIssuer/mesh` та автоматична синхронізація публічного сертифіката `Secret/mesh-ca-public` (`tls.ca`) у namespace `traefik`, `authelia`, `argocd`.
3. Розгортання `traefik` із wildcard-сертифікатом `*.localtest.me` і глобальним `ForwardAuth` middleware на entrypoint `websecure`.
4. Генерація локальних секретів Authelia та OIDC-клієнта ArgoCD у `state/authelia/` (`scripts/authelia-secrets.sh`) і встановлення `authelia` у namespace `authelia` (внутрішній HTTPS між Traefik і Authelia).
5. Розгортання демонстраційного сервісу `demo` у namespace `demo` (`https://demo.localtest.me`).
6. Генерація `hostAliases` для `auth.localtest.me` і підключення `rootCA` з `mesh-ca-public` (`scripts/render-argocd-oidc.sh`), після чого встановлення `argo-cd` у namespace `argocd` з вимкненим локальним паролем `admin` (`admin.enabled: false`) та увімкненим OIDC SSO.

Перевірка готовності подів і сертифікатів:

```bash
kubectl get pods -n cert-manager -n traefik -n authelia -n argocd
kubectl get certificate -A
```

Усі поди мають бути в статусі `Running` / `Ready`, усі сертифікати — у стані `Ready: True`.

---

## 4. Отримання доступу до Web UI ArgoCD

### 4.1. Отримання облікових даних для першого входу

Під час першого запуску `scripts/authelia-secrets.sh` ідемпотентно створює обліковий запис `admin` (групи `admins`, `dev`) і зберігає пароль локально (поза Git):

```bash
cat state/authelia/admin_password
```

### 4.2. Довіра до локального CA (опціонально для браузера)

Оскільки домен `*.localtest.me` резолвиться на `127.0.0.1` без редагування `/etc/hosts`, адреса одразу відкривається в браузері. Сертифікат виписано внутрішнім `ClusterIssuer: mesh`, тому браузер покаже попередження про невідомий CA.

Щоб прибрати попередження, можна вивантажити публічний сертифікат CA (без приватного ключа) та імпортувати його в довірені кореневі центри браузера/ОС:

```bash
kubectl get secret mesh-ca-public -n traefik -o jsonpath='{.data.tls\.ca}' | base64 -d > state/mesh-ca.crt
```

### 4.3. Покроковий вхід у Web UI

1. Відкрийте в браузері **`https://argocd.localtest.me`**.
2. Traefik `ForwardAuth` перевірить наявність сесії та перенаправить на портал входу **`https://auth.localtest.me`**.
3. Введіть логін `admin` та пароль із `state/authelia/admin_password`.
4. Після успішного входу Authelia поверне вас на `https://argocd.localtest.me`.
5. На сторінці входу ArgoCD натисніть **Log in via Authelia**. Оскільки сесійна cookie на `.localtest.me` вже активна, а для OIDC-клієнта увімкнено `consent_mode: implicit`, вхід відбудеться без повторного введення пароля.
6. Перейдіть у **User Info** (іконка профілю зліва): у полі груп має відображатися `admins`, що через `argocd-rbac-cm` (`g, admins, role:admin`) надає повні права адміністратора.

---

## 5. Доступ для інших учасників команди та перехід до MVP

### Додавання користувачів команди

Користувачі Authelia описуються в `state/authelia/users_database.yml` (формується у `scripts/authelia-secrets.sh`):
- Користувачі в групі `admins` отримують в ArgoCD роль `role:admin`.
- Користувачі без групи `admins` отримують роль за замовчуванням `policy.default: role:readonly`.

Щоб згенерувати `argon2id`-хеш пароля для нового учасника команди:

```bash
docker run --rm --entrypoint authelia ghcr.io/authelia/authelia:4.39.24 \
  crypto hash generate argon2 --password '<пароль_користувача>'
```

### Підключення GitOps для MVP

Маніфести ArgoCD `Application` винесено в чарт `deploy/gitops/` (із підтримкою `sync-wave` та multi-source `valueFiles` із `deploy/envs/`):

```bash
helm template gitops deploy/gitops \
  --set repoURL=https://github.com/<org>/<repo>.git \
  --set env=dev-gitops \
  | kubectl apply -f -
```

Для `staging` і `prod` використовуються ті самі чарти в `deploy/platform/*` з відповідними файлами `deploy/envs/staging.yaml` та `deploy/envs/prod.yaml`, а секрети (`authelia-secrets`, `authelia-users`, `authelia-oidc`, `oidc.argocd.clientSecret`) постачаються через менеджер секретів кластера (External Secrets / Sealed Secrets) замість локальних bash-скриптів.

---

## 6. Результат PoC (чекліст)

- [x] Кластер `k3d` створено (3 ноди `Ready`, порти `80`/`443` прокинуті на Traefik)
- [x] Автоматизовано внутрішній PKI (`cert-manager` + `trust-manager`, `Bundle/mesh-ca-public`)
- [x] Traefik працює з wildcard TLS `*.localtest.me` та `ForwardAuth` на базі Authelia
- [x] ArgoCD розгорнуто у namespace `argocd`, Web UI доступний за `https://argocd.localtest.me`
- [x] Вхід команди працює через OIDC SSO (`Log in via Authelia`), локальний `admin` вимкнено, RBAC налаштовано (`admins -> role:admin`)
- [x] Підготовлено 1:1 контури `dev-local`, `dev-gitops`, `staging`, `prod` і шаблон `deploy/gitops` для запуску MVP

---

## Очищення середовища

```bash
make delete-k3d
```
