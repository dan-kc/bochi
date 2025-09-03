ALTER TABLE trades
ADD COLUMN habit_id INT,
ADD CONSTRAINT fk_habit_id FOREIGN KEY (habit_id) REFERENCES habits(id),
ADD CONSTRAINT fk_user_id FOREIGN KEY (user_id) REFERENCES users(id);
