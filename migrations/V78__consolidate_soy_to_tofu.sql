-- Migrate soy_balance values into tofu_balance
UPDATE users SET tofu_balance = tofu_balance + soy_balance;

-- Drop the soy_balance column
ALTER TABLE users DROP COLUMN soy_balance;
