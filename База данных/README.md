# База данных GigaChat

Всё, что нужно для развёртывания PostgreSQL под проект — в одной папке.

## Содержимое

| Файл | Что это |
|---|---|
| **[`init-db.sql`](init-db.sql)** | ⚡ **Главный файл** — одним прогоном собирает ВСЮ БД проекта (19 таблиц + 2 расширения + сид-данные) |
| [`PostgreSQL-Guide.md`](PostgreSQL-Guide.md) | Полный гайд: установка Postgres, pgvector, доступ из LAN, частые запросы, бэкап/восстановление |
| [`OrgAppeal-Setup.md`](OrgAppeal-Setup.md) | Детально про таблицы алгоритма «Организация обращения» + 10 тест-сценариев |

---

## Быстрый старт: вся БД одним файлом

`init-db.sql` создаёт всё что нужно проекту:

**Расширения:** `pgcrypto`, `vector` (pgvector)

**Таблицы (19):**
| Кто использует | Таблицы |
|---|---|
| RAG-агент | `documents` (vector(1024) + ivfflat-индекс) |
| Чат-агенты | `chat_memory`, `chat_summaries` |
| SSO (общая auth) | `auth_users`, `auth_sessions` |
| Cross-device sessions | `agent_sessions` |
| Агент «Меры информационной безопасности» | `kb_norms`, `kb_violations`, `kb_requirements`, `kb_risks`, `kb_measures`, `kb_violation_requirement`, `kb_violation_risk`, `kb_violation_measure`, `kb_cases`, `compliance_incidents` (+ сид: 10 мер, 4 нарушения, связи, 1 кейс) |
| Алгоритм «Организация обращения» | `appeal_employees`, `appeal_event1`, `appeal_event2` (+ тест-данные: 58 + 40 + 28) |

---

## Сценарий 1: офис — Windows-ПК + PostgreSQL на Linux-сервере по SSH

> Полный пошаговый рецепт. Подставь свои значения: **`130.100.X.X`** = IP сервера, **`7022`** = SSH-порт, **`postgres`** = SSH-юзер.
> Если у тебя другие — замени в командах.

### Шаг 0 — открыть PowerShell на Windows-ПК

Нажми `Win` → набери `powershell` → Enter. Откроется синее окно PowerShell.

### Шаг 1 — перейти в папку с проектом

```powershell
cd C:\Users\Lenovo\Desktop\GigaChat
```

Проверь, что файл на месте:

```powershell
dir "База данных\init-db.sql"
```

Должно вывести строку с размером файла (~25 КБ).

### Шаг 2 — скопировать `init-db.sql` на сервер

```powershell
scp -P 7022 "База данных\init-db.sql" postgres@130.100.X.X:~/
```

PowerShell спросит пароль SSH-юзера `postgres`. Введи — символы не отображаются (это нормально), Enter.

Ожидаемый вывод:

```
init-db.sql                                   100%   16KB   320.5KB/s   00:00
```

### Шаг 3 — подключиться к серверу по SSH

```powershell
ssh postgres@130.100.X.X -p 7022
```

Снова пароль (тот же что в шаге 2). После ввода окажешься в shell сервера — приглашение сменится на что-то вроде `postgres@server:~$`.

### Шаг 4 — на сервере: удалить старую БД

```bash
psql -U postgres -c "DROP DATABASE IF EXISTS ai_agent;"
```

Если БД ещё не существует — выведет `NOTICE: database "ai_agent" does not exist, skipping`. Это норма.
Если существует и пустая — выведет `DROP DATABASE`.

> ⚠️ После DROP вся история чатов агентов и документы RAG будут безвозвратно удалены. Если в `ai_agent` есть боевые данные — сначала бэкап (`pg_dump`, см. [`PostgreSQL-Guide.md`](PostgreSQL-Guide.md)).

### Шаг 5 — на сервере: создать пустую БД

```bash
psql -U postgres -c "CREATE DATABASE ai_agent;"
```

Ожидаемый вывод:

```
CREATE DATABASE
```

### Шаг 6 — на сервере: накатить весь SQL

```bash
psql -U postgres -d ai_agent -f ~/init-db.sql
```

Это создаст все 19 таблиц + расширения + сид-данные. Будет много строк вида `CREATE EXTENSION`, `CREATE TABLE`, `CREATE INDEX`, `INSERT 0 N`, etc. Финал должен показать таблицу со списком 19 таблиц (`\dt`) и список расширений (`\dx`).

### Шаг 7 — на сервере: проверить результат

```bash
psql -U postgres -d ai_agent -c "\dt"
```

Должны быть видны 19 таблиц:

