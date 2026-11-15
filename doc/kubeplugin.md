# Плагін `kubectl kubeplugin`

Скрипт [`scripts/kubeplugin`](../scripts/kubeplugin) — це плагін для `kubectl`, який отримує метрики використання CPU та пам'яті з Kubernetes (`kubectl top`) і виводить їх у структурованому текстовому форматі:

```text
Resource, Namespace, Name, CPU, Memory
```

## Передумови

- `bash` (версія 4.0+)
- `kubectl` у `PATH`
- Налаштований доступ до кластера Kubernetes з запущеним **metrics-server**

Перевірити роботу `metrics-server` можна командою:

```bash
kubectl top nodes
```

## Встановлення як плагін `kubectl`

`kubectl` автоматично розпізнає будь-який виконуваний файл у `$PATH` з префіксом `kubectl-`. Щоб підключити скрипт як плагін `kubectl kubeplugin`:

1. Переконайтеся, що скрипт має права на виконання:

   ```bash
   chmod +x scripts/kubeplugin
   ```

2. Створіть символічне посилання (або скопіюйте файл) з назвою `kubectl-kubeplugin` у каталог із `$PATH`, наприклад `~/.local/bin` або `/usr/local/bin`:

   ```bash
   mkdir -p ~/.local/bin
   ln -sf "$(pwd)/scripts/kubeplugin" ~/.local/bin/kubectl-kubeplugin
   ```

   Якщо `~/.local/bin` відсутній у `$PATH`, додайте його до профілю оболонки (`~/.bashrc` або `~/.zshrc`):

   ```bash
   export PATH="$HOME/.local/bin:$PATH"
   ```

3. Перевірте, що `kubectl` бачить плагін:

   ```bash
   kubectl plugin list
   ```

   Очікуваний вивід міститиме шлях до `kubectl-kubeplugin`.

## Синтаксис та параметри

```text
kubectl kubeplugin [RESOURCE] [NAMESPACE] [OPTIONS]
```

За сумісністю також підтримується префікс `top` (наприклад, `kubectl kubeplugin top pods -n kube-system`).

### Позиційні аргументи

| Аргумент | Опис | За замовчуванням |
|---|---|---|
| `RESOURCE` | Тип ресурсу: `pods` (`pod`, `po`) або `nodes` (`node`, `no`) | `pods` |
| `NAMESPACE` | Namespace для ресурсу `pods` (якщо не задано `-n` або `-A`) | namespace поточного контексту (`default`, якщо не вказано) |

### Прапорці

| Прапорець | Опис |
|---|---|
| `-n`, `--namespace <ns>` | Вказати namespace для `pods` |
| `-A`, `--all-namespaces` | Вивести метрики подів з усіх namespace |
| `-l`, `--selector <query>` | Фільтрація за label selector |
| `--sort-by <cpu\|memory>` | Сортування результатів за `cpu` або `memory` |
| `--context <name>` | Контекст `kubeconfig`, який потрібно використати |
| `--no-header` | Не виводити рядок заголовка `Resource, Namespace, Name, CPU, Memory` |
| `-h`, `--help` | Показати довідку |

> Для ресурсу `nodes` (cluster-scoped) поле `Namespace` у виводі має значення `-`, а прапорці `-n` / `-A` ігноруються з попередженням у `stderr`.

## Приклади використання

### Статистика подів у namespace `kube-system`

```bash
kubectl kubeplugin pods -n kube-system
```

Або позиційним аргументом:

```bash
kubectl kubeplugin pods kube-system
```

Приклад реального виводу з кластера `k3d-module-4-task-1-k3d`:

```text
Resource, Namespace, Name, CPU, Memory
pod, kube-system, coredns-8db54c48d-b4ztb, 3m, 14Mi
pod, kube-system, local-path-provisioner-5d9d9885bc-qgqsq, 1m, 8Mi
pod, kube-system, metrics-server-786d997795-c45qv, 4m, 24Mi
pod, kube-system, svclb-traefik-6e630ebd-2cm52, 0m, 0Mi
pod, kube-system, svclb-traefik-6e630ebd-c9j26, 0m, 0Mi
pod, kube-system, svclb-traefik-6e630ebd-x45hj, 0m, 0Mi
```

### Поди в усіх namespace із сортуванням за пам'яттю

```bash
kubectl kubeplugin pods -A --sort-by=memory
```

### Статистика вузлів кластера

```bash
kubectl kubeplugin nodes
```

Приклад виводу:

```text
Resource, Namespace, Name, CPU, Memory
node, -, k3d-module-4-task-1-k3d-agent-0, 23m, 396Mi
node, -, k3d-module-4-task-1-k3d-agent-1, 30m, 343Mi
node, -, k3d-module-4-task-1-k3d-server-0, 84m, 1003Mi
```

### Фільтрація за мітками без заголовка

```bash
kubectl kubeplugin pods -n kube-system -l k8s-app=kube-dns --no-header
```

### Прямий запуск без встановлення як плагіна

```bash
./scripts/kubeplugin pods -n kube-system
```
