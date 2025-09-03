CREATE TABLE IF NOT EXISTS habits (
    id SERIAL PRIMARY KEY,
    user_id INT NOT NULL,
    name VARCHAR(100) NOT NULL,
    hidden_until TIMESTAMP,
    created_at TIMESTAMP NOT NULL,
    deleted_at TIMESTAMP,
    difficulty INT NOT NULL,
    importance INT NOT NULL,
    time_commitment INT NOT NULL,
    daily_desired_frequency INT NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);
