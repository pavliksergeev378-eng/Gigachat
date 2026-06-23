# LDAP group diagnostics

## Что собрать на работе

### 1. Браузер

Открыть `diagnostics.html` и нажать:

```text
Проверить GigaChat
Показать auth
Проверить planner-auth verify
Мои группы
Список групп
```

### 2. n8n executions

Открыть последние executions workflow:

```text
planner-auth / SSO. Поток
group-sync
```

Смотреть:

```text
Login prep
SQL: ensure user
Format login OK
SQL: my groups
Format my
```

### 3. PostgreSQL

Выполнить:

```sql
SELECT id, username, display_name, department, is_admin, last_login_at
FROM auth_users
ORDER BY id DESC
LIMIT 20;
```

```sql
SELECT * FROM task_groups ORDER BY id;
```

```sql
SELECT * FROM group_members ORDER BY group_id, user_id;
```

```sql
SELECT
  au.id AS user_id,
  au.username,
  au.display_name,
  au.department,
  tg.id AS group_id,
  tg.name AS group_name,
  gm.role AS group_role
FROM auth_users au
LEFT JOIN group_members gm ON gm.user_id = au.id
LEFT JOIN task_groups tg ON tg.id = gm.group_id
ORDER BY au.username, tg.name;
```

## Что замазать перед отправкой

Замазать:

```text
пароли
tokens
cookies
API keys
полный LDAP DN, если там персональные данные
почту, если нельзя показывать
```

Можно оставить:

```text
названия колонок
типы колонок
первые 3-5 символов токена, если нужно проверить наличие
факт наличия department/memberOf/groups
```
