use chrono::NaiveDateTime;
use sqlx::{postgres::PgPoolOptions, Pool, Postgres, Transaction};
use url::form_urlencoded;
use uuid::Uuid;

#[derive(Clone)]
pub struct Database {
    pool: Pool<Postgres>,
}

impl Database {
    pub async fn new() -> Self {
        // Get configuration from environment variables
        let user = std::env::var("DB_USER").expect("DB_USER not set");
        let password = std::env::var("DB_PASSWORD").expect("DB_PASSWORD not set");
        let encoded_password: String =
            form_urlencoded::byte_serialize(password.as_bytes()).collect();
        let host = std::env::var("DB_HOST").expect("DB_HOST not set");
        let name = std::env::var("DB_NAME").expect("DB_NAME not set");
        let ssl_mode = std::env::var("SSL_MODE").expect("SSL_MODE not set");

        let database_url = format!(
            "postgres://{}:{}@{}:5432/{}?sslmode={}",
            user, encoded_password, host, name, ssl_mode
        );

        let pool = PgPoolOptions::new()
            // 97 is the default connection limit for postgres. All pools must add up
            // to at most 97. Since we will have at most 2 servers, 48 is an
            // appropriate value here.
            .max_connections(48)
            .connect(&database_url)
            .await
            .expect("Unable to create database pool.");

        Database { pool }
    }

    /// Creates a user, returning the user id.
    pub async fn create_user(
        &self,
        email: &str,
        hashed_password: &str,
    ) -> Result<Uuid, sqlx::Error> {
        let (user_id,): (Uuid,) =
            sqlx::query_as("INSERT INTO users (email, password) VALUES ($1, $2) RETURNING id")
                .bind(email)
                .bind(hashed_password)
                .fetch_one(&self.pool)
                .await?;

        Ok(user_id)
    }

    pub async fn create_habit(
        &self,
        create_habit_options: CreateHabitOptions,
    ) -> Result<HabitRow, sqlx::Error> {
        sqlx::query_as(
            "INSERT INTO habits
            (user_id, name, hidden_until, description, min_daily_frequency, difficulty_rank) VALUES ($1, $2, $3, $4, $5, $6) RETURNING id, name, created_at, updated_at, deleted_at, hidden_until, description, min_daily_frequency, difficulty_rank",
        )
        .bind(create_habit_options.user_id)
        .bind(create_habit_options.name)
        .bind(create_habit_options.hidden_until)
        .bind(create_habit_options.description)
        .bind(create_habit_options.min_daily_frequency)
        .bind(create_habit_options.difficulty_rank)
        .fetch_one(&self.pool)
        .await
    }

    pub async fn create_reward(
        &self,
        create_reward_options: CreateRewardOptions,
    ) -> Result<RewardRow, sqlx::Error> {
        sqlx::query_as(
            "INSERT INTO rewards
            (user_id, name, description, hidden_until, max_daily_frequency) VALUES ($1, $2, $3, $4, $5) RETURNING id, name, description, created_at, updated_at, deleted_at, hidden_until, max_daily_frequency",
        )
        .bind(create_reward_options.user_id)
        .bind(create_reward_options.name)
        .bind(create_reward_options.description)
        .bind(create_reward_options.hidden_until)
        .bind(create_reward_options.max_daily_frequency)
        .fetch_one(&self.pool)
        .await
    }

