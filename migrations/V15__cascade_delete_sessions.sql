-- Drop the existing foreign key constraint
ALTER TABLE sessions DROP CONSTRAINT fk_user;

-- Add a new foreign key constraint with ON DELETE CASCADE
ALTER TABLE sessions
ADD CONSTRAINT fk_user
FOREIGN KEY (user_id)
REFERENCES users(id)
ON DELETE CASCADE;
