-- planner-auth — это НЕ таблица БД, а n8n workflow/webhook.
-- В БД ожидаются auth_users, auth_sessions, task_groups, group_members.

SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
ORDER BY table_name;

SELECT id, username, display_name, is_admin
FROM auth_users
ORDER BY id;

SELECT LEFT(token, 8) AS token_prefix, user_id, expires_at, remember, last_used_at
FROM auth_sessions
ORDER BY last_used_at DESC NULLS LAST;

SELECT id, name, description, created_by, created_at
FROM task_groups
ORDER BY id;

SELECT
  gm.group_id,
  g.name AS group_name,
  gm.user_id,
  u.username,
  u.display_name,
  gm.role,
  gm.added_at
FROM group_members gm
JOIN task_groups g ON g.id = gm.group_id
JOIN auth_users u ON u.id = gm.user_id
ORDER BY g.name, gm.role, u.username;

SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'auth_users'
ORDER BY ordinal_position;

SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'task_groups'
ORDER BY ordinal_position;

SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'group_members'
ORDER BY ordinal_position;
