ALTER TABLE users
    DROP CONSTRAINT chk_users_theme_palette_neutral,
    DROP CONSTRAINT chk_users_theme_palette_task,
    DROP CONSTRAINT chk_users_theme_palette_habit,
    DROP CONSTRAINT chk_users_theme_palette_reward,
    DROP CONSTRAINT chk_users_theme_palette_settings;

ALTER TABLE users
    ADD CONSTRAINT chk_users_theme_palette_neutral
    CHECK (theme_palette_neutral IN (
        'paper', 'paperCotton', 'paperPorcelain', 'paperInk',
        'paperYellow', 'paperAmber', 'paperOrange', 'paperTomato', 'paperRed',
        'paperRuby', 'paperCrimson', 'paperPink', 'paperPlum', 'paperPurple', 'paperViolet',
        'paperIris', 'paperIndigo', 'paperBlue', 'paperCyan', 'paperTeal', 'paperJade',
        'paperGreen', 'paperGrass', 'paperLime', 'paperMint', 'paperSky'
    )),
    ADD CONSTRAINT chk_users_theme_palette_task
    CHECK (theme_palette_task IN (
        'paper', 'paperCotton', 'paperPorcelain', 'paperInk',
        'paperYellow', 'paperAmber', 'paperOrange', 'paperTomato', 'paperRed',
        'paperRuby', 'paperCrimson', 'paperPink', 'paperPlum', 'paperPurple', 'paperViolet',
        'paperIris', 'paperIndigo', 'paperBlue', 'paperCyan', 'paperTeal', 'paperJade',
        'paperGreen', 'paperGrass', 'paperLime', 'paperMint', 'paperSky'
    )),
    ADD CONSTRAINT chk_users_theme_palette_habit
    CHECK (theme_palette_habit IN (
        'paper', 'paperCotton', 'paperPorcelain', 'paperInk',
        'paperYellow', 'paperAmber', 'paperOrange', 'paperTomato', 'paperRed',
        'paperRuby', 'paperCrimson', 'paperPink', 'paperPlum', 'paperPurple', 'paperViolet',
        'paperIris', 'paperIndigo', 'paperBlue', 'paperCyan', 'paperTeal', 'paperJade',
        'paperGreen', 'paperGrass', 'paperLime', 'paperMint', 'paperSky'
    )),
    ADD CONSTRAINT chk_users_theme_palette_reward
    CHECK (theme_palette_reward IN (
        'paper', 'paperCotton', 'paperPorcelain', 'paperInk',
        'paperYellow', 'paperAmber', 'paperOrange', 'paperTomato', 'paperRed',
        'paperRuby', 'paperCrimson', 'paperPink', 'paperPlum', 'paperPurple', 'paperViolet',
        'paperIris', 'paperIndigo', 'paperBlue', 'paperCyan', 'paperTeal', 'paperJade',
        'paperGreen', 'paperGrass', 'paperLime', 'paperMint', 'paperSky'
    )),
    ADD CONSTRAINT chk_users_theme_palette_settings
    CHECK (theme_palette_settings IN (
        'paper', 'paperCotton', 'paperPorcelain', 'paperInk',
        'paperYellow', 'paperAmber', 'paperOrange', 'paperTomato', 'paperRed',
        'paperRuby', 'paperCrimson', 'paperPink', 'paperPlum', 'paperPurple', 'paperViolet',
        'paperIris', 'paperIndigo', 'paperBlue', 'paperCyan', 'paperTeal', 'paperJade',
        'paperGreen', 'paperGrass', 'paperLime', 'paperMint', 'paperSky'
    ));
