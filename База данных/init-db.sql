-- ============================================================================
-- Полная инициализация БД ai_agent под GigaChat: расширения + все таблицы проекта.
-- Прогоняется ОДИН РАЗ на свежесозданной БД.
-- ============================================================================

\echo '== Расширения =='
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

\echo '== RAG-агент: documents (embedding vector(1024)) =='
CREATE TABLE IF NOT EXISTS documents (
    id SERIAL PRIMARY KEY,
    filename VARCHAR(500) NOT NULL,
    chunk_index INTEGER NOT NULL,
    chunk_text TEXT NOT NULL,
    embedding vector(1024),
    created_at TIMESTAMP DEFAULT NOW(),
    CONSTRAINT documents_filename_chunk_unique UNIQUE (filename, chunk_index)
);
CREATE INDEX IF NOT EXISTS idx_documents_embedding
    ON documents USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);
CREATE INDEX IF NOT EXISTS idx_documents_filename ON documents (filename);

\echo '== Память агентов: chat_memory + chat_summaries =='
CREATE TABLE IF NOT EXISTS chat_memory (
    id SERIAL PRIMARY KEY,
    session_id VARCHAR(255) NOT NULL,
    role VARCHAR(20) NOT NULL,
    content TEXT NOT NULL,
    extras JSONB,
    created_at TIMESTAMP DEFAULT NOW(),
    -- M1 (аудит): владелец сообщения. Все агентские воркфлоу читают и пишут
    -- историю строго с user_id = владелец токена, чтобы история одного
    -- пользователя не утекала в сессию другого. NULL = доавторизационная
    -- (осиротевшая) история, при строгой фильтрации невидима.
    user_id INTEGER
);
CREATE INDEX IF NOT EXISTS idx_chat_memory_session
    ON chat_memory (session_id, created_at);

CREATE TABLE IF NOT EXISTS chat_summaries (
    session_id VARCHAR(255) PRIMARY KEY,
    summary_text TEXT,
    messages_summarized INTEGER DEFAULT 0,
    updated_at TIMESTAMP DEFAULT NOW()
);

\echo '== SSO: auth_users + auth_sessions (общая auth для всех агентов) =='
CREATE TABLE IF NOT EXISTS auth_users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(100) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,  -- у доменных юзеров — случайный (вход только через домен)
    display_name VARCHAR(200),            -- ФИО из домена (login_work/LDAP); показывается в шапке
    is_admin BOOLEAN DEFAULT false,       -- админ: может пополнять Базу знаний compliance
    created_at TIMESTAMP DEFAULT NOW(),
    last_login_at TIMESTAMP,
    password_changed_at TIMESTAMP DEFAULT NOW()
);
-- Миграция для уже существующей БД:
ALTER TABLE auth_users ADD COLUMN IF NOT EXISTS display_name VARCHAR(200);
ALTER TABLE auth_users ADD COLUMN IF NOT EXISTS is_admin BOOLEAN DEFAULT false;
-- Назначить администратора (пополнение Базы знаний): подставь свой логин
--   UPDATE auth_users SET is_admin = true WHERE username = '<твой_логин>';
CREATE INDEX IF NOT EXISTS idx_auth_users_username_lower
    ON auth_users (LOWER(username));

CREATE TABLE IF NOT EXISTS auth_sessions (
    token VARCHAR(64) PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES auth_users(id) ON DELETE CASCADE,
    created_at TIMESTAMP DEFAULT NOW(),
    last_used_at TIMESTAMP DEFAULT NOW(),
    expires_at TIMESTAMP NOT NULL,
    remember BOOLEAN DEFAULT FALSE
);
CREATE INDEX IF NOT EXISTS idx_auth_sessions_user
    ON auth_sessions (user_id);
CREATE INDEX IF NOT EXISTS idx_auth_sessions_expires
    ON auth_sessions (expires_at);

-- agent_sessions: общая для всех агентов. Sync через /webhook/sessions-sync,
-- ключ (user_id, agent, session_id) — один аккаунт видит свои сессии на
-- любом ПК, разные аккаунты на одном ПК изолированы. agent ∈ {planner, chat,
-- rag, math, prompt, plane, compliance}.
\echo '== agent_sessions: единый стор сессий всех агентов =='
CREATE TABLE IF NOT EXISTS agent_sessions (
    session_id  VARCHAR(255) NOT NULL,
    user_id     INTEGER NOT NULL REFERENCES auth_users(id) ON DELETE CASCADE,
    agent       VARCHAR(32)  NOT NULL,
    name        TEXT         NOT NULL,
    sort_order  INTEGER      NOT NULL DEFAULT 0,
    created_at  TIMESTAMP    NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMP    NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, agent, session_id)
);
CREATE INDEX IF NOT EXISTS idx_agent_sessions_user_agent_sorted
    ON agent_sessions (user_id, agent, sort_order, updated_at DESC);

