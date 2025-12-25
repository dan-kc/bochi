ALTER TABLE users
ADD COLUMN theme_preference VARCHAR(10) NOT NULL DEFAULT 'auto'
CHECK (theme_preference IN ('dark', 'light', 'auto'));
