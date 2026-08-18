ALTER TABLE trades
ALTER COLUMN created_at SET NOT NULL;

ALTER TABLE trades
ADD COLUMN reward_id INT NULL;

ALTER TABLE trades
DROP COLUMN user_id;

ALTER TABLE trades
ADD CONSTRAINT trades_reward_id_fkey
FOREIGN KEY (reward_id) REFERENCES rewards(id) ON DELETE CASCADE;
