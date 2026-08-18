ALTER TABLE users
DROP CONSTRAINT users_app_store_environment_check;

ALTER TABLE users
ADD CONSTRAINT users_app_store_environment_check
CHECK (
    app_store_environment IS NULL
    OR app_store_environment IN ('sandbox', 'production', 'xcode')
);

CREATE TABLE premium_entitlements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    source VARCHAR(10) NOT NULL,
    status VARCHAR(20) NOT NULL,
    product_id VARCHAR(255),
    expires_at TIMESTAMP,
    app_store_original_transaction_id VARCHAR(255),
    app_store_latest_transaction_id VARCHAR(255),
    app_store_environment VARCHAR(20),
    external_billing_customer_id VARCHAR(255),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP,
    CHECK (source IN ('apple', 'web')),
    CHECK (
        status IN (
            'none',
            'active',
            'grace_period',
            'billing_retry',
            'expired',
            'revoked'
        )
    ),
    CHECK (
        app_store_environment IS NULL
        OR app_store_environment IN ('sandbox', 'production', 'xcode')
    )
);

CREATE TRIGGER update_premium_entitlements_updated_at
BEFORE UPDATE ON premium_entitlements
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();

CREATE UNIQUE INDEX premium_entitlements_apple_original_transaction_id_key
ON premium_entitlements (app_store_original_transaction_id)
WHERE source = 'apple'
  AND app_store_original_transaction_id IS NOT NULL
  AND deleted_at IS NULL;

CREATE INDEX premium_entitlements_user_id_idx
ON premium_entitlements (user_id)
WHERE deleted_at IS NULL;

CREATE INDEX premium_entitlements_status_idx
ON premium_entitlements (status)
WHERE deleted_at IS NULL;

CREATE TABLE apple_server_notifications (
    notification_uuid VARCHAR(255) PRIMARY KEY,
    notification_type VARCHAR(255),
    subtype VARCHAR(255),
    original_transaction_id VARCHAR(255),
    latest_transaction_id VARCHAR(255),
    product_id VARCHAR(255),
    environment VARCHAR(20),
    payload_hash VARCHAR(64) NOT NULL,
    processed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO premium_entitlements (
    user_id,
    source,
    status,
    product_id,
    expires_at,
    app_store_original_transaction_id,
    app_store_latest_transaction_id,
    app_store_environment,
    external_billing_customer_id
)
SELECT
    id,
    subscription_source,
    subscription_status,
    subscription_product_id,
    subscription_expires_at,
    app_store_original_transaction_id,
    app_store_latest_transaction_id,
    app_store_environment,
    external_billing_customer_id
FROM users
WHERE subscription_source IS NOT NULL;
