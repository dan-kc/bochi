ALTER TABLE users
DROP COLUMN tofu_balance;

CREATE INDEX trades_user_id_active_idx
ON trades (user_id)
WHERE deleted_at IS NULL;
