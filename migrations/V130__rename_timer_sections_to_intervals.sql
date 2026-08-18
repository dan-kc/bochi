ALTER TABLE timers
RENAME COLUMN sections TO intervals;

ALTER TABLE timers
RENAME CONSTRAINT chk_timers_sections_array TO chk_timers_intervals_array;

ALTER TABLE timers
RENAME CONSTRAINT chk_timers_sections_not_empty TO chk_timers_intervals_not_empty;