\echo '== Compliance-агент: база знаний по нарушениям информационной безопасности, меры, история =='
-- Агент формирования компенсирующих мер по выявленным нарушениям информационной безопасности.
-- Модель: RAG по нормативке (kb_norms) + структурированная экспертная база
-- (нарушения <-> требования <-> риски <-> меры) + примеры (kb_cases) + история.
-- embedding vector(1024) — как у documents (локальный GigaChat-эмбеддер).
-- Семантические поля (embedding) наполняет загрузчик/переэмбеддер; сид без них.

-- 1) Корпус нормативки для семантического поиска (наполняется загрузчиком документов).
CREATE TABLE IF NOT EXISTS kb_norms (
    id           SERIAL PRIMARY KEY,
    doc_name     VARCHAR(500) NOT NULL,   -- ГОСТ Р 57580, Приказ ФСТЭК №21, Политика информационной безопасности…
    doc_version  VARCHAR(50),             -- редакция документа (контроль версий, ТЗ п.10)
    section      VARCHAR(200),            -- пункт/раздел = источник требования
    chunk_index  INTEGER NOT NULL DEFAULT 0,
    chunk_text   TEXT NOT NULL,
    embedding    vector(1024),
    created_at   TIMESTAMP DEFAULT NOW(),
    CONSTRAINT kb_norms_doc_chunk_unique UNIQUE (doc_name, doc_version, chunk_index)
);
CREATE INDEX IF NOT EXISTS idx_kb_norms_embedding
    ON kb_norms USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);
CREATE INDEX IF NOT EXISTS idx_kb_norms_doc ON kb_norms (doc_name);

-- 2) Типовые нарушения (embedding — для матча входящего нарушения по смыслу).
CREATE TABLE IF NOT EXISTS kb_violations (
    id           SERIAL PRIMARY KEY,
    title        VARCHAR(500) NOT NULL UNIQUE,
    category     VARCHAR(120) NOT NULL,   -- категория нарушения
    processes    TEXT,                    -- затронутые процессы (через ;)
    description  TEXT,
    criticality  VARCHAR(20) DEFAULT 'medium'
        CHECK (criticality IN ('low','medium','high','critical')),
    embedding    vector(1024),
    created_at   TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_kb_violations_embedding
    ON kb_violations USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);
CREATE INDEX IF NOT EXISTS idx_kb_violations_category ON kb_violations (category);

-- 3) Нормативные требования (на что ссылаемся в обосновании).
CREATE TABLE IF NOT EXISTS kb_requirements (
    id           SERIAL PRIMARY KEY,
    text         TEXT NOT NULL,
    norm_ref     VARCHAR(500),            -- источник: документ + пункт + версия
    criticality  VARCHAR(20) DEFAULT 'medium'
        CHECK (criticality IN ('low','medium','high','critical')),
    created_at   TIMESTAMP DEFAULT NOW()
);

-- 4) Типовые риски.
CREATE TABLE IF NOT EXISTS kb_risks (
    id           SERIAL PRIMARY KEY,
    title        VARCHAR(500) NOT NULL,
    description  TEXT,
    criticality  VARCHAR(20) DEFAULT 'medium'
        CHECK (criticality IN ('low','medium','high','critical')),
    created_at   TIMESTAMP DEFAULT NOW()
);

