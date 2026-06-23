-- Минимальная схема БД для group-sync.json
-- Выполнять в той же PostgreSQL-БД, где уже есть auth_users и auth_sessions.

CREATE TABLE IF NOT EXISTS task_groups (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    description TEXT DEFAULT '',
    created_by INTEGER REFERENCES auth_users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS group_members (
    group_id INTEGER NOT NULL REFERENCES task_groups(id) ON DELETE CASCADE,
    user_id INTEGER NOT NULL REFERENCES auth_users(id) ON DELETE CASCADE,
    role TEXT NOT NULL DEFAULT 'member',
    added_by INTEGER REFERENCES auth_users(id) ON DELETE SET NULL,
    added_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (group_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_group_members_user_id ON group_members(user_id);
CREATE INDEX IF NOT EXISTS idx_group_members_group_id ON group_members(group_id);
