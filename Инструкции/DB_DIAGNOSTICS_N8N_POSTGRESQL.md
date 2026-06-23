# Диагностика PostgreSQL через n8n

## Как запускать

В n8n создать workflow:

```text
Manual Trigger → PostgreSQL
```

В PostgreSQL node:

```text
Operation: Execute Query
```

Запускать SQL по одному блоку.

## 1. Проверка подключения

```sql
SELECT
  current_database() AS database_name,
  current_schema() AS schema_name,
  current_user AS db_user,
  inet_server_addr() AS server_ip,
  inet_server_port() AS server_port,
  now() AS checked_at;
```

## 2. Все таблицы public

```sql
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_schema = 'public'
ORDER BY table_name;
```

## 3. Ключевые таблицы

```sql
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN ('auth_users', 'auth_sessions', 'task_groups', 'group_members')
ORDER BY table_name;
```

## 4. Структура auth_users

```sql
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'auth_users'
ORDER BY ordinal_position;
```

## 5. Структура task_groups

```sql
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'task_groups'
ORDER BY ordinal_position;
```

## 6. Структура group_members

```sql
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'group_members'
ORDER BY ordinal_position;
```

## 7. Количество строк

```sql
SELECT 'auth_users' AS table_name, COUNT(*) AS rows_count FROM auth_users
UNION ALL
SELECT 'task_groups' AS table_name, COUNT(*) AS rows_count FROM task_groups
UNION ALL
SELECT 'group_members' AS table_name, COUNT(*) AS rows_count FROM group_members;
```

## 8. Пользователь + группа

```sql
SELECT
  au.id AS user_id,
  au.username,
  au.display_name,
  tg.id AS group_id,
  tg.name AS group_name,
  gm.role AS group_role,
  COALESCE(gm.added_at, gm.created_at) AS joined_at
FROM group_members gm
JOIN auth_users au ON au.id = gm.user_id
JOIN task_groups tg ON tg.id = gm.group_id
ORDER BY au.username, tg.name;
```

## 9. Пользователи без группы

```sql
SELECT au.*
FROM auth_users au
LEFT JOIN group_members gm ON gm.user_id = au.id
WHERE gm.user_id IS NULL
LIMIT 50;
```

## 10. LDAP / department / group поля

```sql
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND (
    column_name ILIKE '%ldap%'
    OR column_name ILIKE '%department%'
    OR column_name ILIKE '%group%'
    OR column_name ILIKE '%role%'
    OR column_name ILIKE '%login%'
    OR column_name ILIKE '%email%'
  )
ORDER BY table_name, column_name;
```

Полный набор запросов лежит в:

```text
База данных/postgres_diagnostics.sql
```
