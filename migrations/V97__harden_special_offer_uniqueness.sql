CREATE UNIQUE INDEX idx_special_offers_user_active_task
ON special_offers (user_id, task_id)
WHERE deleted_at IS NULL AND task_id IS NOT NULL;

CREATE UNIQUE INDEX idx_special_offers_user_active_habit
ON special_offers (user_id, habit_id)
WHERE deleted_at IS NULL AND habit_id IS NOT NULL;

CREATE UNIQUE INDEX idx_special_offers_user_active_reward
ON special_offers (user_id, reward_id)
WHERE deleted_at IS NULL AND reward_id IS NOT NULL;
