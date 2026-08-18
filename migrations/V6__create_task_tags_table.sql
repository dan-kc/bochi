CREATE TABLE IF NOT EXISTS task_tags (
    task_id INT NOT NULL,
    tag_id INT NOT NULL,

    PRIMARY KEY (task_id, tag_id),
    FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE,
    FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
);
