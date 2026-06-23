# TODO: planner-auth — автоматическое назначение группы из LDAP

## Текущая проблема

При старом LDAP-входе пользователь успешно заходит, но группы не отображаются, потому что `planner-auth` не создаёт связь:

```text
auth_users.id → group_members.user_id → task_groups.id
```

`group-sync` уже умеет показывать группы, но ему нужны данные в `group_members`.

## Цель

После LDAP-входа:

1. получить пользователя;
2. извлечь LDAP-группу/отдел;
3. создать группу в `task_groups`, если её нет;
4. добавить пользователя в `group_members`;
5. вернуть на frontend поля группы.

## Готовые файлы для внесения в n8n

См. пакет:

```text
patches/planner-auth-ldap-auto-groups/
```

Файлы:

```text
01_Login_prep_replace.js
02_SQL_ensure_user_replace.sql
03_Format_login_OK_replace.js
04_optional_schema_check_and_patch.sql
05_diagnostics_after_login.sql
```

## Минимальный порядок работы

### 1. Сделать backup workflow

В n8n открыть `planner-auth` / `SSO. Поток` и сделать Duplicate или Export.

### 2. Посмотреть фактический LDAP-ответ

В execution найти node, который вызывает `login_work`, и посмотреть, где лежит:

```text
department
memberOf
groups
cn
displayName
```

Персональные данные и полный LDAP-ответ не отправлять наружу.

### 3. Проверить схему

Выполнить:

```text
04_optional_schema_check_and_patch.sql
```

### 4. Заменить node `Login prep`

Код взять из:

```text
01_Login_prep_replace.js
```

### 5. Заменить SQL node `SQL: ensure user`

SQL взять из:

```text
02_SQL_ensure_user_replace.sql
```

Query Parameters:

```js
={{ [$json.username, $json.display_name, $json.department, $json.group_name] }}
```

### 6. Заменить node `Format login OK`

Код взять из:

```text
03_Format_login_OK_replace.js
```

### 7. Проверка

Войти через LDAP, потом открыть:

```text
/diagnostics.html
```

Нажать:

```text
Показать auth
Мои группы
Список групп
```

Ожидаем `in_group: true`.
