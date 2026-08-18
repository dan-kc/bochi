ALTER TABLE apple_server_notifications
ADD COLUMN subscription_status VARCHAR(20),
ADD COLUMN expires_at TIMESTAMP;

ALTER TABLE apple_server_notifications
ADD CONSTRAINT apple_server_notifications_subscription_status_check
CHECK (
    subscription_status IS NULL
    OR subscription_status IN (
        'none',
        'active',
        'grace_period',
        'billing_retry',
        'expired',
        'revoked'
    )
);

CREATE INDEX apple_server_notifications_original_transaction_processed_idx
ON apple_server_notifications (original_transaction_id, processed_at DESC)
WHERE original_transaction_id IS NOT NULL;
