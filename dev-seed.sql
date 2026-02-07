-- Fixture data for tofustash development

INSERT INTO users (id, email, password, premium, theme_preference, tofu_balance) VALUES
('11111111-1111-1111-1111-111111111111', 'alice@example.com', '$argon2id$v=19$m=19456,t=2,p=1$mGgPTifIvQ6giqIgS7u5Bg$+vMH8Y/Zeab+O90RTLo5oYUiIb4NS5e1DInFrXAX9Lc', false, 'auto', 150.0),
('22222222-2222-2222-2222-222222222222', 'bob@example.com', '$argon2id$v=19$m=19456,t=2,p=1$mGgPTifIvQ6giqIgS7u5Bg$+vMH8Y/Zeab+O90RTLo5oYUiIb4NS5e1DInFrXAX9Lc', true, 'dark', 370.0),
('33333333-3333-3333-3333-333333333333', 'charlie@example.com', '$argon2id$v=19$m=19456,t=2,p=1$mGgPTifIvQ6giqIgS7u5Bg$+vMH8Y/Zeab+O90RTLo5oYUiIb4NS5e1DInFrXAX9Lc', false, 'light', 0.0);

-- Tags for Alice
INSERT INTO tags (id, user_id, name, color_hex) VALUES
('aaaa1111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111', 'Work', '#FF5733  '),
('aaaa2222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111', 'Personal', '#33FF57  '),
('aaaa3333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111', 'Urgent', '#FF0000  ');

-- Tags for Bob
INSERT INTO tags (id, user_id, name, color_hex) VALUES
('bbbb1111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', 'Health', '#00FF00  '),
('bbbb2222-2222-2222-2222-222222222222', '22222222-2222-2222-2222-222222222222', 'Learning', '#0000FF  ');

-- Habits for Alice
INSERT INTO habits (id, user_id, name, description, min_daily_frequency, hidden_until, difficulty_rank) VALUES
('aaaa0001-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'Complete project proposal', 'Write and submit the Q1 project proposal to management', NULL, NULL, 'a0'),
('aaaa0002-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'Review pull requests', 'Go through pending PRs on the main repo', NULL, NULL, 'a1'),
('aaaa0003-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111', 'Exercise', 'Daily workout routine', 1.0, NULL, 'a2'),
('aaaa0004-0000-0000-0000-000000000004', '11111111-1111-1111-1111-111111111111', 'Read documentation', 'Catch up on new API documentation', NULL, '2025-01-10 09:00:00', 'a3'),
('aaaa0005-0000-0000-0000-000000000005', '11111111-1111-1111-1111-111111111111', 'Team standup', 'Daily team sync meeting', 1.0, NULL, 'a4');

-- Habits for Bob
INSERT INTO habits (id, user_id, name, description, min_daily_frequency, hidden_until, difficulty_rank) VALUES
('bbbb0001-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'Morning meditation', 'Start the day with 15 minutes of mindfulness', 1.0, NULL, 'a0'),
('bbbb0002-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222222', 'Learn Rust', 'Complete chapter 5 of the Rust book', NULL, NULL, 'a1'),
('bbbb0003-0000-0000-0000-000000000003', '22222222-2222-2222-2222-222222222222', 'Grocery shopping', 'Buy vegetables and fruits for the week', NULL, NULL, 'a2');

-- Habits for Charlie
INSERT INTO habits (id, user_id, name, description, min_daily_frequency, hidden_until, difficulty_rank) VALUES
('cccc0001-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333', 'Setup new laptop', 'Install dev tools and configure environment', NULL, NULL, 'a0');

-- Rewards for Alice
INSERT INTO rewards (id, user_id, name, description, max_daily_frequency, hidden_until) VALUES
('aaaa1000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'Coffee break', 'Enjoy a nice cup of coffee', 3.0, NULL),
('aaaa1000-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'Gaming session', 'Play video games for 30 minutes', 2.0, NULL),
('aaaa1000-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111', 'Movie night', 'Watch a movie of your choice', 1.0, NULL);

-- Rewards for Bob
INSERT INTO rewards (id, user_id, name, description, max_daily_frequency, hidden_until) VALUES
('bbbb1000-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'Snack time', 'Have a healthy snack', 4.0, NULL),
('bbbb1000-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222222', 'YouTube break', 'Watch YouTube for 15 minutes', 2.0, NULL);

-- Trades (habit completions and reward claims)
INSERT INTO trades (id, user_id, habit_id, reward_id, amount) VALUES
('aaaa2000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'aaaa0003-0000-0000-0000-000000000003', NULL, 10),
('aaaa2000-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'aaaa0005-0000-0000-0000-000000000005', NULL, 5),
('aaaa2000-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111', NULL, 'aaaa1000-0000-0000-0000-000000000001', -5),
('bbbb2000-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'bbbb0001-0000-0000-0000-000000000001', NULL, 15),
('bbbb2000-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222222', 'bbbb0001-0000-0000-0000-000000000001', NULL, 15),
('bbbb2000-0000-0000-0000-000000000003', '22222222-2222-2222-2222-222222222222', NULL, 'bbbb1000-0000-0000-0000-000000000001', -10);
