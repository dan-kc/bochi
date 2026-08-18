-- Add nullable difficulty_rank column for lexicographic ordering
ALTER TABLE tasks ADD COLUMN difficulty_rank VARCHAR(255) NULL;

-- Create partial index for efficient ordering queries (only non-NULL values)
CREATE INDEX idx_tasks_difficulty_rank ON tasks (user_id, difficulty_rank) WHERE difficulty_rank IS NOT NULL;