    pub async fn create_trade_with_habit(
        &self,
        create_trade_options: CreateTradeWithHabitOptions,
    ) -> Result<TradeWithHabitRow, sqlx::Error> {
        sqlx::query_as(
            // We `SELECT $1, $2, $3` here instead of `SELECT column names`. This is valid SQL.
            // We do this because we can only do a where clause if we SELECT. We don't want
            // to use any of the values from the habits table for the insert, so we just provide
            // literal values that, after the validation is done, gets used by the insert
            // statement.
            "WITH new_trade AS (
                INSERT INTO trades (habit_id, amount, user_id)
                SELECT $1, $2, $3
                FROM habits
                WHERE habits.id = $1 AND habits.user_id = $3
                RETURNING id, habit_id, reward_id, amount, created_at
            )
            SELECT
                nt.*,
                h.name AS habit_name, h.created_at AS habit_created_at, h.updated_at AS habit_updated_at, h.deleted_at AS habit_deleted_at, h.hidden_until AS habit_hidden_until, h.description AS habit_description, h.min_daily_frequency AS habit_min_daily_frequency, h.difficulty_rank AS habit_difficulty_rank
            FROM new_trade nt
            JOIN habits h ON nt.habit_id = h.id",
        )
        .bind(create_trade_options.habit_id)
        .bind(create_trade_options.amount)
        .bind(create_trade_options.user_id)
        .fetch_one(&self.pool)
        .await
    }

    pub async fn create_trade_with_reward(
        &self,
        create_trade_options: CreateTradeWithRewardOptions,
    ) -> Result<TradeWithRewardRow, sqlx::Error> {
        sqlx::query_as(
            "WITH new_trade AS (
                INSERT INTO trades (reward_id, amount, user_id)
                SELECT $1, $2, $3
                FROM rewards
                WHERE rewards.id = $1 AND rewards.user_id = $3
                RETURNING id, habit_id, reward_id, amount, created_at
            )
            SELECT
                nt.*,
                r.name AS reward_name, r.created_at AS reward_created_at, r.updated_at AS reward_updated_at, r.deleted_at AS reward_deleted_at, r.hidden_until AS reward_hidden_until, r.description AS reward_description, r.max_daily_frequency as reward_max_daily_frequency
            FROM new_trade nt
            JOIN rewards r ON nt.reward_id = r.id",
        )
        .bind(create_trade_options.reward_id)
        .bind(create_trade_options.amount)
        .bind(create_trade_options.user_id)
        .fetch_one(&self.pool)
        .await
    }

    /// Creates refresh token in the db. Api keys have expires_at = NULL
    pub async fn create_or_overwrite_refresh_token(
        &self,
        refresh_token: &str,
        user_id: Uuid,
        name: &str,
        is_api_key: bool,
    ) -> Result<RefreshTokenRow, sqlx::Error> {
        // TODO: put in transaction.
        // Delete
        sqlx::query("DELETE FROM refresh_tokens WHERE name = $1 AND user_id = $2;")
            .bind(name)
            .bind(user_id)
            .execute(&self.pool)
            .await?;

        let insert_query = match is_api_key{
            true => "INSERT INTO refresh_tokens (key, user_id, name, expires_at) VALUES ($1, $2, $3, NULL) RETURNING key, created_at, expires_at",
            false => "INSERT INTO refresh_tokens (key, user_id, name) VALUES ($1, $2, $3) RETURNING key, created_at, expires_at"
        };
        let refresh_token_row: RefreshTokenRow = sqlx::query_as(insert_query)
            .bind(refresh_token)
            .bind(user_id)
            .bind(name)
            .fetch_one(&self.pool)
            .await
            .map_err(|_| sqlx::Error::RowNotFound)?;

        Ok(refresh_token_row)
    }

    pub async fn delete_refresh_token_by_user_and_name(
        &self,
        user_id: Uuid,
        name: &str,
    ) -> Result<(), sqlx::Error> {
        sqlx::query("DELETE FROM refresh_tokens WHERE user_id = $1 AND name = $2")
            .bind(user_id)
            .bind(name)
            .execute(&self.pool)
            .await?;

        Ok(())
    }

    pub async fn get_refresh_token_from_name_user(
        &self,
        name: &str,
        user_id: Uuid,
    ) -> Result<RefreshTokenRow, sqlx::Error> {
        sqlx::query_as(
            "
            SELECT refresh_tokens.key, refresh_tokens.created_at, refresh_tokens.expires_at
            FROM refresh_tokens
            INNER JOIN users ON refresh_tokens.user_id = users.id
            WHERE refresh_tokens.name = $1
            AND refresh_tokens.user_id = $2
            AND (refresh_tokens.expires_at > NOW() OR refresh_tokens.expires_at IS NULL);
        ",
        )
        .bind(name)
        .bind(user_id)
        .fetch_optional(&self.pool)
        .await
        .unwrap()
        .ok_or(sqlx::Error::RowNotFound)
    }

    /// Returns the user from email.
    pub async fn get_user_from_email(&self, email: &str) -> Result<UserRow, sqlx::Error> {
        sqlx::query_as("SELECT id, email, password, is_anonymous, device_id, premium FROM users WHERE email = $1")
            .bind(email)
            .fetch_optional(&self.pool)
            .await?
            .ok_or(sqlx::Error::RowNotFound)
    }

    /// Creates an anonymous user, returning the user id.
    pub async fn create_anonymous_user(&self, device_id: Uuid) -> Result<Uuid, sqlx::Error> {
        let (user_id,): (Uuid,) = sqlx::query_as(
            "INSERT INTO users (is_anonymous, device_id) VALUES (true, $1) RETURNING id",
        )
        .bind(device_id)
        .fetch_one(&self.pool)
        .await?;

        Ok(user_id)
    }

    /// Returns the user from device_id.
    pub async fn get_user_from_device_id(&self, device_id: Uuid) -> Result<UserRow, sqlx::Error> {
        sqlx::query_as(
            "SELECT id, email, password, is_anonymous, device_id, premium FROM users WHERE device_id = $1",
        )
        .bind(device_id)
        .fetch_optional(&self.pool)
        .await?
        .ok_or(sqlx::Error::RowNotFound)
    }

    /// Claims an anonymous account by setting email and password.
    pub async fn claim_account(
        &self,
        user_id: Uuid,
        email: &str,
        hashed_password: &str,
    ) -> Result<(), sqlx::Error> {
        let result = sqlx::query(
            "UPDATE users SET email = $2, password = $3, is_anonymous = false WHERE id = $1 AND is_anonymous = true",
        )
        .bind(user_id)
        .bind(email)
        .bind(hashed_password)
        .execute(&self.pool)
        .await?;

        if result.rows_affected() == 0 {
            return Err(sqlx::Error::RowNotFound);
        }

        Ok(())
    }

    /// Checks if a user is anonymous.
    pub async fn is_user_anonymous(&self, user_id: Uuid) -> Result<bool, sqlx::Error> {
        let (is_anonymous,): (bool,) =
            sqlx::query_as("SELECT is_anonymous FROM users WHERE id = $1")
                .bind(user_id)
                .fetch_one(&self.pool)
                .await?;

        Ok(is_anonymous)
    }

    // ============================================================================
    // Sync Operations
    // ============================================================================

    /// Get all habits for a user, optionally filtered by updated_at > since
    pub async fn get_habits_since(
        &self,
        user_id: Uuid,
        since: Option<NaiveDateTime>,
    ) -> Result<Vec<HabitRow>, sqlx::Error> {
        match since {
            Some(since_time) => {
                sqlx::query_as(
                    "SELECT id, name, created_at, updated_at, deleted_at, hidden_until, description, min_daily_frequency, difficulty_rank
                     FROM habits
                     WHERE user_id = $1 AND updated_at > $2
                     ORDER BY updated_at ASC",
                )
                .bind(user_id)
                .bind(since_time)
                .fetch_all(&self.pool)
                .await
            }
            None => {
                sqlx::query_as(
                    "SELECT id, name, created_at, updated_at, deleted_at, hidden_until, description, min_daily_frequency, difficulty_rank
                     FROM habits
                     WHERE user_id = $1
                     ORDER BY updated_at ASC",
                )
                .bind(user_id)
                .fetch_all(&self.pool)
                .await
            }
        }
    }

    // ============================================================================
    // Trade Sync Operations
    // ============================================================================

    /// Get all trades for a user, optionally filtered by updated_at > since
    pub async fn get_trades_since(
        &self,
        user_id: Uuid,
        since: Option<NaiveDateTime>,
    ) -> Result<Vec<TradeRow>, sqlx::Error> {
        match since {
            Some(since_time) => {
                sqlx::query_as(
                    "SELECT id, habit_id, reward_id, amount, created_at, updated_at, deleted_at
                     FROM trades
                     WHERE user_id = $1 AND updated_at > $2
                     ORDER BY updated_at ASC",
                )
                .bind(user_id)
                .bind(since_time)
                .fetch_all(&self.pool)
                .await
            }
            None => {
                sqlx::query_as(
                    "SELECT id, habit_id, reward_id, amount, created_at, updated_at, deleted_at
                     FROM trades
                     WHERE user_id = $1
                     ORDER BY updated_at ASC",
                )
                .bind(user_id)
                .fetch_all(&self.pool)
                .await
            }
        }
    }

    /// Get user balance
    pub async fn get_user_balance(&self, user_id: Uuid) -> Result<UserBalanceRow, sqlx::Error> {
        sqlx::query_as("SELECT soy_balance, tofu_balance FROM users WHERE id = $1")
            .bind(user_id)
            .fetch_one(&self.pool)
            .await
    }

    /// Get user profile (email and premium status)
    pub async fn get_user_profile(&self, user_id: Uuid) -> Result<UserProfileRow, sqlx::Error> {
        sqlx::query_as("SELECT email, premium FROM users WHERE id = $1")
            .bind(user_id)
            .fetch_one(&self.pool)
            .await
    }

    // ============================================================================
    // Transaction Support for Unified Sync
    // ============================================================================

    /// Begin a new database transaction
    pub async fn begin_transaction(&self) -> Result<Transaction<'_, Postgres>, sqlx::Error> {
        self.pool.begin().await
    }

    /// Upsert a habit within a transaction
    pub async fn upsert_habit_tx(
        tx: &mut Transaction<'_, Postgres>,
        user_id: Uuid,
        habit: &UpsertHabitOptions,
    ) -> Result<HabitRow, sqlx::Error> {
        sqlx::query_as(
            "INSERT INTO habits (id, user_id, name, description, created_at, deleted_at, hidden_until, min_daily_frequency, difficulty_rank)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
             ON CONFLICT (id) DO UPDATE SET
                user_id = CASE
                    WHEN habits.user_id = $2 THEN habits.user_id
                    WHEN EXISTS (SELECT 1 FROM users WHERE id = habits.user_id AND is_anonymous = true) THEN $2
                    ELSE habits.user_id
                END,
                name = CASE
                    WHEN habits.user_id = $2 OR EXISTS (SELECT 1 FROM users WHERE id = habits.user_id AND is_anonymous = true) THEN EXCLUDED.name
                    ELSE habits.name
                END,
                description = CASE
                    WHEN habits.user_id = $2 OR EXISTS (SELECT 1 FROM users WHERE id = habits.user_id AND is_anonymous = true) THEN EXCLUDED.description
                    ELSE habits.description
                END,
                deleted_at = CASE
                    WHEN habits.user_id = $2 OR EXISTS (SELECT 1 FROM users WHERE id = habits.user_id AND is_anonymous = true) THEN EXCLUDED.deleted_at
                    ELSE habits.deleted_at
                END,
                hidden_until = CASE
                    WHEN habits.user_id = $2 OR EXISTS (SELECT 1 FROM users WHERE id = habits.user_id AND is_anonymous = true) THEN EXCLUDED.hidden_until
                    ELSE habits.hidden_until
                END,
                min_daily_frequency = CASE
                    WHEN habits.user_id = $2 OR EXISTS (SELECT 1 FROM users WHERE id = habits.user_id AND is_anonymous = true) THEN EXCLUDED.min_daily_frequency
                    ELSE habits.min_daily_frequency
                END,
                difficulty_rank = CASE
                    WHEN habits.user_id = $2 OR EXISTS (SELECT 1 FROM users WHERE id = habits.user_id AND is_anonymous = true) THEN EXCLUDED.difficulty_rank
                    ELSE habits.difficulty_rank
                END
             RETURNING id, name, created_at, updated_at, deleted_at, hidden_until, description, min_daily_frequency, difficulty_rank",
        )
        .bind(habit.id)
        .bind(user_id)
        .bind(&habit.name)
        .bind(&habit.description)
        .bind(habit.created_at)
        .bind(habit.deleted_at)
        .bind(habit.hidden_until)
        .bind(habit.min_daily_frequency)
        .bind(&habit.difficulty_rank)
        .fetch_one(&mut **tx)
        .await
    }

    /// Upsert a trade within a transaction (does not update balance - caller should use recalculate_balance_tx)
    pub async fn upsert_trade_tx(
        tx: &mut Transaction<'_, Postgres>,
        user_id: Uuid,
        trade: &UpsertTradeOptions,
    ) -> Result<TradeRow, sqlx::Error> {
        // Validate habit belongs to user if habit_id is provided
        if let Some(habit_id) = trade.habit_id {
            let habit_valid: Option<(Uuid,)> = sqlx::query_as(
                "SELECT id FROM habits
                 WHERE id = $1 AND (user_id = $2 OR EXISTS (SELECT 1 FROM users WHERE id = habits.user_id AND is_anonymous = true))",
            )
            .bind(habit_id)
            .bind(user_id)
            .fetch_optional(&mut **tx)
            .await?;

            if habit_valid.is_none() {
                return Err(sqlx::Error::RowNotFound);
            }
        }

        // Validate reward belongs to user if reward_id is provided
        if let Some(reward_id) = trade.reward_id {
            let reward_valid: Option<(Uuid,)> = sqlx::query_as(
                "SELECT id FROM rewards WHERE id = $1 AND user_id = $2",
            )
            .bind(reward_id)
            .bind(user_id)
            .fetch_optional(&mut **tx)
            .await?;

            if reward_valid.is_none() {
                return Err(sqlx::Error::RowNotFound);
            }
        }

        // Upsert the trade
        sqlx::query_as(
            "INSERT INTO trades (id, user_id, habit_id, reward_id, amount, created_at, deleted_at)
             VALUES ($1, $2, $3, $4, $5, $6, $7)
             ON CONFLICT (id) DO UPDATE SET
                deleted_at = EXCLUDED.deleted_at
             RETURNING id, habit_id, reward_id, amount, created_at, updated_at, deleted_at",
        )
        .bind(trade.id)
        .bind(user_id)
        .bind(trade.habit_id)
        .bind(trade.reward_id)
        .bind(trade.amount)
        .bind(trade.created_at)
        .bind(trade.deleted_at)
        .fetch_one(&mut **tx)
        .await
    }

    /// Recalculate user balance from all non-deleted trades within a transaction
    pub async fn recalculate_balance_tx(
        tx: &mut Transaction<'_, Postgres>,
        user_id: Uuid,
    ) -> Result<f64, sqlx::Error> {
        // Sum all non-deleted trades
        let (total,): (Option<i64>,) = sqlx::query_as(
            "SELECT COALESCE(SUM(amount), 0) FROM trades WHERE user_id = $1 AND deleted_at IS NULL",
        )
        .bind(user_id)
        .fetch_one(&mut **tx)
        .await?;

        let balance = total.unwrap_or(0) as f64;

        // Update user balance
        sqlx::query("UPDATE users SET soy_balance = $2 WHERE id = $1")
            .bind(user_id)
            .bind(balance)
            .execute(&mut **tx)
            .await?;

        Ok(balance)
    }
}

