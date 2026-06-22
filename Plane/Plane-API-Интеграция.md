# Plane API — документация для интеграции

## Задача

Есть рабочее приложение с авторизацией через LDAP. Пользователям в нём назначаются задачи. Нужно, чтобы эти задачи отображались в Plane и в нашем планировщике (GigaChat Plane-агент).

---

## 1. Что такое Plane

Plane — это open-source система управления проектами (аналог Jira/Linear):

- **Бэкенд**: Django 4.2 + Django REST Framework + PostgreSQL
- **Фронтенд**: Next.js (React)
- **API**: REST, авторизация через API-токены (заголовок `X-API-Key`)
- **События**: вебхуки при создании/изменении/удалении задач

---

## 2. Модель данных (что нам важно)

### Пользователь (`User`)
Поля: `id` (UUID), `username`, `email`, `display_name`, `first_name`, `last_name`, `is_active`.

**LDAP-поддержки в Plane нет.** Нужно будет синхронизировать пользователей из LDAP в Plane вручную или через скрипт.

### Workspace (рабочее пространство)
`id`, `name`, `slug`, `owner_id`. Один workspace на организацию.

### Project (проект)
`id`, `name`, `identifier` (короткий код, например `PROJ`), `workspace_id`, `description`.

### Issue (задача) — главная сущность
Поля:
| Поле | Тип | Описание |
|---|---|---|
| `id` | UUID | Уникальный идентификатор |
| `sequence_id` | int | Номер задачи в проекте (авто) |
| `name` | string | Название задачи |
| `description_html` | string | Описание (HTML) |
| `state_id` | UUID | Статус (FK → State) |
| `priority` | enum | `urgent` / `high` / `medium` / `low` / `none` |
| `start_date` | date | Дата начала |
| `target_date` | date | Срок выполнения |
| `assignees` | M2M | Исполнители (через IssueAssignee) |
| `labels` | M2M | Метки (через IssueLabel) |
| `parent_id` | UUID | Родительская задача (для подзадач) |
| `project_id` | UUID | Проект |
| `created_by_id` | UUID | Кто создал |
| `external_source` | string | Внешний источник |
| `external_id` | string | ID во внешней системе |

Важные поля: **`external_source` и `external_id`** — именно через них можно связать задачу в Plane с задачей в вашем LDAP-приложении.

### State (статус)
Стандартные статусы: **Backlog, Todo, In Progress, Done, Cancelled**.

### Cycle (спринт/цикл)
`id`, `name`, `start_date`, `end_date`, `project_id`.

### Module (модуль)
`id`, `name`, `project_id`, `status` (backlog/planned/in-progress/paused/completed/cancelled).

---

## 3. Аутентификация в Plane API

Plane использует API-токены. Как получить:

1. Зайти в Plane → Settings → API tokens
2. Создать токен (для сервисной интеграции — отметить `is_service`)
3. Токен имеет формат `plane_api_...`

**Использование:**
```
GET /api/...
Header: X-API-Key: plane_api_xxxxxxxxxxxx
```

Для n8n-воркфлоу этот токен передаётся в настройках Plane-агента (`plane_token`).

---

## 4. Основные API-эндпоинты

Все URL строятся от базового: `http://<plane-host>:8000`

### Проекты
```
GET  /api/v1/workspaces/{workspace_slug}/projects/
```
Возвращает список проектов. Параметр: `?per_page=1000`

### Задачи — CRUD
```
GET    /api/v1/workspaces/{workspace_slug}/projects/{project_id}/issues/
POST   /api/v1/workspaces/{workspace_slug}/projects/{project_id}/issues/
GET    /api/v1/workspaces/{workspace_slug}/projects/{project_id}/issues/{issue_id}/
PATCH  /api/v1/workspaces/{workspace_slug}/projects/{project_id}/issues/{issue_id}/
DELETE /api/v1/workspaces/{workspace_slug}/projects/{project_id}/issues/{issue_id}/
```

**Создание задачи:**
```json
POST /api/v1/workspaces/office/projects/<UUID>/issues/
Header: X-API-Key: plane_api_...
{
  "name": "Позвонить клиенту",
  "description_html": "<p>Нужно позвонить до пятницы</p>",
  "priority": "high",
  "target_date": "2026-06-27",
  "assignees": ["<user-uuid-1>"],
  "labels": ["<label-uuid>"],
  "external_source": "ldap-app",
  "external_id": "task-12345"
}
```

