-- Fixture data for tofustash development

INSERT INTO users (id, email, password, premium, theme_preference, soy_balance, tofu_balance) VALUES
('11111111-1111-1111-1111-111111111111', 'alice@example.com', '$argon2id$v=19$m=19456,t=2,p=1$mGgPTifIvQ6giqIgS7u5Bg$+vMH8Y/Zeab+O90RTLo5oYUiIb4NS5e1DInFrXAX9Lc', false, 'auto', 100.0, 50.0),
('22222222-2222-2222-2222-222222222222', 'bob@example.com', '$argon2id$v=19$m=19456,t=2,p=1$mGgPTifIvQ6giqIgS7u5Bg$+vMH8Y/Zeab+O90RTLo5oYUiIb4NS5e1DInFrXAX9Lc', true, 'dark', 250.0, 120.0),
('33333333-3333-3333-3333-333333333333', 'charlie@example.com', '$argon2id$v=19$m=19456,t=2,p=1$mGgPTifIvQ6giqIgS7u5Bg$+vMH8Y/Zeab+O90RTLo5oYUiIb4NS5e1DInFrXAX9Lc', false, 'light', 0.0, 0.0);

-- Tags for Alice
INSERT INTO tags (id, user_id, name, color_hex) VALUES
('aaaa1111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111', 'Work', '#FF5733  '),
('aaaa2222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111', 'Personal', '#33FF57  '),
('aaaa3333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111', 'Urgent', '#FF0000  ');

-- Tags for Bob
INSERT INTO tags (id, user_id, name, color_hex) VALUES
('bbbb1111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', 'Health', '#00FF00  '),
('bbbb2222-2222-2222-2222-222222222222', '22222222-2222-2222-2222-222222222222', 'Learning', '#0000FF  ');

-- Tasks for Alice
INSERT INTO tasks (id, user_id, name, description, due_by, min_daily_frequency, hidden_until) VALUES
('aaaa0001-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'Complete project proposal', 'Write and submit the Q1 project proposal to management', '2025-01-15 17:00:00', NULL, NULL),
('aaaa0002-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'Review pull requests', 'Go through pending PRs on the main repo', NULL, NULL, NULL),
('aaaa0003-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111', 'Exercise', 'Daily workout routine', NULL, 1.0, NULL),
('aaaa0004-0000-0000-0000-000000000004', '11111111-1111-1111-1111-111111111111', 'Read documentation', 'Catch up on new API documentation', NULL, NULL, '2025-01-10 09:00:00'),
('aaaa0005-0000-0000-0000-000000000005', '11111111-1111-1111-1111-111111111111', 'Team standup', 'Daily team sync meeting', NULL, 1.0, NULL);

-- Tasks for Bob
INSERT INTO tasks (id, user_id, name, description, due_by, min_daily_frequency, hidden_until) VALUES
('bbbb0001-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'Morning meditation', 'Start the day with 15 minutes of mindfulness', NULL, 1.0, NULL),
('bbbb0002-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222222', 'Learn Rust', 'Complete chapter 5 of the Rust book', '2025-02-01 23:59:59', NULL, NULL),
('bbbb0003-0000-0000-0000-000000000003', '22222222-2222-2222-2222-222222222222', 'Grocery shopping', 'Buy vegetables and fruits for the week', '2025-01-07 18:00:00', NULL, NULL);

-- Tasks for Charlie
INSERT INTO tasks (id, user_id, name, description, due_by, min_daily_frequency, hidden_until) VALUES
('cccc0001-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333', 'Setup new laptop', 'Install dev tools and configure environment', '2025-01-08 12:00:00', NULL, NULL);

-- Task Tags (linking tasks to tags)
INSERT INTO task_tags (task_id, tag_id) VALUES
('aaaa0001-0000-0000-0000-000000000001', 'aaaa1111-1111-1111-1111-111111111111'),
('aaaa0001-0000-0000-0000-000000000001', 'aaaa3333-3333-3333-3333-333333333333'),
('aaaa0002-0000-0000-0000-000000000002', 'aaaa1111-1111-1111-1111-111111111111'),
('aaaa0003-0000-0000-0000-000000000003', 'aaaa2222-2222-2222-2222-222222222222'),
('aaaa0005-0000-0000-0000-000000000005', 'aaaa1111-1111-1111-1111-111111111111'),
('bbbb0001-0000-0000-0000-000000000001', 'bbbb1111-1111-1111-1111-111111111111'),
('bbbb0002-0000-0000-0000-000000000002', 'bbbb2222-2222-2222-2222-222222222222');

-- Task Dependencies (task depends on another task)
INSERT INTO task_dependencies (task_id, depends_on_task_id) VALUES
('aaaa0002-0000-0000-0000-000000000002', 'aaaa0001-0000-0000-0000-000000000001');

-- Rewards for Alice
INSERT INTO rewards (id, user_id, name, description, max_daily_frequency, hidden_until) VALUES
('aaaa1000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'Coffee break', 'Enjoy a nice cup of coffee', 3.0, NULL),
('aaaa1000-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'Gaming session', 'Play video games for 30 minutes', 2.0, NULL),
('aaaa1000-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111', 'Movie night', 'Watch a movie of your choice', 1.0, NULL);

-- Rewards for Bob
INSERT INTO rewards (id, user_id, name, description, max_daily_frequency, hidden_until) VALUES
('bbbb1000-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'Snack time', 'Have a healthy snack', 4.0, NULL),
('bbbb1000-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222222', 'YouTube break', 'Watch YouTube for 15 minutes', 2.0, NULL);

-- Trades (task completions and reward claims)
INSERT INTO trades (id, task_id, reward_id, amount) VALUES
('aaaa2000-0000-0000-0000-000000000001', 'aaaa0003-0000-0000-0000-000000000003', NULL, 10),
('aaaa2000-0000-0000-0000-000000000002', 'aaaa0005-0000-0000-0000-000000000005', NULL, 5),
('aaaa2000-0000-0000-0000-000000000003', NULL, 'aaaa1000-0000-0000-0000-000000000001', -5),
('bbbb2000-0000-0000-0000-000000000001', 'bbbb0001-0000-0000-0000-000000000001', NULL, 15),
('bbbb2000-0000-0000-0000-000000000002', 'bbbb0001-0000-0000-0000-000000000001', NULL, 15),
('bbbb2000-0000-0000-0000-000000000003', NULL, 'bbbb1000-0000-0000-0000-000000000001', -10);
