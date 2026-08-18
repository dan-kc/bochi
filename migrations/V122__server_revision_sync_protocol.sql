CREATE TABLE user_sync_state (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    revision BIGINT NOT NULL DEFAULT 0
);

INSERT INTO user_sync_state (user_id, revision)
SELECT id, 0
FROM users
ON CONFLICT (user_id) DO NOTHING;

ALTER TABLE tasks ADD COLUMN server_revision BIGINT NOT NULL DEFAULT 0;
ALTER TABLE rewards ADD COLUMN server_revision BIGINT NOT NULL DEFAULT 0;
ALTER TABLE trades ADD COLUMN server_revision BIGINT NOT NULL DEFAULT 0;
ALTER TABLE tags ADD COLUMN server_revision BIGINT NOT NULL DEFAULT 0;
ALTER TABLE task_tags ADD COLUMN server_revision BIGINT NOT NULL DEFAULT 0;
ALTER TABLE habit_tags ADD COLUMN server_revision BIGINT NOT NULL DEFAULT 0;
ALTER TABLE reward_tags ADD COLUMN server_revision BIGINT NOT NULL DEFAULT 0;
ALTER TABLE task_task_dependencies ADD COLUMN server_revision BIGINT NOT NULL DEFAULT 0;
ALTER TABLE task_habit_dependencies ADD COLUMN server_revision BIGINT NOT NULL DEFAULT 0;
ALTER TABLE reward_task_dependencies ADD COLUMN server_revision BIGINT NOT NULL DEFAULT 0;
ALTER TABLE reward_habit_dependencies ADD COLUMN server_revision BIGINT NOT NULL DEFAULT 0;
ALTER TABLE timers ADD COLUMN server_revision BIGINT NOT NULL DEFAULT 0;

CREATE INDEX idx_tasks_user_revision ON tasks(user_id, server_revision);
CREATE INDEX idx_rewards_user_revision ON rewards(user_id, server_revision);
CREATE INDEX idx_trades_user_revision ON trades(user_id, server_revision);
CREATE INDEX idx_tags_user_revision ON tags(user_id, server_revision);
CREATE INDEX idx_timers_user_revision ON timers(user_id, server_revision);
CREATE INDEX idx_task_tags_revision ON task_tags(server_revision);
CREATE INDEX idx_habit_tags_revision ON habit_tags(server_revision);
CREATE INDEX idx_reward_tags_revision ON reward_tags(server_revision);
CREATE INDEX idx_task_task_dependencies_revision ON task_task_dependencies(server_revision);
CREATE INDEX idx_task_habit_dependencies_revision ON task_habit_dependencies(server_revision);
CREATE INDEX idx_reward_task_dependencies_revision ON reward_task_dependencies(server_revision);
CREATE INDEX idx_reward_habit_dependencies_revision ON reward_habit_dependencies(server_revision);

CREATE TABLE sync_changes (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    revision BIGINT NOT NULL,
    entity_kind TEXT NOT NULL,
    entity_id TEXT NOT NULL,
    operation_id UUID,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, revision, entity_kind, entity_id)
);

CREATE INDEX idx_sync_changes_user_revision ON sync_changes(user_id, revision);
CREATE INDEX idx_sync_changes_operation ON sync_changes(user_id, operation_id)
WHERE operation_id IS NOT NULL;

CREATE TABLE processed_sync_operations (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    operation_id UUID NOT NULL,
    revision BIGINT NOT NULL,
    response_json JSONB NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, operation_id)
);
