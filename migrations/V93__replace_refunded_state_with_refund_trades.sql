ALTER TABLE trades
ADD COLUMN refunds_trade_id UUID;

ALTER TABLE trades
ADD CONSTRAINT trades_refunds_trade_id_fkey
FOREIGN KEY (refunds_trade_id) REFERENCES trades(id) ON DELETE SET NULL;

WITH refunded_trades AS (
    SELECT
        id,
        user_id,
        task_id,
        habit_id,
        reward_id,
        source_name,
        amount,
        refunded_at
    FROM trades
    WHERE refunded_at IS NOT NULL
),
inserted_refunds AS (
    INSERT INTO trades (
        id,
        user_id,
        task_id,
        habit_id,
        reward_id,
        source_name,
        amount,
        created_at,
        updated_at,
        deleted_at,
        refunds_trade_id
    )
    SELECT
        gen_random_uuid(),
        user_id,
        task_id,
        habit_id,
        reward_id,
        source_name,
        -amount,
        refunded_at,
        refunded_at,
        NULL,
        id
    FROM refunded_trades
)
UPDATE trades
SET refunded_at = NULL
WHERE refunded_at IS NOT NULL;

DROP INDEX IF EXISTS trades_user_id_active_idx;

CREATE INDEX trades_user_id_active_idx
ON trades (user_id)
WHERE deleted_at IS NULL;

CREATE INDEX trades_refunds_trade_id_active_idx
ON trades (refunds_trade_id)
WHERE deleted_at IS NULL;
