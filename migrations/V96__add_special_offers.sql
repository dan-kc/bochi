CREATE TABLE special_offers (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL,
    task_id UUID,
    habit_id UUID,
    reward_id UUID,
    modifier_percent SMALLINT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP,
    expires_at TIMESTAMP NOT NULL,
    CONSTRAINT fk_special_offers_user
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT fk_special_offers_task
        FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE,
    CONSTRAINT fk_special_offers_habit
        FOREIGN KEY (habit_id) REFERENCES habits(id) ON DELETE CASCADE,
    CONSTRAINT fk_special_offers_reward
        FOREIGN KEY (reward_id) REFERENCES rewards(id) ON DELETE CASCADE,
    CONSTRAINT chk_special_offers_single_target
        CHECK (
            (CASE WHEN task_id IS NOT NULL THEN 1 ELSE 0 END) +
            (CASE WHEN habit_id IS NOT NULL THEN 1 ELSE 0 END) +
            (CASE WHEN reward_id IS NOT NULL THEN 1 ELSE 0 END) = 1
        ),
    CONSTRAINT chk_special_offers_modifier_percent
        CHECK (modifier_percent IN (-50, -40, -30, 30, 40, 50)),
    CONSTRAINT chk_special_offers_direction_matches_target
        CHECK (
            (task_id IS NOT NULL AND modifier_percent > 0)
            OR (habit_id IS NOT NULL AND modifier_percent > 0)
            OR (reward_id IS NOT NULL AND modifier_percent < 0)
        ),
    CONSTRAINT chk_special_offers_expiry_after_creation
        CHECK (expires_at > created_at)
);

CREATE INDEX idx_special_offers_user_updated
ON special_offers (user_id, updated_at);

CREATE INDEX idx_special_offers_user_deleted
ON special_offers (user_id, deleted_at);

CREATE INDEX idx_special_offers_user_expires
ON special_offers (user_id, expires_at);

CREATE TRIGGER update_special_offers_updated_at
BEFORE UPDATE ON special_offers
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();
