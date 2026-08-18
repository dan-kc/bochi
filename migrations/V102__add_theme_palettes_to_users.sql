ALTER TABLE users
    ADD COLUMN theme_palette_neutral VARCHAR(32) NOT NULL DEFAULT 'paper',
    ADD COLUMN theme_palette_task VARCHAR(32) NOT NULL DEFAULT 'paperBlue',
    ADD COLUMN theme_palette_habit VARCHAR(32) NOT NULL DEFAULT 'paperJade',
    ADD COLUMN theme_palette_reward VARCHAR(32) NOT NULL DEFAULT 'paperTomato',
    ADD COLUMN theme_palette_settings VARCHAR(32) NOT NULL DEFAULT 'paper';

ALTER TABLE users
    ADD CONSTRAINT chk_users_theme_palette_neutral
    CHECK (theme_palette_neutral IN (
        'paper', 'paperYellow', 'paperAmber', 'paperOrange', 'paperTomato', 'paperRed',
        'paperRuby', 'paperCrimson', 'paperPink', 'paperPlum', 'paperPurple', 'paperViolet',
        'paperIris', 'paperIndigo', 'paperBlue', 'paperCyan', 'paperTeal', 'paperJade',
        'paperGreen', 'paperGrass', 'paperLime', 'paperMint', 'paperSky'
    )),
    ADD CONSTRAINT chk_users_theme_palette_task
    CHECK (theme_palette_task IN (
        'paper', 'paperYellow', 'paperAmber', 'paperOrange', 'paperTomato', 'paperRed',
        'paperRuby', 'paperCrimson', 'paperPink', 'paperPlum', 'paperPurple', 'paperViolet',
        'paperIris', 'paperIndigo', 'paperBlue', 'paperCyan', 'paperTeal', 'paperJade',
        'paperGreen', 'paperGrass', 'paperLime', 'paperMint', 'paperSky'
    )),
    ADD CONSTRAINT chk_users_theme_palette_habit
    CHECK (theme_palette_habit IN (
        'paper', 'paperYellow', 'paperAmber', 'paperOrange', 'paperTomato', 'paperRed',
        'paperRuby', 'paperCrimson', 'paperPink', 'paperPlum', 'paperPurple', 'paperViolet',
        'paperIris', 'paperIndigo', 'paperBlue', 'paperCyan', 'paperTeal', 'paperJade',
        'paperGreen', 'paperGrass', 'paperLime', 'paperMint', 'paperSky'
    )),
    ADD CONSTRAINT chk_users_theme_palette_reward
    CHECK (theme_palette_reward IN (
        'paper', 'paperYellow', 'paperAmber', 'paperOrange', 'paperTomato', 'paperRed',
        'paperRuby', 'paperCrimson', 'paperPink', 'paperPlum', 'paperPurple', 'paperViolet',
        'paperIris', 'paperIndigo', 'paperBlue', 'paperCyan', 'paperTeal', 'paperJade',
        'paperGreen', 'paperGrass', 'paperLime', 'paperMint', 'paperSky'
    )),
    ADD CONSTRAINT chk_users_theme_palette_settings
    CHECK (theme_palette_settings IN (
        'paper', 'paperYellow', 'paperAmber', 'paperOrange', 'paperTomato', 'paperRed',
        'paperRuby', 'paperCrimson', 'paperPink', 'paperPlum', 'paperPurple', 'paperViolet',
        'paperIris', 'paperIndigo', 'paperBlue', 'paperCyan', 'paperTeal', 'paperJade',
        'paperGreen', 'paperGrass', 'paperLime', 'paperMint', 'paperSky'
    ));
