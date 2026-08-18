CREATE TABLE IF NOT EXISTS rewards (
  id SERIAL PRIMARY KEY,
  user_id INT NOT NULL,
  name VARCHAR(100) NOT NULL,
  description VARCHAR(16384) NOT NULL,
  created_at TIMESTAMP NOT NULL,
  deleted_at TIMESTAMP,
  hidden_until TIMESTAMP,
  max_daily_freqency FLOAT
);

ALTER TABLE tasks
ALTER COLUMN description SET NOT NULL;