```
                   List of relations
 Schema |           Name           | Type  |  Owner
--------+--------------------------+-------+----------
 public | agent_sessions           | table | postgres
 public | appeal_employees         | table | postgres
 public | appeal_event1            | table | postgres
 public | appeal_event2            | table | postgres
 public | auth_sessions            | table | postgres
 public | auth_users               | table | postgres
 public | chat_memory              | table | postgres
 public | chat_summaries           | table | postgres
 public | compliance_incidents     | table | postgres
 public | documents                | table | postgres
 public | kb_cases                 | table | postgres
 public | kb_measures              | table | postgres
 public | kb_norms                 | table | postgres
 public | kb_requirements          | table | postgres
 public | kb_risks                 | table | postgres
 public | kb_violation_measure     | table | postgres
 public | kb_violation_requirement | table | postgres
 public | kb_violation_risk        | table | postgres
 public | kb_violations            | table | postgres
(19 rows)
```

И проверь, что сид-данные залились:

```bash
psql -U postgres -d ai_agent -c "SELECT count(*) FROM kb_measures; SELECT count(*) FROM appeal_employees;"
```

Должно быть `10` (компенсирующие меры) и `58` (сотрудники для алгоритма обращений).

### Шаг 8 — удалить временный файл с сервера (опционально)

```bash
rm ~/init-db.sql
```

### Шаг 9 — выйти из SSH

```bash
exit
```

PowerShell вернётся к локальному приглашению `PS C:\Users\Lenovo\Desktop\GigaChat>`.

### Готово ✅

Дальше — импорт workflow в n8n (см. [`../Import-Workflows-Guide.md`](../Import-Workflows-Guide.md)) и проверка агентов через дашборд.

---

## Сценарий 2: PostgreSQL в Docker (как у нас на dev-машине)

**Шаг 1 — снести контейнер и его volume:**

```powershell
docker stop postgres
docker rm postgres
$vol = docker inspect postgres --format '{{(index .Mounts 0).Name}}' 2>$null
if ($vol) { docker volume rm $vol }
```

**Шаг 2 — поднять контейнер с pgvector:**

```powershell
docker run -d --name postgres --network n8n-net --restart unless-stopped `
  -e POSTGRES_USER=admin -e POSTGRES_PASSWORD=admin123 -e POSTGRES_DB=testdb `
  -p 5432:5432 pgvector/pgvector:pg16
```

**Шаг 3 — подождать готовности (5 сек) и накатить:**

```powershell
docker exec -i postgres psql -U admin -d testdb -v ON_ERROR_STOP=1 < "База данных/init-db.sql"
```

> ⚡ Используй именно образ **`pgvector/pgvector:pg16`** — стандартный `postgres:16`
> НЕ содержит расширения `vector`, и `init-db.sql` упадёт на `CREATE EXTENSION vector`.

---

## Сценарий 3: PostgreSQL на Windows (обычная установка)

```powershell
# 1. Сначала установи pgvector (см. PostgreSQL-Guide.md раздел 2)

# 2. Пересоздать БД и накатить
psql -U postgres -c "DROP DATABASE IF EXISTS ai_agent;"
psql -U postgres -c "CREATE DATABASE ai_agent;"
psql -U postgres -d ai_agent -f "База данных/init-db.sql"
```

---

## Проверка результата

После прогона `init-db.sql` должна вывестись таблица:

```
                   List of relations
 Schema |           Name           | Type
--------+--------------------------+-------
 public | agent_sessions           | table
 public | appeal_employees         | table
 public | appeal_event1            | table
 public | appeal_event2            | table
 public | auth_sessions            | table
 public | auth_users               | table
 public | chat_memory              | table
 public | chat_summaries           | table
 public | compliance_incidents     | table
 public | documents                | table
 public | kb_cases                 | table
 public | kb_measures              | table
 public | kb_norms                 | table
 public | kb_requirements          | table
 public | kb_risks                 | table
 public | kb_violation_measure     | table
 public | kb_violation_requirement | table
 public | kb_violation_risk        | table
 public | kb_violations            | table
(19 rows)
```

И расширения:

```
   Name   | Version
----------+---------
 pgcrypto | 1.3
 plpgsql  | 1.0
 vector   | 0.8.x
```

---

## Дальше

1. **Импортировать workflow в n8n** — см. [`../Import-Workflows-Guide.md`](../Import-Workflows-Guide.md). Postgres-credential должен указывать на ту БД, в которую мы только что накатили.
2. **Запустить агентов** — открой [`../GigaChat-Platform.html`](../GigaChat-Platform.html). Регистрация через login.html, агент «Меры информационной безопасности» (база знаний `kb_*` + сид), прогон 10 кейсов алгоритма обращений из [`../Tests/OrgAppeal/`](../Tests/OrgAppeal/) — всё должно работать сразу.

## Что если что-то сломалось

- **`CREATE EXTENSION vector` упал** — pgvector не установлен. См. [`PostgreSQL-Guide.md`](PostgreSQL-Guide.md) раздел 2, или используй Docker-образ `pgvector/pgvector:pg16`.
- **`role "postgres" does not exist`** — у тебя другой суперпользователь. В Docker-сетапе обычно `admin`, в чистой Linux-установке — `postgres`. Смотри переменную `POSTGRES_USER` контейнера или Linux-юзера на сервере.
- **Другие проблемы** — раздел «Если что-то сломалось» в [`PostgreSQL-Guide.md`](PostgreSQL-Guide.md).
