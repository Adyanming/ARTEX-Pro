CREATE TABLE IF NOT EXISTS task_schedules (
    id                 BIGSERIAL PRIMARY KEY,
    name               TEXT NOT NULL,
    enabled            BOOLEAN NOT NULL DEFAULT true,
    timezone_mode      TEXT NOT NULL DEFAULT 'beijing'
                       CHECK (timezone_mode IN ('beijing','system')),
    schedule_type      TEXT NOT NULL DEFAULT 'weekly'
                       CHECK (schedule_type IN ('once','weekly')),
    run_date           DATE,
    end_date           DATE,
    weekdays           TEXT NOT NULL DEFAULT '',
    start_time         TIME NOT NULL,
    end_time           TIME,
    start_immediately  BOOLEAN NOT NULL DEFAULT false,
    status             TEXT NOT NULL DEFAULT 'waiting'
                       CHECK (status IN ('waiting','running','outside','completed','error','paused')),
    last_window_key    TEXT NOT NULL DEFAULT '',
    last_transition_at TIMESTAMPTZ,
    last_error         TEXT NOT NULL DEFAULT '',
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK ((schedule_type = 'once' AND run_date IS NOT NULL) OR
           (schedule_type = 'weekly' AND run_date IS NULL)),
    CHECK ((schedule_type = 'once') OR weekdays <> '')
);
CREATE INDEX IF NOT EXISTS idx_task_schedules_enabled ON task_schedules(enabled, id);
ALTER TABLE task_schedules ADD COLUMN IF NOT EXISTS end_date DATE;
DROP TRIGGER IF EXISTS trg_task_schedules_upd ON task_schedules;
CREATE TRIGGER trg_task_schedules_upd BEFORE UPDATE ON task_schedules
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS task_schedule_tasks (
    schedule_id BIGINT NOT NULL REFERENCES task_schedules(id) ON DELETE CASCADE,
    task_id     BIGINT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    paused_by_schedule BOOLEAN NOT NULL DEFAULT false,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (schedule_id, task_id)
);
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS schedule_paused BOOLEAN NOT NULL DEFAULT false;
CREATE INDEX IF NOT EXISTS idx_task_schedule_tasks_task ON task_schedule_tasks(task_id);
ALTER TABLE task_schedule_tasks ADD COLUMN IF NOT EXISTS paused_by_schedule BOOLEAN NOT NULL DEFAULT false;


CREATE TABLE IF NOT EXISTS finding_cases (
    id BIGSERIAL PRIMARY KEY,
    task_id BIGINT REFERENCES tasks(id) ON DELETE SET NULL,
    origin_task_id BIGINT NOT NULL,
    title TEXT NOT NULL,
    reason TEXT NOT NULL,
    severity TEXT NOT NULL DEFAULT '',
    severity_reason TEXT NOT NULL DEFAULT '',
    report TEXT NOT NULL DEFAULT '',
    version BIGINT NOT NULL DEFAULT 1,
    report_version BIGINT NOT NULL DEFAULT 0,
    active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS finding_case_members (
    finding_id BIGINT PRIMARY KEY REFERENCES findings(id) ON DELETE CASCADE,
    case_id BIGINT NOT NULL REFERENCES finding_cases(id),
    joined_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_finding_case_members_case ON finding_case_members(case_id);
CREATE TABLE IF NOT EXISTS finding_case_events (
    id BIGSERIAL PRIMARY KEY,
    case_id BIGINT NOT NULL REFERENCES finding_cases(id),
    action TEXT NOT NULL,
    actor TEXT NOT NULL,
    reason TEXT NOT NULL,
    finding_ids JSONB NOT NULL DEFAULT '[]',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS finding_case_suggestions (
    id BIGSERIAL PRIMARY KEY,
    task_id BIGINT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    left_id BIGINT NOT NULL REFERENCES findings(id) ON DELETE CASCADE,
    right_id BIGINT NOT NULL REFERENCES findings(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    reason TEXT NOT NULL,
    state TEXT NOT NULL DEFAULT 'pending',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(left_id,right_id),
    CHECK(left_id < right_id)
);
CREATE TABLE IF NOT EXISTS finding_case_blocks (
    left_id BIGINT NOT NULL REFERENCES findings(id) ON DELETE CASCADE,
    right_id BIGINT NOT NULL REFERENCES findings(id) ON DELETE CASCADE,
    reason TEXT NOT NULL,
    PRIMARY KEY(left_id,right_id), CHECK(left_id < right_id)
);
CREATE OR REPLACE FUNCTION finding_case_changed() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE cid BIGINT; remaining INTEGER;
BEGIN
    IF TG_TABLE_NAME = 'findings' THEN
        IF OLD IS NOT DISTINCT FROM NEW THEN RETURN NEW; END IF;
        SELECT case_id INTO cid FROM finding_case_members WHERE finding_id=NEW.id;
    ELSE
        cid := OLD.case_id;
    END IF;
    IF cid IS NOT NULL THEN
        UPDATE finding_cases SET version=version+1 WHERE id=cid;
        IF TG_OP='DELETE' THEN
            SELECT count(*) INTO remaining FROM finding_case_members WHERE case_id=cid;
            INSERT INTO finding_case_events(case_id,action,actor,reason,finding_ids)
                VALUES(cid,'member_deleted','system','member removed or deleted',jsonb_build_array(OLD.finding_id));
            IF remaining < 2 THEN
                UPDATE finding_cases SET active=false WHERE id=cid;
                DELETE FROM finding_case_members WHERE case_id=cid;
            END IF;
        END IF;
    END IF;
    RETURN NULL;
END $$;
DROP TRIGGER IF EXISTS finding_case_content_changed ON findings;
CREATE TRIGGER finding_case_content_changed AFTER UPDATE ON findings
FOR EACH ROW EXECUTE FUNCTION finding_case_changed();
DROP TRIGGER IF EXISTS finding_case_member_deleted ON finding_case_members;
CREATE TRIGGER finding_case_member_deleted AFTER DELETE ON finding_case_members
FOR EACH ROW EXECUTE FUNCTION finding_case_changed();
CREATE TABLE IF NOT EXISTS finding_case_review_runs (
    conversation_id BIGINT PRIMARY KEY REFERENCES conversations(id) ON DELETE CASCADE,
    task_id BIGINT REFERENCES tasks(id) ON DELETE SET NULL,
    state TEXT NOT NULL DEFAULT 'queued',
    error TEXT NOT NULL DEFAULT ''
);

ALTER TABLE finding_case_review_runs ADD COLUMN IF NOT EXISTS finding_ids JSONB NOT NULL DEFAULT '[]';

ALTER TABLE finding_case_review_runs ADD COLUMN IF NOT EXISTS reviewed_ids JSONB NOT NULL DEFAULT '[]';
ALTER TABLE finding_case_review_runs ADD COLUMN IF NOT EXISTS conclusion JSONB NOT NULL DEFAULT '{}';
CREATE INDEX IF NOT EXISTS idx_finding_case_reviews_active_task ON finding_case_review_runs(task_id) WHERE state IN ('queued','running');

CREATE TABLE IF NOT EXISTS task_schedule_history (
 id BIGSERIAL PRIMARY KEY,
 schedule_id BIGINT NOT NULL REFERENCES task_schedules(id) ON DELETE CASCADE,
 task_id BIGINT,
 action TEXT NOT NULL,
 success BOOLEAN NOT NULL,
 message TEXT NOT NULL DEFAULT '',
 created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_schedule_history ON task_schedule_history(schedule_id,id DESC);

