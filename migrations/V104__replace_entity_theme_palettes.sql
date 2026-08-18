ALTER TABLE users
    ADD COLUMN theme_palette_main VARCHAR(32) NOT NULL DEFAULT 'paperPorcelain',
    ADD COLUMN theme_palette_accent VARCHAR(32) NOT NULL DEFAULT 'semantic';

UPDATE users
SET theme_palette_main = CASE
        WHEN theme_palette_neutral = 'paper' THEN 'paperPorcelain'
        ELSE theme_palette_neutral
    END,
    theme_palette_accent = 'semantic';

ALTER TABLE users
    DROP CONSTRAINT chk_users_theme_palette_neutral,
    DROP CONSTRAINT chk_users_theme_palette_task,
    DROP CONSTRAINT chk_users_theme_palette_habit,
    DROP CONSTRAINT chk_users_theme_palette_reward,
    DROP CONSTRAINT chk_users_theme_palette_settings;

ALTER TABLE users
    DROP COLUMN theme_palette_neutral,
    DROP COLUMN theme_palette_task,
    DROP COLUMN theme_palette_habit,
    DROP COLUMN theme_palette_reward,
    DROP COLUMN theme_palette_settings;

ALTER TABLE users
    ADD CONSTRAINT chk_users_theme_palette_main
    CHECK (theme_palette_main IN (
        'paper', 'paperCotton', 'paperPorcelain', 'paperInk',
        'paperYellow', 'paperAmber', 'paperOrange', 'paperTomato', 'paperRed',
        'paperRuby', 'paperCrimson', 'paperPink', 'paperPlum', 'paperPurple', 'paperViolet',
        'paperIris', 'paperIndigo', 'paperBlue', 'paperCyan', 'paperTeal', 'paperJade',
        'paperGreen', 'paperGrass', 'paperLime', 'paperMint', 'paperSky'
    )),
    ADD CONSTRAINT chk_users_theme_palette_accent
    CHECK (theme_palette_accent IN (
        'semantic',
        'paper', 'paperCotton', 'paperPorcelain', 'paperInk',
        'paperYellow', 'paperAmber', 'paperOrange', 'paperTomato', 'paperRed',
        'paperRuby', 'paperCrimson', 'paperPink', 'paperPlum', 'paperPurple', 'paperViolet',
        'paperIris', 'paperIndigo', 'paperBlue', 'paperCyan', 'paperTeal', 'paperJade',
        'paperGreen', 'paperGrass', 'paperLime', 'paperMint', 'paperSky'
    ));
