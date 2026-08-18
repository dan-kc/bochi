ALTER TABLE rewards ADD COLUMN recurring BOOLEAN;

UPDATE rewards
SET recurring = TRUE;

ALTER TABLE rewards ALTER COLUMN recurring SET NOT NULL;
ALTER TABLE rewards ALTER COLUMN recurring SET DEFAULT TRUE;

ALTER TABLE rewards
ADD CONSTRAINT chk_rewards_one_off_shape CHECK (
    recurring OR max_daily_frequency IS NULL
);

CREATE INDEX idx_rewards_user_recurring_created
ON rewards (user_id, recurring, created_at, id);

CREATE INDEX idx_rewards_user_recurring_updated
ON rewards (user_id, recurring, updated_at);
