ALTER TABLE earnables
ADD COLUMN permanent_adjustment_multiplier DOUBLE PRECISION;

ALTER TABLE rewards
ADD COLUMN permanent_adjustment_multiplier DOUBLE PRECISION;

ALTER TABLE trades
ADD COLUMN one_time_adjustment_multiplier DOUBLE PRECISION;

ALTER TABLE earnables
ADD CONSTRAINT chk_earnables_permanent_adjustment_multiplier
CHECK (
    permanent_adjustment_multiplier IS NULL
    OR (
        permanent_adjustment_multiplier >= 0.0::DOUBLE PRECISION
        AND permanent_adjustment_multiplier <= 1000.0::DOUBLE PRECISION
    )
);

ALTER TABLE rewards
ADD CONSTRAINT chk_rewards_permanent_adjustment_multiplier
CHECK (
    permanent_adjustment_multiplier IS NULL
    OR (
        permanent_adjustment_multiplier >= 0.0::DOUBLE PRECISION
        AND permanent_adjustment_multiplier <= 1000.0::DOUBLE PRECISION
    )
);

ALTER TABLE trades
ADD CONSTRAINT chk_trades_one_time_adjustment_multiplier
CHECK (
    one_time_adjustment_multiplier IS NULL
    OR (
        one_time_adjustment_multiplier >= 0.0::DOUBLE PRECISION
        AND one_time_adjustment_multiplier <= 1000.0::DOUBLE PRECISION
    )
);