pub struct CreateHabitOptions {
    pub user_id: Uuid,
    pub name: String,
    pub hidden_until: Option<NaiveDateTime>,
    pub description: String,
    pub min_daily_frequency: Option<f64>,
    pub difficulty_rank: Option<String>,
}

pub struct CreateTradeWithHabitOptions {
    user_id: Uuid,
    habit_id: Uuid,
    amount: i32,
}
impl CreateTradeWithHabitOptions {
    pub fn new(user_id: Uuid, habit_id: Uuid, amount: i32) -> Self {
        Self {
            user_id,
            habit_id,
            amount,
        }
    }
}

pub struct CreateTradeWithRewardOptions {
    user_id: Uuid,
    reward_id: Uuid,
    amount: i32,
}
impl CreateTradeWithRewardOptions {
    pub fn new(user_id: Uuid, reward_id: Uuid, amount: i32) -> Self {
        Self {
            user_id,
            reward_id,
            amount,
        }
    }
}

pub struct CreateRewardOptions {
    pub user_id: Uuid,
    pub name: String,
    pub description: String,
    pub hidden_until: Option<NaiveDateTime>,
    pub max_daily_frequency: Option<f32>,
}

pub struct UpsertHabitOptions {
    pub id: Uuid,
    pub name: String,
    pub description: String,
    pub created_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub hidden_until: Option<NaiveDateTime>,
    pub min_daily_frequency: Option<f64>,
    pub difficulty_rank: Option<String>,
}

