ALTER TABLE trades
ADD COLUMN vault_amount_micro BIGINT;

UPDATE trades
SET vault_amount_micro = CASE
    WHEN trade_kind = 'vaultDeposit' THEN (-amount::bigint * 1000000)
    WHEN trade_kind IN ('vaultInterest', 'vaultRewardPurchase') THEN (amount::bigint * 1000000)
    ELSE NULL
END;

UPDATE trades
SET amount = 0
WHERE trade_kind IN ('vaultInterest', 'vaultRewardPurchase');

ALTER TABLE trades
ADD CONSTRAINT chk_trades_vault_amount_micro_shape
CHECK (
    (
        trade_kind NOT IN ('vaultDeposit', 'vaultInterest', 'vaultRewardPurchase')
        AND vault_amount_micro IS NULL
    )
    OR (
        trade_kind = 'vaultDeposit'
        AND amount < 0
        AND vault_amount_micro = (-amount::bigint * 1000000)
    )
    OR (
        trade_kind = 'vaultInterest'
        AND amount = 0
        AND vault_amount_micro > 0
    )
    OR (
        trade_kind = 'vaultRewardPurchase'
        AND amount = 0
        AND (
            (refunds_trade_id IS NULL AND vault_amount_micro < 0)
            OR (refunds_trade_id IS NOT NULL AND vault_amount_micro > 0)
        )
    )
);
