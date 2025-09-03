ALTER TABLE refresh_tokens
RENAME COLUMN id TO key;
ALTER TABLE refresh_tokens
DROP CONSTRAINT sessions_pkey;
ALTER TABLE refresh_tokens
ADD CONSTRAINT refresh_tokens_pkey PRIMARY KEY (name, user_id);
