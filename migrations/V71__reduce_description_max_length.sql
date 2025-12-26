-- Reduce description max length from 16384 to 10000 characters for tasks and rewards tables
ALTER TABLE tasks ALTER COLUMN description TYPE character varying(10000);
ALTER TABLE rewards ALTER COLUMN description TYPE character varying(10000);
