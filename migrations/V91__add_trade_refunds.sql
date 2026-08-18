ALTER TABLE trades
ADD COLUMN refunded_at TIMESTAMP;

DROP INDEX IF EXISTS trades_user_id_active_idx;

CREATE INDEX trades_user_id_active_idx
ON trades (user_id)
WHERE deleted_at IS NULL AND refunded_at IS NULL;
