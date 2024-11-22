ALTER TABLE tags
ADD CONSTRAINT unique_user_id_name UNIQUE (user_id, name);