pub struct UpsertTradeOptions {
    pub id: Uuid,
    pub habit_id: Option<Uuid>,
    pub reward_id: Option<Uuid>,
    pub amount: i32,
    pub created_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
}

#[derive(sqlx::FromRow)]
pub struct TradeRow {
    pub id: Uuid,
    pub habit_id: Option<Uuid>,
    pub reward_id: Option<Uuid>,
    pub amount: i32,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
}

#[derive(sqlx::FromRow)]
pub struct UserBalanceRow {
    pub soy_balance: f64,
    pub tofu_balance: f64,
}

#[derive(sqlx::FromRow)]
pub struct UserProfileRow {
    pub email: Option<String>,
    pub premium: bool,
}

#[derive(sqlx::FromRow)]
pub struct UserRow {
    pub id: Uuid,
    pub email: Option<String>,
    pub password: Option<String>,
    pub is_anonymous: bool,
    #[allow(dead_code)]
    pub device_id: Option<Uuid>,
    pub premium: bool,
}

#[derive(sqlx::FromRow)]
pub struct RefreshTokenRow {
    pub key: String,
    #[allow(dead_code)]
    pub created_at: NaiveDateTime,
    pub expires_at: Option<NaiveDateTime>,
}

#[derive(sqlx::FromRow)]
pub struct HabitRow {
    pub id: Uuid,
    pub name: String,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub hidden_until: Option<NaiveDateTime>,
    pub description: String,
    pub min_daily_frequency: Option<f64>,
    pub difficulty_rank: Option<String>,
}

