ALTER TABLE trades
DROP CONSTRAINT IF EXISTS chk_trades_trade_kind;

ALTER TABLE trades
DROP CONSTRAINT IF EXISTS check_trade_source_shape;

ALTER TABLE trades
RENAME COLUMN habit_id TO recurring_task_id;

UPDATE trades
SET trade_kind = 'recurringTaskCompletion'
WHERE trade_kind = 'habitCompletion';

ALTER TABLE trades
ADD CONSTRAINT chk_trades_trade_kind
CHECK (
    trade_kind IN (
        'taskCompletion',
        'recurringTaskCompletion',
        'rewardPurchase',
        'vaultDeposit',
        'vaultInterest',
        'vaultRewardPurchase'
    )
);

ALTER TABLE trades
ADD CONSTRAINT check_trade_source_shape
CHECK (
    (
        trade_kind = 'taskCompletion'
        AND task_id IS NOT NULL
        AND recurring_task_id IS NULL
        AND reward_id IS NULL
    )
    OR (
        trade_kind = 'recurringTaskCompletion'
        AND task_id IS NULL
        AND recurring_task_id IS NOT NULL
        AND reward_id IS NULL
    )
    OR (
        trade_kind IN ('rewardPurchase', 'vaultRewardPurchase')
        AND task_id IS NULL
        AND recurring_task_id IS NULL
        AND reward_id IS NOT NULL
    )
    OR (
        trade_kind IN ('vaultDeposit', 'vaultInterest')
        AND task_id IS NULL
        AND recurring_task_id IS NULL
        AND reward_id IS NULL
    )
);

ALTER TABLE habit_tags
RENAME TO recurring_task_tags;

ALTER TABLE recurring_task_tags
RENAME COLUMN habit_id TO recurring_task_id;

ALTER TABLE task_habit_dependencies
RENAME TO task_recurring_task_dependencies;

ALTER TABLE task_recurring_task_dependencies
RENAME COLUMN habit_id TO recurring_task_id;

ALTER TABLE reward_habit_dependencies
RENAME TO reward_recurring_task_dependencies;

ALTER TABLE reward_recurring_task_dependencies
RENAME COLUMN habit_id TO recurring_task_id;

ALTER INDEX IF EXISTS idx_habit_tags_revision
RENAME TO idx_recurring_task_tags_revision;

ALTER INDEX IF EXISTS idx_task_habit_dependencies_revision
RENAME TO idx_task_recurring_task_dependencies_revision;

ALTER INDEX IF EXISTS idx_reward_habit_dependencies_revision
RENAME TO idx_reward_recurring_task_dependencies_revision;

ALTER INDEX IF EXISTS idx_task_habit_dependencies_updated
RENAME TO idx_task_recurring_task_dependencies_updated;

ALTER INDEX IF EXISTS idx_task_habit_dependencies_habit
RENAME TO idx_task_recurring_task_dependencies_recurring_task;

ALTER INDEX IF EXISTS idx_reward_habit_dependencies_updated
RENAME TO idx_reward_recurring_task_dependencies_updated;

ALTER INDEX IF EXISTS idx_reward_habit_dependencies_habit
RENAME TO idx_reward_recurring_task_dependencies_recurring_task;

ALTER TRIGGER update_habit_tags_updated_at ON recurring_task_tags
RENAME TO update_recurring_task_tags_updated_at;

ALTER TRIGGER update_task_habit_dependencies_updated_at ON task_recurring_task_dependencies
RENAME TO update_task_recurring_task_dependencies_updated_at;

ALTER TRIGGER update_reward_habit_dependencies_updated_at ON reward_recurring_task_dependencies
RENAME TO update_reward_recurring_task_dependencies_updated_at;
