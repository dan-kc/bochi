ALTER TABLE users
ADD COLUMN subscription_source VARCHAR(10),
ADD COLUMN subscription_status VARCHAR(20) NOT NULL DEFAULT 'none',
ADD COLUMN subscription_expires_at TIMESTAMP,
ADD COLUMN app_store_original_transaction_id VARCHAR(255),
ADD COLUMN external_billing_customer_id VARCHAR(255);

ALTER TABLE users
ADD CONSTRAINT users_subscription_source_check
CHECK (
    subscription_source IS NULL
    OR subscription_source IN ('apple', 'web')
);

ALTER TABLE users
ADD CONSTRAINT users_subscription_status_check
CHECK (
    subscription_status IN (
        'none',
        'active',
        'grace_period',
        'billing_retry',
        'expired',
        'revoked'
    )
);
