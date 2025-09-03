-- Step 1: Add user_id column as nullable
ALTER TABLE sessions
ADD COLUMN user_id INT;

-- Step 2: Update user_id based on username
UPDATE sessions
SET user_id = users.id
FROM users
WHERE sessions.username = users.username;

-- Step 3: Set user_id column to NOT NULL
ALTER TABLE sessions
ALTER COLUMN user_id SET NOT NULL;

-- Step 4: Add foreign key constraint
ALTER TABLE sessions
ADD CONSTRAINT fk_user
FOREIGN KEY (user_id)
REFERENCES users (id);

-- Step 5: Drop username column
ALTER TABLE sessions
DROP COLUMN username;
