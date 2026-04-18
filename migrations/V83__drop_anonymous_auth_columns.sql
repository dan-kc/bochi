DROP INDEX IF EXISTS users_device_id_key;

ALTER TABLE users
DROP CONSTRAINT IF EXISTS users_non_anonymous_has_credentials,
DROP CONSTRAINT IF EXISTS users_anonymous_has_device_id,
DROP COLUMN IF EXISTS is_anonymous,
DROP COLUMN IF EXISTS device_id;
