# GigaChat group-sync: установка и проверка

## Назначение

`group-sync` — отдельный n8n workflow `/webhook/group-sync`, который отвечает за прикладные группы пользователей.

Он не заменяет `planner-auth`. Авторизация остаётся в `planner-auth`, а группы проверяются отдельным запросом после входа.

## Файлы

```text
Workflow/group-sync.json
База данных/group-sync_schema.sql
diagnostics.html
```

## 1. Подготовить БД

В n8n создать временный workflow:

```text
Manual Trigger → PostgreSQL
```

В PostgreSQL node выбрать:

```text
Operation: Execute Query
```

Выполнить:

```text
База данных/group-sync_schema.sql
```

## 2. Импортировать workflow

В n8n импортировать:

```text
Workflow/group-sync.json
```

После импорта:

1. проверить PostgreSQL credentials во всех PostgreSQL node;
2. убедиться, что webhook path = `group-sync`;
3. активировать workflow.

Ожидаемый endpoint:

```text
POST /webhook/group-sync
```

## 3. Добавить frontend helper

В `Agents/_shared.js` должен быть объект:

```js
GigaChat.groups
```

с методами:

```js
GigaChat.groups.my()
GigaChat.groups.list()
GigaChat.groups.create(name, description)
GigaChat.groups.join(groupId)
```

Если его нет, применить патч:

```text
patches/Agents_shared_add_GigaChat_groups.patch
```

## 4. Проверить через diagnostics.html

Открыть через HTTP:

```text
http://localhost:8765/diagnostics.html
```

или рабочий адрес платформы.

Нажать:

```text
Проверить GigaChat
Показать auth
Проверить planner-auth verify
Мои группы
Список групп
```

## 5. Проверить напрямую из Console

```js
console.log(await GigaChat.groups.my());
console.log(await GigaChat.groups.list());
```

## 6. Частые ошибки

### `GigaChat.groups is undefined`

Не применён патч `_shared.js` или браузер держит старый кэш.

### `404` от `/webhook/group-sync`

Workflow не импортирован или не активирован.

### `500` от `/webhook/group-sync`

Смотреть n8n execution. Обычно ошибка в SQL, credentials или подключении не к той БД.

### `groups: [{}]`

Нужно обновить `Format list` / `Format my` или импортировать исправленный `Workflow/group-sync.json`.
