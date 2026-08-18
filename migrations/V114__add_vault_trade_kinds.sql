ALTER TABLE trades
ADD COLUMN trade_kind TEXT;

UPDATE trades
SET trade_kind = CASE
    WHEN task_id IS NOT NULL THEN 'taskCompletion'
    WHEN habit_id IS NOT NULL THEN 'habitCompletion'
    WHEN reward_id IS NOT NULL THEN 'rewardPurchase'
    ELSE 'habitCompletion'
END;

ALTER TABLE trades
ALTER COLUMN trade_kind SET NOT NULL;

ALTER TABLE trades
ADD COLUMN vault_interest_day DATE;

ALTER TABLE trades
DROP CONSTRAINT IF EXISTS check_trade_task_habit_or_reward;

ALTER TABLE trades
ADD CONSTRAINT chk_trades_trade_kind
CHECK (
    trade_kind IN (
        'taskCompletion',
        'habitCompletion',
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
        AND habit_id IS NULL
        AND reward_id IS NULL
    )
    OR (
        trade_kind = 'habitCompletion'
        AND task_id IS NULL
        AND habit_id IS NOT NULL
        AND reward_id IS NULL
    )
    OR (
        trade_kind IN ('rewardPurchase', 'vaultRewardPurchase')
        AND task_id IS NULL
        AND habit_id IS NULL
        AND reward_id IS NOT NULL
    )
    OR (
        trade_kind IN ('vaultDeposit', 'vaultInterest')
        AND task_id IS NULL
        AND habit_id IS NULL
        AND reward_id IS NULL
    )
);

ALTER TABLE trades
ADD CONSTRAINT chk_trades_vault_interest_day_shape
CHECK (
    (trade_kind = 'vaultInterest' AND vault_interest_day IS NOT NULL)
    OR (trade_kind <> 'vaultInterest' AND vault_interest_day IS NULL)
);

CREATE INDEX trades_user_trade_kind_active_idx
ON trades (user_id, trade_kind)
WHERE deleted_at IS NULL;

CREATE UNIQUE INDEX trades_user_vault_interest_day_active_idx
ON trades (user_id, vault_interest_day)
WHERE deleted_at IS NULL
  AND trade_kind = 'vaultInterest'
  AND vault_interest_day IS NOT NULL;
