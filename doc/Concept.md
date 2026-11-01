# AsciiArtify: порівняння minikube, kind та k3d для локальної розробки на Kubernetes

> Звіт підготовлено для вибору інструменту під PoC. Дата: листопад 2026.
> Поряд зі звітом — `Makefile` і скрипти в `scripts/`, які піднімають однаковий
> тестовий кластер кожним із трьох інструментів для особистої перевірки.

---

## 1. Вступ

AsciiArtify зберігає код у GitHub і планує розгортати продукт у Kubernetes. Для розробки
та PoC потрібен **локальний** кластер, який швидко створюється, легко видаляється і максимально
схожий на «справжній» Kubernetes. Розглянуто три інструменти:

[![Watch the video](https://img.youtube.com/vi/T-D1KVIuvjA/maxresdefault.jpg)](https://youtu.be/T-D1KVIuvjA)

| Інструмент | Що це | Хто розвиває | Ліцензія |
|---|---|---|---|
| **minikube** | Локальний Kubernetes у VM або контейнері; орієнтований на розробника, має addons і dashboard | Kubernetes SIG Cluster Lifecycle | Apache 2.0 |
| **kind** (Kubernetes IN Docker) | Кожна нода — контейнер з kubeadm-кластером; створений для тестування самого Kubernetes і CI | Kubernetes SIG Testing | Apache 2.0 |
| **k3d** | Обгортка, що запускає **k3s** (полегшений сертифікований дистрибутив від Rancher/SUSE) у контейнерах | Спільнота k3d-io (ініційовано Rancher) | MIT (k3d), Apache 2.0 (k3s) |

> Уточнення до вихідного опису: k3d використовує не RKE, а **k3s** — окремий легкий
> дистрибутив Kubernetes від Rancher. RKE/RKE2 — інші продукти, для повноцінних серверних кластерів.

---

## 2. Характеристики

| Характеристика | minikube | kind | k3d |
|---|---|---|---|
| **ОС хоста** | Linux, macOS, Windows | Linux, macOS, Windows | Linux, macOS, Windows (через Docker Desktop/WSL2) |
| **Архітектури** | amd64, arm64 (також ppc64le, s390x для частини драйверів) | amd64, arm64 | amd64, arm64 (і armv7 для k3s) |
| **Середовище запуску нод** | Драйвери: docker, podman, VirtualBox, Hyper-V, KVM2, QEMU, vfkit, bare-metal (`none`) | Контейнери docker / podman / nerdctl | Контейнери docker (podman через Docker API-сокет) |
| **Дистрибутив K8s** | Upstream (kubeadm) | Upstream (kubeadm), проходить conformance | k3s (CNCF-сертифікований, урізаний: SQLite/etcd, без in-tree хмарних провайдерів) |
| **Мультинодовість** | Так (`--nodes`) | Так (YAML-конфіг, у т.ч. HA control-plane) | Так (`--servers`, `--agents`), HA на embedded etcd |
| **Ліміти CPU/RAM на ноду** | Нативно: `--cpus`, `--memory` (на кожну ноду) | Немає параметрів — тільки `docker update` по контейнеру | RAM нативно (`--servers-memory/--agents-memory`), CPU — через `docker update` |
| **Автоматизація / IaC** | CLI-прапорці, профілі, `minikube config` | Декларативний YAML-конфіг, ідеальний для CI (GitHub Actions) | Декларативний YAML-конфіг (`k3d cluster create --config`), CLI |
| **Ingress / LoadBalancer** | addon `ingress`, `minikube tunnel` | Встановлюється вручну (ingress-nginx, MetalLB/cloud-provider-kind) | Вбудовані Traefik і ServiceLB, проброс портів через loadbalancer-контейнер |
| **Локальний registry / образи** | addon `registry`, `minikube image load` | `kind load docker-image` | `--registry-create`, `k3d image import` |
| **Моніторинг і керування** | `minikube dashboard`, addon `metrics-server`, багато інших addons | Немає вбудованого; ставиться як у звичайний кластер | metrics-server у k3s за замовчуванням; dashboard/Prometheus — вручну або Helm (k3s HelmChart CRD) |
| **Ресурсомісткість** | Найвища (особливо з VM-драйвером) | Середня | Найнижча (k3s ≈ 512 МБ на сервер) |
| **Типовий час створення 3-нодового кластера** | ~2–4 хв | ~1–2 хв | ~30–60 с |

*Час — орієнтовні значення на сучасному ноутбуці з уже завантаженими образами; перевірте на своєму обладнанні через `make`.*

---

## 3. Переваги та недоліки

### minikube
**Переваги**
- Найпростіший старт для новачка, найкраща документація й туторіали.
- Багатий набір addons (dashboard, ingress, metrics-server, registry), `minikube service` відкриває сервіс у браузері.
- Гнучкі драйвери: може працювати взагалі без Docker (VM-драйвери) — це пряма відповідь на ризик ліцензування Docker Desktop.
- Нативні ліміти CPU/RAM на ноду.

**Недоліки**
- Найповільніший і найважчий; мультинодовий режим історично менш стабільний, ніж одновузловий.
- Більше «магії» (addons, tunnel), яка відрізняється від продакшн-кластера.
- Масштабування обмежене ресурсами одного комп'ютера (стосується всіх трьох інструментів).

### kind
**Переваги**
- Upstream Kubernetes, яким тестують сам Kubernetes → максимальна відповідність продакшну.
- Швидкий, декларативний конфіг, де-факто стандарт для CI (GitHub Actions — актуально, бо код у GitHub).
- Легко піднімати кластери з різними версіями K8s (через `node image`).

**Недоліки**
- Немає ingress/LoadBalancer «з коробки», немає dashboard — більше ручної роботи.
- Немає параметрів ресурсів на ноду; kubelet бачить ресурси всього хоста.
- Кластер не переживає перезапуск Docker так само надійно, як minikube/k3d (орієнтований на «одноразові» кластери).

### k3d
**Переваги**
- Найшвидший і найлегший; 3-нодовий кластер за секунди, мінімальне споживання RAM.
- «Батарейки в комплекті»: Traefik ingress, ServiceLB, local-path storage, локальний registry.
- Зручно стартувати/зупиняти кластери (`k3d cluster stop/start`), декларативний конфіг.
- k3s — сертифікований Kubernetes, який також використовується на edge/IoT і у невеликих продакшн-середовищах.

**Недоліки**
- k3s ≠ upstream: інші дефолти (Traefik замість ingress-nginx, SQLite замість etcd, урізані компоненти) — можливі розбіжності з цільовим продакшн-кластером.
- Менша спільнота й документація, ніж у minikube/kind.
- Podman — лише через Docker-сумісний сокет, з обмеженнями в rootless-режимі.

### Зведена оцінка (1 — гірше, 5 — краще)

| Критерій | minikube | kind | k3d |
|---|:-:|:-:|:-:|
| Легкість використання | 5 | 4 | 4 |
| Швидкість розгортання | 2 | 4 | 5 |
| Споживання ресурсів | 2 | 3 | 5 |
| Близькість до upstream/продакшну | 4 | 5 | 3 |
| Вбудовані додаткові функції | 5 | 2 | 4 |
| Документація та спільнота | 5 | 4 | 3 |
| Придатність для CI | 3 | 5 | 4 |
| Незалежність від Docker Desktop | 5 | 4 | 3 |

---

## 4. Ризики ліцензування Docker і альтернатива Podman

### Що саме платне
- **Docker Engine** (dockerd, CLI, Compose, BuildKit) — open source під Apache 2.0, безкоштовний, у т.ч. для комерції. На Linux-машинах розробників і в CI ризику немає.
- **Docker Desktop** (GUI-застосунок для macOS/Windows/Linux з VM) — безкоштовний лише для особистого використання, освіти, некомерційного open source та **малого бізнесу: менше 250 працівників І менше $10 млн річного доходу**. Інакше потрібна платна підписка Pro / Team / Business (орієнтовно $9 / $15 / $24 за користувача на місяць при оплаті за рік). Обидва пороги діють незалежно: достатньо перевищити один.

### Що це означає для AsciiArtify
- Як стартап, AsciiArtify, найімовірніше, зараз у безкоштовній зоні. Ризик відкладений: після раунду інвестицій/зростання команди поріг доходу або чисельності може бути перетнутий, і використання Desktop без підписки порушуватиме умови договору (включно з правом Docker на аудит).
- Заходи: зафіксувати в інженерних правилах, що інструменти не прив'язані до Docker Desktop; на Linux використовувати Docker Engine; на macOS/Windows мати перевірену альтернативу.

### Альтернативи Docker Desktop
| Альтернатива | Ліцензія | Примітки |
|---|---|---|
| **Podman + Podman Desktop** | Apache 2.0 | Daemonless, rootless за замовчуванням, Docker-сумісний CLI і API-сокет |
| Docker Engine у WSL2 / Linux | Apache 2.0 | Без GUI, але повністю безкоштовний |
| Colima (macOS) | MIT | Легка VM з Docker або containerd |
| Rancher Desktop | Apache 2.0 | Включає k3s, вибір dockerd або containerd |

### Підтримка Podman трьома інструментами
| | minikube | kind | k3d |
|---|---|---|---|
| Як увімкнути | `--driver=podman` (рекомендовано `--container-runtime=containerd`) | `KIND_EXPERIMENTAL_PROVIDER=podman` | `DOCKER_HOST=unix://<podman.sock>` |
| Статус | Experimental | Experimental, але тестується в CI проєкту (rootful і rootless) | Неофіційно/experimental, rootless має обмеження |
| Вимоги | Podman у rootful або налаштований rootless | cgroup v2, `Delegate=yes` для rootless | Увімкнений `podman.socket` |

Скрипти цього репозиторію підтримують Podman прапорцем `ENGINE=podman` (`make kind ENGINE=podman`).

**Висновок щодо Podman:** для PoC Podman придатний, але очікуйте більше дрібних проблем, ніж з Docker. Найзріліша комбінація — **kind + Podman**; найменш «бойова» — k3d + Podman.

---

## 5. Тестові кластери: як запустити

Усі варіанти: **3 ноди × 2 CPU × 2 GB RAM**, ноди — контейнери Docker (або Podman), namespace за замовчуванням — **`dev`**.

```bash
make help            # список команд
make minikube        # minikube, driver docker, 3 ноди
make kind            # kind: 1 control-plane + 2 workers
make k3s             # k3d (k3s у Docker): 1 server + 2 agents   (alias: make k3d)

make demo-k3s        # Hello World у кластері (demo-minikube | demo-kind | demo-k3s)
make status          # стан усіх кластерів
make delete-kind     # видалити один кластер
make clean           # видалити всі
make lint            # bash -n + shellcheck
```

Перевизначення параметрів: `make kind NODES=3 NODE_CPUS=2 NODE_MEMORY_MB=2048 NAMESPACE=dev ENGINE=podman`.

Відсутні `kubectl`, `kind`, `k3d`, `minikube` автоматично завантажуються в `./bin` (вимкнути: `AUTO_INSTALL=0`).

### Вимоги до хоста
- Docker Engine/Desktop або Podman, `make`, `curl`, `bash` (Linux, macOS; Windows — через WSL2).
- Щонайменше **2 ядра** (ліміт CPU на ноду не може перевищувати кількість ядер хоста) і **~8 GB RAM**, виділених Docker/Podman: 3 × 2 GB для нод + запас. У Docker Desktop: *Settings → Resources*; у Podman: `podman machine set --cpus 4 --memory 8192`.
- Ліміти CPU — це квота, а не резервування: три ноди по 2 CPU на 4-ядерному хості працюватимуть, ділячи ядра.

### Як кожен інструмент реалізує вимоги

| Вимога | minikube | kind | k3d |
|---|---|---|---|
| 3 ноди | `--nodes 3` | конфіг: 1 control-plane + 2 worker | `--servers 1 --agents 2` |
| 2 CPU на ноду | `--cpus 2` (нативно) | `docker update --cpus 2` після створення | `docker update --cpus 2` після створення |
| 2 GB на ноду | `--memory 2048mb` (нативно) | `docker update --memory 2g` після створення | `--servers-memory/--agents-memory 2048m` (нативно) |
| Namespace `dev` | після створення | після створення | після створення |

**Namespace за замовчуванням.** Жоден з трьох інструментів не дозволяє задати default namespace під час створення кластера. Тому скрипти одразу після створення виконують:

```bash
kubectl create namespace dev
kubectl config set-context --current --namespace=dev
```

**Нюанс kind.** Після `docker update` контейнер справді обмежений cgroup-ом, але kubelet усередині бачить CPU/RAM усього хоста (`kubectl describe node`). Для планувальника це означає, що він «думає», ніби ресурсів більше. Для PoC це прийнятно; minikube і k3d показують ліміт коректніше.

### Структура
```
.
├── Makefile
├── README.md
└── scripts/
    ├── common.sh     # параметри, preflight, встановлення утиліт, ліміти, namespace
    ├── minikube.sh   # up | down | status
    ├── kind.sh       # up | down | status
    ├── k3s.sh        # up | down | status   (k3d)
    └── demo.sh       # Hello World: deploy | delete
```

---

## 6. Демонстрація: k3d + «Hello World»

Рекомендований для PoC інструмент — **k3d** (обґрунтування у розділі 7).

### Крок 1. Створити кластер
```bash
$ make k3s
==> Рушій: docker | хост: 8 CPU, 15890 MB | потрібно: 3×2 CPU, 3×2048 MB
==> Створюю k3d-кластер 'asciiartify-k3d' (1 server + 2 agents, рушій docker)
...
 ✔  Ліміти 2 CPU / 2048 MB застосовано до k3d-asciiartify-k3d-server-0
 ✔  Ліміти 2 CPU / 2048 MB застосовано до k3d-asciiartify-k3d-agent-0
 ✔  Ліміти 2 CPU / 2048 MB застосовано до k3d-asciiartify-k3d-agent-1
 ✔  Namespace 'dev' створено та встановлено за замовчуванням для контексту k3d-asciiartify-k3d
```

### Крок 2. Перевірити кластер
```bash
$ kubectl get nodes
NAME                           STATUS   ROLES                  AGE   VERSION
k3d-asciiartify-k3d-server-0   Ready    control-plane,master   40s   v1.xx.x+k3s1
k3d-asciiartify-k3d-agent-0    Ready    <none>                 35s   v1.xx.x+k3s1
k3d-asciiartify-k3d-agent-1    Ready    <none>                 35s   v1.xx.x+k3s1

$ kubectl config view --minify -o jsonpath='{..namespace}'
dev
```

### Крок 3. Розгорнути Hello World
```bash
$ make demo-k3s
==> Розгортаю hello-world у k3d-asciiartify-k3d / namespace dev
deployment.apps/hello-world created
service/hello-world created
deployment "hello-world" successfully rolled out
NAME                          READY   STATUS    NODE
hello-world-xxxxxxxxxx-aaaaa  1/1     Running   k3d-asciiartify-k3d-server-0
hello-world-xxxxxxxxxx-bbbbb  1/1     Running   k3d-asciiartify-k3d-agent-0
hello-world-xxxxxxxxxx-ccccc  1/1     Running   k3d-asciiartify-k3d-agent-1
==> Port-forward localhost:8088 → svc/hello-world:80
 ✔  Відповідь сервісу: Hello World from AsciiArtify!
```

Демо створює `Deployment` з 3 репліками образу `hashicorp/http-echo` (multi-arch) з `topologySpreadConstraints`, щоб репліки рознеслися по різних нодах, і `Service` типу ClusterIP. Той самий маніфест працює в усіх трьох кластерах (`make demo-kind`, `make demo-minikube`).

Аналогічно вручну:
```bash
kubectl create deployment hello-world --image=hashicorp/http-echo:1.0 --replicas=3 -- /http-echo -text="Hello World"
kubectl expose deployment hello-world --port=80 --target-port=5678
kubectl port-forward svc/hello-world 8088:80 &
curl localhost:8088
```

### Крок 4. Прибрати
```bash
make delete-k3s
```

---

## 7. Висновки та рекомендації

**Для PoC AsciiArtify рекомендовано k3d.** Він найшвидше створює мультинодовий кластер, найменше навантажує ноутбуки розробників, має готові ingress (Traefik), LoadBalancer і локальний registry — отже, команда швидше переходить від «підняти кластер» до перевірки самого продукту. Для стадії PoC це головне.

| Інструмент | Роль у проєкті |
|---|---|
| **k3d** | Основний інструмент для PoC і щоденної локальної розробки |
| **kind** | CI у GitHub Actions (інтеграційні та e2e-тести) і перевірка на upstream Kubernetes перед продакшном |
| **minikube** | Онбординг/навчання; резервний варіант для macOS/Windows без Docker Desktop (VM-драйвери) або коли потрібні addons/dashboard |

**Ризики та як їх закрити**
1. *Розбіжність k3s з продакшном.* Не покладатися на специфіку k3s (Traefik CRD, local-path) у маніфестах; продакшн-маніфести/Helm-чарти проганяти в kind у CI.
2. *Ліцензування Docker Desktop.* Зараз стартап, найімовірніше, у безкоштовній зоні, але при зростанні понад 250 людей або $10 млн доходу знадобиться підписка. Заздалегідь перевірити робочий процес на Podman Desktop / Colima / Rancher Desktop; на Linux і в CI використовувати безкоштовний Docker Engine.
3. *Обмеження масштабування.* Будь-який з інструментів обмежений ресурсами однієї машини — це інструменти розробки, а не платформа для навантажувального тестування. Для тестів масштабування після PoC — керований кластер (EKS/GKE/AKS) або окремий k3s/RKE2-кластер.

**Наступні кроки**
1. Кожному розробнику виконати `make k3s && make demo-k3s` і порівняти з `make kind` / `make minikube` на своєму залізі.
2. Додати в GitHub Actions job з `kind` для e2e-тестів.
3. Прогнати ті самі сценарії з `ENGINE=podman` на macOS-машині, щоб мати план Б без Docker Desktop.

---

### Джерела
- minikube: https://minikube.sigs.k8s.io/docs/
- kind: https://kind.sigs.k8s.io/ (rootless/Podman: https://kind.sigs.k8s.io/docs/user/rootless/)
- k3d: https://k3d.io/ (`k3d cluster create`: https://k3d.io/stable/usage/commands/k3d_cluster_create/)
- k3s: https://docs.k3s.io/
- Docker Desktop license: https://docs.docker.com/subscription/desktop-license/ , FAQ: https://www.docker.com/pricing/faq/
- Podman: https://podman.io/