-- 5) Компенсирующие меры (4 типа по ТЗ, п.5).
CREATE TABLE IF NOT EXISTS kb_measures (
    id               SERIAL PRIMARY KEY,
    type             VARCHAR(20) NOT NULL
        CHECK (type IN ('organizational','technical','administrative','controlling')),
    name             VARCHAR(500) NOT NULL UNIQUE,
    description      TEXT,
    expected_effect  TEXT,                -- ожидаемый эффект
    created_at       TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_kb_measures_type ON kb_measures (type);

-- 6) Связи (их наполняют эксперты — главная ценность базы).
CREATE TABLE IF NOT EXISTS kb_violation_requirement (
    violation_id   INTEGER NOT NULL REFERENCES kb_violations(id) ON DELETE CASCADE,
    requirement_id INTEGER NOT NULL REFERENCES kb_requirements(id) ON DELETE CASCADE,
    PRIMARY KEY (violation_id, requirement_id)
);
CREATE TABLE IF NOT EXISTS kb_violation_risk (
    violation_id INTEGER NOT NULL REFERENCES kb_violations(id) ON DELETE CASCADE,
    risk_id      INTEGER NOT NULL REFERENCES kb_risks(id) ON DELETE CASCADE,
    PRIMARY KEY (violation_id, risk_id)
);
CREATE TABLE IF NOT EXISTS kb_violation_measure (
    violation_id INTEGER NOT NULL REFERENCES kb_violations(id) ON DELETE CASCADE,
    measure_id   INTEGER NOT NULL REFERENCES kb_measures(id) ON DELETE CASCADE,
    PRIMARY KEY (violation_id, measure_id)
);

-- 7) Примеры реализованных решений (few-shot + самообогащение из утверждённых кейсов).
CREATE TABLE IF NOT EXISTS kb_cases (
    id              SERIAL PRIMARY KEY,
    violation_text  TEXT NOT NULL,
    category        VARCHAR(120),
    measures_json   JSONB,               -- утверждённый набор мер
    justification   TEXT,
    embedding       vector(1024),
    approved_by     INTEGER REFERENCES auth_users(id),
    created_at      TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_kb_cases_embedding
    ON kb_cases USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);

