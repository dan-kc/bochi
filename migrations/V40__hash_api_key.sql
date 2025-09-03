ALTER TABLE api_keys
ADD COLUMN name VARCHAR(32);
ALTER TABLE api_keys
DROP CONSTRAINT api_keys_pkey;
ALTER TABLE api_keys
RENAME COLUMN id TO key;
ALTER TABLE api_keys
ADD CONSTRAINT api_keys_pkey PRIMARY KEY (name, key);
