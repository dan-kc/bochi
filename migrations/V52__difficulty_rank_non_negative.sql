ALTER TABLE tasks
ADD CONSTRAINT difficulty_rank_non_negative CHECK (difficulty_rank >= 0);