**Обновление задачи:**
```json
PATCH /api/v1/workspaces/office/projects/<UUID>/issues/<UUID>/
{
  "state_id": "<done-state-uuid>",
  "priority": "urgent"
}
```

### Поиск задачи по external_id

Прямого эндпоинта для поиска по `external_id` нет. Нужно использовать общий поиск:
```
GET /api/v1/workspaces/{workspace_slug}/projects/{project_id}/issues/?search=task-12345
```
Либо хранить маппинг external_id → plane_issue_id в своём приложении.

### Пользователи проекта
```
GET /api/v1/workspaces/{workspace_slug}/projects/{project_id}/members/
```

### Циклы (спринты)
```
GET /api/v1/workspaces/{workspace_slug}/projects/{project_id}/cycles/
```

### Модули
```
GET /api/v1/workspaces/{workspace_slug}/projects/{project_id}/modules/
```

### Вебхуки
```
GET    /api/v2/workspaces/{workspace_slug}/webhooks/
POST   /api/v2/workspaces/{workspace_slug}/webhooks/
DELETE /api/v2/workspaces/{workspace_slug}/webhooks/{webhook_id}/
```

---

## 5. Вебхуки — события из Plane наружу

Plane умеет отправлять вебхуки при изменениях. Это основной способ получить **обратную связь** (если задачу изменили в Plane — обновить в LDAP-приложении).

### Создание вебхука
```json
POST /api/v2/workspaces/{workspace_slug}/webhooks/
{
  "url": "https://your-ldap-app.example.com/plane-webhook",
  "project": true,
  "issue": true,
  "module": false,
  "cycle": false,
  "issue_comment": false,
  "is_active": true
}
```

### Формат вебхука
```json
{
  "event": "issue",
  "action": "update",
  "workspace_id": "<uuid>",
  "workspace_slug": "office",
  "data": { ... },
  "activity": [
    {
      "field": "state",
      "old_value": "todo",
      "new_value": "done",
      "actor": { "id": "...", "display_name": "..." }
    }
  ]
}
```

### Подпись
Plane подписывает вебхуки HMAC-SHA256:
- Заголовок: `X-Plane-Signature: <signature>`
- Секрет: `secret_key` из ответа при создании вебхука (формат: `plane_wh_...`)

Типы событий: `project`, `issue`, `module`, `cycle`, `module_issue`, `cycle_issue`, `issue_comment`.

---

## 6. Схема интеграции LDAP-приложение ↔ Plane

### Вариант А: Прямая запись в Plane API (рекомендуемый)

```
LDAP-приложение
    │
    │  При создании/изменении/удалении задачи
    │  вызывать Plane API напрямую:
    │
    ├── POST /issues/ (создать)   → задача появляется в Plane
    ├── PATCH /issues/{id}/ (обновить)
    └── DELETE /issues/{id}/ (удалить)
    
Plane
    │
    │  Вебхук при изменениях
    │  (если кто-то меняет задачу в Plane — синхронизировать обратно)
    │
    └── POST → LDAP-приложение (колбэк)
```

**Что нужно сделать:**
1. Создать API-токен в Plane (service-токен)
2. В коде LDAP-приложения добавить вызовы Plane API при операциях с задачами
3. Хранить маппинг: `задача_LDAP` → `plane_issue_id` (в БД приложения)
4. При создании задачи в Plane передавать `external_source: "ldap-app"`, `external_id: <id из LDAP-приложения>`

### Вариант Б: Периодическая синхронизация (если прямой вызов невозможен)

Пишется скрипт (cron/Celery), который:
1. Забирает все задачи из LDAP-приложения
2. Забирает все задачи из Plane
3. Сравнивает по `external_id` и синхронизирует изменения

Минус: задержка.

### Вариант В: Через n8n (если n8n уже используется)

Создать отдельный n8n-воркфлоу, который:
1. Принимает вебхук от LDAP-приложения
2. Вызывает Plane API
3. Возвращает результат

Это разгружает основное приложение от прямой работы с Plane API.

---

## 7. Синхронизация пользователей (LDAP → Plane)

Plane не поддерживает LDAP из коробки. Варианты решения:

### A. Ручная синхронизация через API
Создать скрипт, который при входе пользователя или по расписанию проверяет — есть ли пользователь в Plane, и если нет, создаёт его или приглашает в workspace.

