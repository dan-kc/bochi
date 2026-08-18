ALTER TABLE users
DROP COLUMN premium,
ADD COLUMN subscription_product_id VARCHAR(255),
ADD COLUMN app_store_latest_transaction_id VARCHAR(255),
ADD COLUMN app_store_environment VARCHAR(20);

ALTER TABLE users
ADD CONSTRAINT users_app_store_environment_check
CHECK (
    app_store_environment IS NULL
    OR app_store_environment IN ('sandbox', 'production')
);

CREATE UNIQUE INDEX users_app_store_original_transaction_id_key
ON users (app_store_original_transaction_id)
WHERE app_store_original_transaction_id IS NOT NULL;

CREATE INDEX users_subscription_status_idx
ON users (subscription_status);
