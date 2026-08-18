CREATE TABLE IF NOT EXISTS task_dependencies (
    task_id INT NOT NULL,
    depends_on_task_id INT NOT NULL,

    PRIMARY KEY (task_id, depends_on_task_id),
    FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE,
    FOREIGN KEY (depends_on_task_id) REFERENCES tasks(id) ON DELETE CASCADE
);