-- 8) История обработанных нарушений (ТЗ п.3) + поля ввода (ТЗ п.4).
CREATE TABLE IF NOT EXISTS compliance_incidents (
    id              SERIAL PRIMARY KEY,
    user_id         INTEGER REFERENCES auth_users(id),
    -- вход (структурированные данные, ТЗ п.4):
    violation       VARCHAR(500),        -- нарушение
    description     TEXT,                -- описание нарушения
    control_object  VARCHAR(300),        -- объект контроля
    criticality     VARCHAR(20),         -- уровень критичности
    check_results   TEXT,                -- результаты проверок
    risk_level      VARCHAR(20),         -- уровень риска
    -- выход:
    category        VARCHAR(120),
    measures_json   JSONB,               -- сформированные меры (4 типа)
    report          JSONB,               -- собранный отчёт (нарушение, риск, меры, ссылки, остаточный риск, сроки)
    residual_risk   VARCHAR(20),
    status          VARCHAR(20) DEFAULT 'draft'
        CHECK (status IN ('draft','approved','rejected')),
    created_at      TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_compliance_incidents_user
    ON compliance_incidents (user_id, created_at DESC);

\echo '== Сид базы знаний по информационной безопасности (ПРИМЕР — замените реальной нормативкой и связями) =='
-- Меры (org/tech/admin/control)
INSERT INTO kb_measures (type, name, description, expected_effect) VALUES
('technical','Внедрить автоматизированное резервное копирование','Настроить ежедневное автоматическое резервное копирование критичных серверов и СУБД.','Гарантированное восстановление данных при сбое/шифровальщике.'),
('organizational','Организовать хранение копий на отдельной площадке','Хранить резервные копии географически отдельно (offsite / отдельный сегмент).','Сохранность копий при физическом инциденте на основной площадке.'),
('controlling','Проводить ежеквартальную проверку восстановления','Регулярно тест-восстанавливать данные из копий и фиксировать результат.','Подтверждённая работоспособность процедуры восстановления.'),
('administrative','Назначить ответственных за контроль резервного копирования','Закрепить приказом ответственных за выполнение и контроль процедур ДКП.','Персональная ответственность и исполнимость процедур.'),
('administrative','Утвердить и довести парольную политику','Утвердить требования к сложности/смене паролей и ознакомить сотрудников.','Снижение риска компрометации учётных записей.'),
('technical','Включить требования сложности и блокировку учётных записей','Технически принудить длину/сложность пароля и блокировку после N неудач.','Защита от перебора и слабых паролей.'),
('technical','Развернуть централизованную антивирусную защиту','Установить и централизованно управлять антивирусом на всех узлах.','Обнаружение и блокировка вредоносного ПО.'),
('controlling','Контролировать актуальность антивирусных баз','Мониторить обновление баз и покрытие узлов антивирусом.','Поддержание защиты в актуальном состоянии.'),
('technical','Включить журналирование событий безопасности','Настроить сбор журналов доступа/действий в централизованный сборщик (SIEM).','Прослеживаемость действий и расследование инцидентов.'),
('organizational','Регламентировать хранение и анализ журналов','Определить сроки хранения и порядок регулярного анализа журналов.','Своевременное выявление аномалий и доказательная база.')
ON CONFLICT (name) DO NOTHING;

-- Типовые нарушения
INSERT INTO kb_violations (title, category, processes, description, criticality) VALUES
('Отсутствует резервное копирование критически важных серверов','Резервное копирование','Восстановление; Непрерывность; Хранение данных','Для критичных серверов не настроено резервное копирование, восстановление данных не гарантировано.','critical'),
('Слабая парольная политика','Управление доступом','Аутентификация; Управление учётными записями','Не заданы требования к сложности и смене паролей, возможны слабые пароли.','high'),
('Отсутствует антивирусная защита','Защита от ВПО','Защита рабочих станций; Защита серверов','На части узлов не установлена/не управляется антивирусная защита.','high'),
('Не ведётся журналирование событий безопасности','Аудит и мониторинг','Мониторинг; Расследование инцидентов','Не настроен сбор журналов доступа и действий, расследование инцидентов затруднено.','medium')
ON CONFLICT (title) DO NOTHING;

-- Требования
INSERT INTO kb_requirements (text, norm_ref, criticality) VALUES
('Обеспечить резервное копирование и восстановление информации критичных систем.','Политика информационной безопасности, разд. «Резервное копирование» (заменить на реальный пункт ГОСТ/приказа)','critical'),
('Установить требования к сложности и периодичности смены паролей.','Политика информационной безопасности, разд. «Управление доступом»','high'),
('Обеспечить антивирусную защиту узлов обработки информации.','Политика информационной безопасности, разд. «Защита от ВПО»','high'),
('Обеспечить регистрацию событий безопасности и хранение журналов.','Политика информационной безопасности, разд. «Аудит и мониторинг»','medium')
ON CONFLICT DO NOTHING;

-- Риски
INSERT INTO kb_risks (title, description, criticality) VALUES
('Безвозвратная потеря критичных данных','Сбой/шифровальщик при отсутствии копий ведёт к необратимой потере данных.','critical'),
('Компрометация учётных записей','Слабые пароли упрощают несанкционированный доступ.','high'),
('Заражение вредоносным ПО','Отсутствие антивируса повышает риск заражения и распространения ВПО.','high'),
('Невозможность расследования инцидентов','Без журналов нельзя установить факты и виновных.','medium')
ON CONFLICT DO NOTHING;

-- Связи: нарушение -> меры
INSERT INTO kb_violation_measure (violation_id, measure_id)
SELECT v.id, m.id FROM kb_violations v JOIN kb_measures m ON TRUE
WHERE v.title='Отсутствует резервное копирование критически важных серверов'
  AND m.name IN ('Внедрить автоматизированное резервное копирование','Организовать хранение копий на отдельной площадке','Проводить ежеквартальную проверку восстановления','Назначить ответственных за контроль резервного копирования')
ON CONFLICT DO NOTHING;
INSERT INTO kb_violation_measure (violation_id, measure_id)
SELECT v.id, m.id FROM kb_violations v JOIN kb_measures m ON TRUE
WHERE v.title='Слабая парольная политика'
  AND m.name IN ('Утвердить и довести парольную политику','Включить требования сложности и блокировку учётных записей')
ON CONFLICT DO NOTHING;
INSERT INTO kb_violation_measure (violation_id, measure_id)
SELECT v.id, m.id FROM kb_violations v JOIN kb_measures m ON TRUE
WHERE v.title='Отсутствует антивирусная защита'
  AND m.name IN ('Развернуть централизованную антивирусную защиту','Контролировать актуальность антивирусных баз')
ON CONFLICT DO NOTHING;
INSERT INTO kb_violation_measure (violation_id, measure_id)
SELECT v.id, m.id FROM kb_violations v JOIN kb_measures m ON TRUE
WHERE v.title='Не ведётся журналирование событий безопасности'
  AND m.name IN ('Включить журналирование событий безопасности','Регламентировать хранение и анализ журналов')
ON CONFLICT DO NOTHING;

-- Связи: нарушение -> требование (по индексу совпадения порядка)
INSERT INTO kb_violation_requirement (violation_id, requirement_id)
SELECT v.id, r.id FROM kb_violations v JOIN kb_requirements r ON TRUE
WHERE (v.title='Отсутствует резервное копирование критически важных серверов' AND r.norm_ref LIKE '%Резервное копирование%')
   OR (v.title='Слабая парольная политика' AND r.norm_ref LIKE '%Управление доступом%')
   OR (v.title='Отсутствует антивирусная защита' AND r.norm_ref LIKE '%Защита от ВПО%')
   OR (v.title='Не ведётся журналирование событий безопасности' AND r.norm_ref LIKE '%Аудит и мониторинг%')
ON CONFLICT DO NOTHING;

-- Связи: нарушение -> риск
INSERT INTO kb_violation_risk (violation_id, risk_id)
SELECT v.id, rk.id FROM kb_violations v JOIN kb_risks rk ON TRUE
WHERE (v.title='Отсутствует резервное копирование критически важных серверов' AND rk.title='Безвозвратная потеря критичных данных')
   OR (v.title='Слабая парольная политика' AND rk.title='Компрометация учётных записей')
   OR (v.title='Отсутствует антивирусная защита' AND rk.title='Заражение вредоносным ПО')
   OR (v.title='Не ведётся журналирование событий безопасности' AND rk.title='Невозможность расследования инцидентов')
ON CONFLICT DO NOTHING;

-- Пример реализованного кейса (few-shot)
INSERT INTO kb_cases (violation_text, category, measures_json, justification) VALUES
('Отсутствует резервное копирование критически важных серверов','Резервное копирование',
 '[{"type":"technical","name":"Внедрить автоматизированное резервное копирование"},{"type":"organizational","name":"Организовать хранение копий на отдельной площадке"},{"type":"controlling","name":"Проводить ежеквартальную проверку восстановления"},{"type":"administrative","name":"Назначить ответственных за контроль резервного копирования"}]'::jsonb,
 'Меры закрывают риск безвозвратной потери данных: автоматизация исключает человеческий фактор, offsite-хранение защищает от физического инцидента, регулярные тесты подтверждают восстановимость, ответственные обеспечивают исполнимость.')
ON CONFLICT DO NOTHING;

\echo '== Организация обращения: appeal_employees + appeal_event1 + appeal_event2 =='
-- Подробности по алгоритму и сценариям тестов: см. OrgAppeal-Setup.md.
-- employee_number NULLABLE — отличает «нет в реестре» (D) от «есть, но без ТН» (E).
CREATE TABLE IF NOT EXISTS appeal_employees (
    id              SERIAL PRIMARY KEY,
    full_name       VARCHAR(200) NOT NULL,
    employee_number VARCHAR(50),
    created_at      TIMESTAMP DEFAULT NOW()
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_appeal_employees_name ON appeal_employees (full_name);

CREATE TABLE IF NOT EXISTS appeal_event1 (
    id          SERIAL PRIMARY KEY,
    full_name   VARCHAR(200) NOT NULL,
    is_done     BOOLEAN NOT NULL DEFAULT FALSE,
    done_at     TIMESTAMP,
    created_at  TIMESTAMP DEFAULT NOW()
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_appeal_event1_name ON appeal_event1 (full_name);

CREATE TABLE IF NOT EXISTS appeal_event2 (
    id          SERIAL PRIMARY KEY,
    full_name   VARCHAR(200) NOT NULL,
    is_done     BOOLEAN NOT NULL DEFAULT FALSE,
    done_at     TIMESTAMP,
    created_at  TIMESTAMP DEFAULT NOW()
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_appeal_event2_name ON appeal_event2 (full_name);

\echo '== Тестовые данные для алгоритма: 58 сотрудников + 40 event1 + 28 event2 =='
INSERT INTO appeal_employees (full_name, employee_number) VALUES
('Иванов Иван Иванович', '10001'),
('Петров Пётр Петрович', '10002'),
('Сидоров Сидор Сидорович', NULL),
('Богданов Богдан Богданович', '10004'),
('Морозов Михаил Михайлович', '10005'),
('Михайлов Дмитрий Александрович', '10006'),
('Васильев Андрей Сергеевич', '10007'),
('Иванова Иванна Ивановна', '10008'),
('Фёдоров Алексей Николаевич', '10010'),
('Волков Артём Денисович', '10011'),
('Алексеев Максим Игоревич', '10012'),
('Лебедев Кирилл Андреевич', '10013'),
('Семёнов Илья Михайлович', '10014'),
('Егоров Антон Юрьевич', '10015'),
('Павлов Роман Олегович', '10016'),
('Козлов Степан Петрович', '10017'),
('Соколов Глеб Дмитриевич', '10018'),
('Виноградов Тимофей Алексеевич', '10019'),
('Никитин Артемий Никитич', '10020'),
('Орлов Матвей Александрович', '10021'),
('Андреев Захар Тимофеевич', '10022'),
('Макаров Лев Юрьевич', '10023'),
('Беляев Марк Романович', '10024'),
('Тарасов Михаил Дмитриевич', '10025'),
('Соловьёв Григорий Петрович', '10026'),
('Захаров Аркадий Степанович', '10027'),
('Борисов Виктор Глебович', '10028'),
('Королёв Платон Кириллович', '10029'),
('Гусев Владимир Семёнович', '10030'),
('Киселёв Олег Артурович', '10031'),
('Куликов Анатолий Игнатьевич', '10032'),
('Романов Кирилл Германович', '10033'),
('Сергеев Никита Аркадьевич', '10034'),
('Фролов Эдуард Тимурович', '10035'),
('Жуков Илья Владиславович', '10036'),
('Антонов Денис Леонидович', '10037'),
('Маркин Богдан Олегович', '10038'),
('Зайцев Сергей Михайлович', '10039'),
('Соболев Виталий Эдуардович', '10040'),
('Зимин Захар Эдуардович', NULL),
('Селезнёв Михаил Витальевич', NULL),
('Дроздов Артур Дмитриевич', NULL),
('Петрова Мария Петровна', '10045'),
('Смирнова Елена Викторовна', '10046'),
('Кузнецова Ольга Андреевна', '10047'),
('Соколова Татьяна Сергеевна', '10048'),
('Попова Наталья Михайловна', '10049'),
('Лебедева Ирина Алексеевна', '10050'),
('Козлова Екатерина Дмитриевна', '10051'),
('Новикова Светлана Петровна', '10052'),
('Морозова Юлия Александровна', '10053'),
('Васильева Виктория Юрьевна', '10054'),
('Соловьёва Алла Семёновна', '10055'),
('Михайлова Полина Романовна', '10056'),
('Полякова Софья Игоревна', '10057'),
('Тихонова Анастасия Павловна', '10058'),
('Калинина Дарья Степановна', '10059'),
('Кузьмина Татьяна Андреевна', NULL)
ON CONFLICT (full_name) DO NOTHING;

INSERT INTO appeal_event1 (full_name, is_done, done_at) VALUES
('Морозов Михаил Михайлович', FALSE, NULL),
('Михайлов Дмитрий Александрович', TRUE,  NOW() - INTERVAL '60 days'),
('Васильев Андрей Сергеевич', TRUE,  NOW() - INTERVAL '45 days'),
('Иванова Иванна Ивановна', TRUE,  NOW() - INTERVAL '30 days'),
('Иванов Иван Иванович', TRUE,  NOW() - INTERVAL '30 days'),
('Петров Пётр Петрович', TRUE,  NOW() - INTERVAL '25 days'),
('Сидоров Сидор Сидорович', TRUE,  NOW() - INTERVAL '20 days'),
('Фёдоров Алексей Николаевич', TRUE,  NOW() - INTERVAL '12 days'),
('Волков Артём Денисович', TRUE,  NOW() - INTERVAL '90 days'),
('Алексеев Максим Игоревич', TRUE,  NOW() - INTERVAL '21 days'),
('Лебедев Кирилл Андреевич', TRUE,  NOW() - INTERVAL '7 days'),
('Семёнов Илья Михайлович', TRUE,  NOW() - INTERVAL '14 days'),
('Егоров Антон Юрьевич', TRUE,  NOW() - INTERVAL '33 days'),
('Павлов Роман Олегович', TRUE,  NOW() - INTERVAL '120 days'),
('Соколов Глеб Дмитриевич', TRUE,  NOW() - INTERVAL '40 days'),
('Виноградов Тимофей Алексеевич', TRUE,  NOW() - INTERVAL '8 days'),
('Орлов Матвей Александрович', TRUE,  NOW() - INTERVAL '17 days'),
('Андреев Захар Тимофеевич', TRUE,  NOW() - INTERVAL '52 days'),
('Беляев Марк Романович', TRUE,  NOW() - INTERVAL '3 days'),
('Соловьёв Григорий Петрович', TRUE,  NOW() - INTERVAL '74 days'),
('Королёв Платон Кириллович', TRUE,  NOW() - INTERVAL '28 days'),
('Петрова Мария Петровна', TRUE,  NOW() - INTERVAL '19 days'),
('Смирнова Елена Викторовна', TRUE,  NOW() - INTERVAL '46 days'),
('Соколова Татьяна Сергеевна', TRUE,  NOW() - INTERVAL '11 days'),
('Лебедева Ирина Алексеевна', TRUE,  NOW() - INTERVAL '6 days'),
('Морозова Юлия Александровна', TRUE,  NOW() - INTERVAL '85 days'),
('Михайлова Полина Романовна', TRUE,  NOW() - INTERVAL '23 days'),
('Романов Кирилл Германович', TRUE,  NOW() - INTERVAL '55 days'),
('Антонов Денис Леонидович', TRUE,  NOW() - INTERVAL '17 days'),
('Зайцев Сергей Михайлович', TRUE,  NOW() - INTERVAL '9 days'),
('Козлов Степан Петрович', FALSE, NULL),
('Никитин Артемий Никитич', FALSE, NULL),
('Макаров Лев Юрьевич', FALSE, NULL),
('Тарасов Михаил Дмитриевич', FALSE, NULL),
('Куликов Анатолий Игнатьевич', FALSE, NULL),
('Кузнецова Ольга Андреевна', FALSE, NULL),
('Попова Наталья Михайловна', FALSE, NULL),
('Полякова Софья Игоревна', FALSE, NULL),
('Маркин Богдан Олегович', FALSE, NULL),
('Соболев Виталий Эдуардович', FALSE, NULL)
ON CONFLICT (full_name) DO NOTHING;

INSERT INTO appeal_event2 (full_name, is_done, done_at) VALUES
('Васильев Андрей Сергеевич', FALSE, NULL),
('Иванова Иванна Ивановна', TRUE,  NOW() - INTERVAL '10 days'),
('Иванов Иван Иванович', TRUE,  NOW() - INTERVAL '10 days'),
('Петров Пётр Петрович', TRUE,  NOW() - INTERVAL '5 days'),
('Фёдоров Алексей Николаевич', TRUE,  NOW() - INTERVAL '4 days'),
('Волков Артём Денисович', TRUE,  NOW() - INTERVAL '38 days'),
('Лебедев Кирилл Андреевич', TRUE,  NOW() - INTERVAL '1 day'),
('Семёнов Илья Михайлович', TRUE,  NOW() - INTERVAL '9 days'),
('Егоров Антон Юрьевич', TRUE,  NOW() - INTERVAL '13 days'),
('Орлов Матвей Александрович', TRUE,  NOW() - INTERVAL '7 days'),
('Беляев Марк Романович', TRUE,  NOW() - INTERVAL '2 days'),
('Соловьёв Григорий Петрович', TRUE,  NOW() - INTERVAL '20 days'),
('Петрова Мария Петровна', TRUE,  NOW() - INTERVAL '11 days'),
('Соколова Татьяна Сергеевна', TRUE,  NOW() - INTERVAL '16 days'),
('Михайлова Полина Романовна', TRUE,  NOW() - INTERVAL '8 days'),
('Смирнова Елена Викторовна', TRUE,  NOW() - INTERVAL '14 days'),
('Сидоров Сидор Сидорович', FALSE, NULL),
('Алексеев Максим Игоревич', FALSE, NULL),
('Соколов Глеб Дмитриевич', FALSE, NULL),
('Виноградов Тимофей Алексеевич', FALSE, NULL),
('Андреев Захар Тимофеевич', FALSE, NULL),
('Королёв Платон Кириллович', FALSE, NULL),
('Лебедева Ирина Алексеевна', FALSE, NULL),
('Морозова Юлия Александровна', FALSE, NULL),
('Романов Кирилл Германович', FALSE, NULL),
('Антонов Денис Леонидович', FALSE, NULL),
('Зайцев Сергей Михайлович', FALSE, NULL),
('Морозов Михаил Михайлович', FALSE, NULL)
ON CONFLICT (full_name) DO NOTHING;

\echo '== Результат: список таблиц + расширений =='
\dt
\dx
