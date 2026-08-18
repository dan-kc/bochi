UPDATE trades refund
SET deleted_at = original.deleted_at
FROM trades original
WHERE refund.refunds_trade_id = original.id
  AND original.deleted_at IS NOT NULL
  AND refund.deleted_at IS NULL;
