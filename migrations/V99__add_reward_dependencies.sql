CREATE TABLE reward_task_dependencies (
    reward_id UUID NOT NULL,
    depends_on_task_id UUID NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP,
    PRIMARY KEY (reward_id, depends_on_task_id),
    CONSTRAINT fk_reward_task_dependencies_reward
        FOREIGN KEY (reward_id) REFERENCES rewards(id) ON DELETE CASCADE,
    CONSTRAINT fk_reward_task_dependencies_depends_on_task
        FOREIGN KEY (depends_on_task_id) REFERENCES tasks(id) ON DELETE CASCADE
);

CREATE INDEX idx_reward_task_dependencies_updated
ON reward_task_dependencies (updated_at);

CREATE INDEX idx_reward_task_dependencies_depends_on_task
ON reward_task_dependencies (depends_on_task_id);

CREATE TRIGGER update_reward_task_dependencies_updated_at
BEFORE UPDATE ON reward_task_dependencies
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();

CREATE TABLE reward_habit_dependencies (
    reward_id UUID NOT NULL,
    habit_id UUID NOT NULL,
    required_completions INTEGER NOT NULL,
    baseline_completion_count INTEGER NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP,
    PRIMARY KEY (reward_id, habit_id),
    CONSTRAINT fk_reward_habit_dependencies_reward
        FOREIGN KEY (reward_id) REFERENCES rewards(id) ON DELETE CASCADE,
    CONSTRAINT fk_reward_habit_dependencies_habit
        FOREIGN KEY (habit_id) REFERENCES habits(id) ON DELETE CASCADE,
    CONSTRAINT chk_reward_habit_dependencies_required_completions
        CHECK (required_completions > 0),
    CONSTRAINT chk_reward_habit_dependencies_baseline_completion_count
        CHECK (baseline_completion_count >= 0)
);

CREATE INDEX idx_reward_habit_dependencies_updated
ON reward_habit_dependencies (updated_at);

CREATE INDEX idx_reward_habit_dependencies_habit
ON reward_habit_dependencies (habit_id);

CREATE TRIGGER update_reward_habit_dependencies_updated_at
BEFORE UPDATE ON reward_habit_dependencies
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();
