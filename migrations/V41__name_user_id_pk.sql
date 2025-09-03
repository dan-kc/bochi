ALTER TABLE api_keys
DROP CONSTRAINT api_keys_pkey;
ALTER TABLE api_keys
ADD CONSTRAINT api_keys_pkey PRIMARY KEY (name, user_id);