### B. Django-кастомная аутентификация
Plane написан на Django. Можно добавить кастомный authentication backend с LDAP (например, `django-auth-ldap`):
1. Установить `django-auth-ldap` в Plane-бэкенд
2. Прописать LDAP-конфигурацию в `settings/common.py`
3. Добавить `AUTHENTICATION_BACKENDS` с LDAP-бэкендом

Это позволит пользователям LDAP входить в Plane напрямую.

### C. Создание пользователей через API
Если не нужен вход в Plane, а нужны только назначения задач — пользователей можно создать через API:
```json
POST /api/v2/workspaces/{workspace_slug}/invitations/
{
  "email": "user@company.com",
  "role": 15
}
```
Или напрямую через Django shell / management command.

---

## 8. Связка с GigaChat Plane-агентом

Ваш Plane-агент в n8n уже работает с Plane API — он использует те же эндпоинты. После того как LDAP-приложение начнёт писать задачи в Plane:

1. Задачи автоматически станут видны в Plane-агенте
2. Пользователи смогут искать, фильтровать, менять эти задачи через чат GigaChat
3. Вебхуки Plane обеспечат обратную синхронизацию (изменения из Plane → в LDAP-приложение)

Никаких изменений в Plane-агенте не требуется — он уже умеет работать со всеми задачами в проектах Plane.

---

## 9. Что нужно от начальника

### Для реализации нужны:

1. **Доступ к Plane API**:
   - URL Plane (например `http://plane.internal:8000`)
   - Workspace slug
   - API-токен (service account)

2. **Проект в Plane**:
   - Создать проект, в который будут попадать задачи из LDAP-приложения
   - Или использовать существующий

3. **Решение по пользователям**:
   - Будут ли пользователи LDAP заходить в Plane напрямую (нужен LDAP auth) — **Вариант B**
   - Или только для назначения задач, без входа в Plane — **Вариант C**

4. **Решение по направлению синхронизации**:
   - Только LDAP-приложение → Plane (односторонняя) — проще
   - LDAP-приложение ↔ Plane (двусторонняя через вебхуки) — сложнее, нужен колбэк-эндпоинт

5. **Ответственный за код LDAP-приложения**:
   - Чтобы добавить вызовы Plane API в логику работы с задачами

---

## 10. Пример: создание задачи из Python

```python
import requests

PLANE_URL = "http://plane.internal:8000"
WORKSPACE_SLUG = "office"
PROJECT_ID = "550e8400-e29b-41d4-a716-446655440000"
API_KEY = "plane_api_xxxxxxxxxxxx"

headers = {
    "X-API-Key": API_KEY,
    "Content-Type": "application/json"
}

def create_issue(name, description, priority="medium", assignee_ids=None, external_id=None):
    body = {
        "name": name,
        "description_html": f"<p>{description}</p>",
        "priority": priority,
        "external_source": "ldap-app",
    }
    if assignee_ids:
        body["assignees"] = assignee_ids
    if external_id:
        body["external_id"] = str(external_id)

    url = f"{PLANE_URL}/api/v1/workspaces/{WORKSPACE_SLUG}/projects/{PROJECT_ID}/issues/"
    resp = requests.post(url, json=body, headers=headers)
    resp.raise_for_status()
    return resp.json()

def update_issue(issue_id, **fields):
    url = f"{PLANE_URL}/api/v1/workspaces/{WORKSPACE_SLUG}/projects/{PROJECT_ID}/issues/{issue_id}/"
    resp = requests.patch(url, json=fields, headers=headers)
    resp.raise_for_status()
    return resp.json()

def get_issues():
    url = f"{PLANE_URL}/api/v1/workspaces/{WORKSPACE_SLUG}/projects/{PROJECT_ID}/issues/?per_page=100"
    resp = requests.get(url, headers=headers)
    resp.raise_for_status()
    return resp.json()
```

---

## 11. Схема данных (ER-диаграмма, ключевые таблицы)

```
Workspace 1──────M Project 1──────M Issue M──────M User (assignees)
    │                   │                │
    │                   │                ├── IssueActivity (история изменений)
    │                   │                ├── IssueComment
    │                   │                ├── IssueLabel M──M Label
    │                   │                └── IssueAttachment
    │                   │
    │                   ├── Cycle 1──M CycleIssue
    │                   ├── Module 1──M ModuleIssue
    │                   ├── State (статусы)
    │                   ├── Webhook
    │                   └── ProjectMember M──M User
    │
    ├── WorkspaceMember M──M User
    └── APIToken
```
