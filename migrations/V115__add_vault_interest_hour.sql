ALTER TABLE trades
ADD COLUMN vault_interest_hour TIMESTAMP;

UPDATE trades
SET vault_interest_hour = vault_interest_day::timestamp
WHERE trade_kind = 'vaultInterest'
  AND vault_interest_day IS NOT NULL
  AND vault_interest_hour IS NULL;

DROP INDEX IF EXISTS trades_user_vault_interest_day_active_idx;

ALTER TABLE trades
DROP CONSTRAINT IF EXISTS chk_trades_vault_interest_day_shape;

ALTER TABLE trades
ADD CONSTRAINT chk_trades_vault_interest_hour_shape
CHECK (
    (
        trade_kind = 'vaultInterest'
        AND vault_interest_hour IS NOT NULL
    )
    OR (
        trade_kind <> 'vaultInterest'
        AND vault_interest_day IS NULL
        AND vault_interest_hour IS NULL
    )
);

CREATE UNIQUE INDEX trades_user_vault_interest_hour_active_idx
ON trades (user_id, vault_interest_hour)
WHERE deleted_at IS NULL
  AND trade_kind = 'vaultInterest'
  AND vault_interest_hour IS NOT NULL;
