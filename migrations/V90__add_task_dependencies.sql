CREATE TABLE task_task_dependencies (
    task_id UUID NOT NULL,
    depends_on_task_id UUID NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP,
    PRIMARY KEY (task_id, depends_on_task_id),
    CONSTRAINT fk_task_task_dependencies_task
        FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE,
    CONSTRAINT fk_task_task_dependencies_depends_on_task
        FOREIGN KEY (depends_on_task_id) REFERENCES tasks(id) ON DELETE CASCADE,
    CONSTRAINT chk_task_task_dependencies_not_self
        CHECK (task_id <> depends_on_task_id)
);

CREATE INDEX idx_task_task_dependencies_updated
ON task_task_dependencies (updated_at);

CREATE INDEX idx_task_task_dependencies_depends_on_task
ON task_task_dependencies (depends_on_task_id);

CREATE TRIGGER update_task_task_dependencies_updated_at
BEFORE UPDATE ON task_task_dependencies
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();

CREATE TABLE task_habit_dependencies (
    task_id UUID NOT NULL,
    habit_id UUID NOT NULL,
    required_completions INTEGER NOT NULL,
    baseline_completion_count INTEGER NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP,
    PRIMARY KEY (task_id, habit_id),
    CONSTRAINT fk_task_habit_dependencies_task
        FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE,
    CONSTRAINT fk_task_habit_dependencies_habit
        FOREIGN KEY (habit_id) REFERENCES habits(id) ON DELETE CASCADE,
    CONSTRAINT chk_task_habit_dependencies_required_completions
        CHECK (required_completions > 0),
    CONSTRAINT chk_task_habit_dependencies_baseline_completion_count
        CHECK (baseline_completion_count >= 0)
);

CREATE INDEX idx_task_habit_dependencies_updated
ON task_habit_dependencies (updated_at);

CREATE INDEX idx_task_habit_dependencies_habit
ON task_habit_dependencies (habit_id);

CREATE TRIGGER update_task_habit_dependencies_updated_at
BEFORE UPDATE ON task_habit_dependencies
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();
