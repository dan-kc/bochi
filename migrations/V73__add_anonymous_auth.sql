-- Add anonymous auth support
-- Anonymous users have device_id but no email/password until they claim their account

-- Add is_anonymous flag (existing users are not anonymous)
ALTER TABLE users ADD COLUMN is_anonymous BOOLEAN NOT NULL DEFAULT false;

-- Add device_id for anonymous users (unique identifier)
ALTER TABLE users ADD COLUMN device_id UUID;

-- Create unique index on device_id (only for non-null values)
CREATE UNIQUE INDEX users_device_id_key ON users (device_id) WHERE device_id IS NOT NULL;

-- Make email nullable (anonymous users don't have email)
ALTER TABLE users ALTER COLUMN email DROP NOT NULL;

-- Make password nullable (anonymous users don't have password)
ALTER TABLE users ALTER COLUMN password DROP NOT NULL;

-- Add check constraint: non-anonymous users must have email and password
ALTER TABLE users ADD CONSTRAINT users_non_anonymous_has_credentials
    CHECK (is_anonymous = true OR (email IS NOT NULL AND password IS NOT NULL));

-- Add check constraint: anonymous users must have device_id
ALTER TABLE users ADD CONSTRAINT users_anonymous_has_device_id
    CHECK (is_anonymous = false OR device_id IS NOT NULL);
