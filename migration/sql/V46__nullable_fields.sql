ALTER TABLE refresh_tokens ALTER COLUMN is_api_key SET NOT NULL;
ALTER TABLE refresh_tokens ALTER COLUMN name SET NOT NULL;
ALTER TABLE refresh_tokens ALTER COLUMN expires_at DROP NOT NULL;