#[derive(sqlx::FromRow)]
pub struct RewardRow {
    pub id: Uuid,
    pub name: String,
    pub description: String,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub hidden_until: Option<NaiveDateTime>,
    pub max_daily_frequency: Option<f32>,
}

#[derive(sqlx::FromRow)]
pub struct TradeWithHabitRow {
    pub id: Uuid,
    pub created_at: NaiveDateTime,
    pub amount: i32,
    pub habit_id: Uuid,

    // Habit join
    pub habit_name: String,
    pub habit_created_at: NaiveDateTime,
    pub habit_updated_at: NaiveDateTime,
    pub habit_deleted_at: Option<NaiveDateTime>,
    pub habit_hidden_until: Option<NaiveDateTime>,
    pub habit_description: String,
    pub habit_min_daily_frequency: Option<f64>,
    pub habit_difficulty_rank: Option<String>,
}

#[derive(sqlx::FromRow)]
pub struct TradeWithRewardRow {
    pub id: Uuid,
    pub created_at: NaiveDateTime,
    pub amount: i32,
    pub reward_id: Uuid,

    // Reward join
    pub reward_name: String,
    pub reward_created_at: NaiveDateTime,
    pub reward_updated_at: NaiveDateTime,
    pub reward_deleted_at: Option<NaiveDateTime>,
    pub reward_hidden_until: Option<NaiveDateTime>,
    pub reward_description: String,
    pub reward_max_daily_frequency: Option<f32>,
}
