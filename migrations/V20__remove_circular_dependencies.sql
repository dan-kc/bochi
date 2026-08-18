ALTER TABLE task_dependencies
ADD CONSTRAINT check_task_id_diff_depends_on_task_id CHECK (task_id <> depends_on_task_id);
