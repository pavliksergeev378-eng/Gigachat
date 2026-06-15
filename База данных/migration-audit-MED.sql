-- Миграции по итогам аудита (MED-блок). Применять к СУЩЕСТВУЮЩЕЙ БД ai_agent.
-- Идемпотентно (IF NOT EXISTS) — можно прогонять повторно.
-- Для свежих развёртываний эти же колонки добавлены в init-db.sql.

-- ── M12: tombstones для agent_sessions ───────────────────────────────
-- Мягкое удаление сессий, чтобы удалённая сессия не «воскресала» при upsert
-- с offline-устройства (см. sessions-sync «SQL: sessions op»).
ALTER TABLE agent_sessions ADD COLUMN IF NOT EXISTS deleted_at timestamptz;

-- ── M1: строгая изоляция chat_memory по user_id ──────────────────────
-- Каждое сообщение привязано к пользователю-владельцу. ВСЕ агентские
-- воркфлоу (chat/rag/math/prompt/plane/sql/history-loader) теперь читают
-- историю с фильтром «AND user_id = <владелец токена>» и пишут новые
-- сообщения с этим же user_id. Без этого история сессии одного пользователя
-- могла прочитаться в сессии другого (session_id угадывается/переиспользуется).
ALTER TABLE chat_memory ADD COLUMN IF NOT EXISTS user_id integer;

-- Бэкафилл по владельцу сессии из agent_sessions. Строки сессий, которых нет
-- в agent_sessions (доавторизационные / осиротевшие), останутся NULL и при
-- строгой фильтрации станут невидимы — осознанный компромисс изоляции.
UPDATE chat_memory cm
   SET user_id = a.user_id
  FROM agent_sessions a
 WHERE cm.session_id = a.session_id
   AND cm.user_id IS NULL;
-- Индекс не добавляем: idx_chat_memory_session (session_id, created_at) уже
-- делает выборку по session_id селективной (сотни строк на сессию), фильтр
-- user_id поверх них тривиален.
