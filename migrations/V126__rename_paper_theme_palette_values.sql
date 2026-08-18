ALTER TABLE users
    DROP CONSTRAINT IF EXISTS chk_users_theme_palette_main,
    DROP CONSTRAINT IF EXISTS chk_users_theme_palette_accent;

UPDATE users
SET theme_palette_main = CASE theme_palette_main
        WHEN 'paperCotton' THEN 'cotton'
        WHEN 'paperPorcelain' THEN 'porcelain'
        WHEN 'paperInk' THEN 'ink'
        WHEN 'paperYellow' THEN 'yellow'
        WHEN 'paperAmber' THEN 'amber'
        WHEN 'paperOrange' THEN 'orange'
        WHEN 'paperTomato' THEN 'tomato'
        WHEN 'paperRed' THEN 'red'
        WHEN 'paperRuby' THEN 'ruby'
        WHEN 'paperCrimson' THEN 'crimson'
        WHEN 'paperPink' THEN 'pink'
        WHEN 'paperPlum' THEN 'plum'
        WHEN 'paperPurple' THEN 'purple'
        WHEN 'paperViolet' THEN 'violet'
        WHEN 'paperIris' THEN 'iris'
        WHEN 'paperIndigo' THEN 'indigo'
        WHEN 'paperBlue' THEN 'blue'
        WHEN 'paperCyan' THEN 'cyan'
        WHEN 'paperTeal' THEN 'teal'
        WHEN 'paperJade' THEN 'jade'
        WHEN 'paperGreen' THEN 'green'
        WHEN 'paperGrass' THEN 'grass'
        WHEN 'paperLime' THEN 'lime'
        WHEN 'paperMint' THEN 'mint'
        WHEN 'paperSky' THEN 'sky'
        ELSE theme_palette_main
    END,
    theme_palette_accent = CASE theme_palette_accent
        WHEN 'paperCotton' THEN 'cotton'
        WHEN 'paperPorcelain' THEN 'porcelain'
        WHEN 'paperInk' THEN 'ink'
        WHEN 'paperYellow' THEN 'yellow'
        WHEN 'paperAmber' THEN 'amber'
        WHEN 'paperOrange' THEN 'orange'
        WHEN 'paperTomato' THEN 'tomato'
        WHEN 'paperRed' THEN 'red'
        WHEN 'paperRuby' THEN 'ruby'
        WHEN 'paperCrimson' THEN 'crimson'
        WHEN 'paperPink' THEN 'pink'
        WHEN 'paperPlum' THEN 'plum'
        WHEN 'paperPurple' THEN 'purple'
        WHEN 'paperViolet' THEN 'violet'
        WHEN 'paperIris' THEN 'iris'
        WHEN 'paperIndigo' THEN 'indigo'
        WHEN 'paperBlue' THEN 'blue'
        WHEN 'paperCyan' THEN 'cyan'
        WHEN 'paperTeal' THEN 'teal'
        WHEN 'paperJade' THEN 'jade'
        WHEN 'paperGreen' THEN 'green'
        WHEN 'paperGrass' THEN 'grass'
        WHEN 'paperLime' THEN 'lime'
        WHEN 'paperMint' THEN 'mint'
        WHEN 'paperSky' THEN 'sky'
        ELSE theme_palette_accent
    END;

ALTER TABLE users
    ALTER COLUMN theme_palette_main SET DEFAULT 'porcelain',
    ALTER COLUMN theme_palette_accent SET DEFAULT 'semantic';

ALTER TABLE users
    ADD CONSTRAINT chk_users_theme_palette_main
    CHECK (theme_palette_main IN (
        'paper', 'cotton', 'porcelain', 'ink',
        'yellow', 'amber', 'orange', 'tomato', 'red',
        'ruby', 'crimson', 'pink', 'plum', 'purple', 'violet',
        'iris', 'indigo', 'blue', 'cyan', 'teal', 'jade',
        'green', 'grass', 'lime', 'mint', 'sky'
    )),
    ADD CONSTRAINT chk_users_theme_palette_accent
    CHECK (theme_palette_accent IN (
        'semantic',
        'paper', 'cotton', 'porcelain', 'ink',
        'yellow', 'amber', 'orange', 'tomato', 'red',
        'ruby', 'crimson', 'pink', 'plum', 'purple', 'violet',
        'iris', 'indigo', 'blue', 'cyan', 'teal', 'jade',
        'green', 'grass', 'lime', 'mint', 'sky'
    ));
