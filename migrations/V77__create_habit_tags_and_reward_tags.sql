-- Create habit_tags junction table for many-to-many relationship between habits and tags
CREATE TABLE IF NOT EXISTS habit_tags (
    habit_id UUID NOT NULL,
    tag_id UUID NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    deleted_at TIMESTAMP,

    PRIMARY KEY (habit_id, tag_id),
    FOREIGN KEY (habit_id) REFERENCES habits(id) ON DELETE CASCADE,
    FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
);

-- Create trigger for updated_at on habit_tags
CREATE TRIGGER update_habit_tags_updated_at
BEFORE UPDATE ON habit_tags
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();

-- Create reward_tags junction table for many-to-many relationship between rewards and tags
CREATE TABLE IF NOT EXISTS reward_tags (
    reward_id UUID NOT NULL,
    tag_id UUID NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    deleted_at TIMESTAMP,

    PRIMARY KEY (reward_id, tag_id),
    FOREIGN KEY (reward_id) REFERENCES rewards(id) ON DELETE CASCADE,
    FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
);

-- Create trigger for updated_at on reward_tags
CREATE TRIGGER update_reward_tags_updated_at
BEFORE UPDATE ON reward_tags
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();
