UPDATE tasks
SET completed_at = NULL;

CREATE INDEX IF NOT EXISTS trades_task_id_active_source_idx
ON trades (task_id, created_at DESC, updated_at DESC, id DESC)
WHERE task_id IS NOT NULL
  AND deleted_at IS NULL
  AND refunds_trade_id IS NULL;
