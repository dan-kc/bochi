ALTER TABLE task_tags
ADD CONSTRAINT unique_task_id_tag_id UNIQUE (task_id, tag_id);
