ALTER TABLE tags
DROP CONSTRAINT unique_user_id_name;

CREATE UNIQUE INDEX unique_active_tag_name_per_user
ON tags (user_id, name)
WHERE deleted_at IS NULL;
