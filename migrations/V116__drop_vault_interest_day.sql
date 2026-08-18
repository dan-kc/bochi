ALTER TABLE trades
DROP CONSTRAINT IF EXISTS chk_trades_vault_interest_hour_shape;

ALTER TABLE trades
DROP COLUMN IF EXISTS vault_interest_day;

ALTER TABLE trades
ADD CONSTRAINT chk_trades_vault_interest_hour_shape
CHECK (
    (
        trade_kind = 'vaultInterest'
        AND vault_interest_hour IS NOT NULL
    )
    OR (
        trade_kind <> 'vaultInterest'
        AND vault_interest_hour IS NULL
    )
);
