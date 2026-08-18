ALTER TABLE users
ADD COLUMN apple_user_id VARCHAR(255);

CREATE UNIQUE INDEX users_apple_user_id_key
ON users (apple_user_id)
WHERE apple_user_id IS NOT NULL;
