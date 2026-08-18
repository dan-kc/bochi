ALTER TABLE trades
ADD COLUMN adjustment_base_amount INTEGER;

ALTER TABLE trades
ADD COLUMN permanent_adjustment_multiplier DOUBLE PRECISION;

ALTER TABLE trades
ADD CONSTRAINT chk_trades_permanent_adjustment_multiplier
CHECK (
    permanent_adjustment_multiplier IS NULL
    OR (
        permanent_adjustment_multiplier >= 0.0::DOUBLE PRECISION
        AND permanent_adjustment_multiplier <= 1000.0::DOUBLE PRECISION
    )
);
