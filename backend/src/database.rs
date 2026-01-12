use crate::graphql::mutations::{CreateRewardInput, CreateTaskInput};
use chrono::NaiveDateTime;
use sqlx::{postgres::PgPoolOptions, Pool, Postgres};
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

    pub async fn create_task(
        &self,
        create_task_options: CreateTaskOptions,
    ) -> Result<TaskRow, sqlx::Error> {
        sqlx::query_as(
            "INSERT INTO tasks
            (user_id, name, hidden_until, due_by, description, min_daily_frequency, difficulty_rank, habit) VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING id, name, created_at, updated_at, deleted_at, hidden_until, due_by, description, min_daily_frequency, difficulty_rank, completed_at, habit",
        )
        .bind(create_task_options.user_id)
        .bind(create_task_options.name)
        .bind(create_task_options.hidden_until)
        .bind(create_task_options.due_by)
        .bind(create_task_options.description)
        .bind(create_task_options.min_daily_frequency)
        .bind(create_task_options.difficulty_rank)
        .bind(create_task_options.habit)
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

    pub async fn create_trade_with_task(
        &self,
        create_trade_options: CreateTradeWithTaskOptions,
    ) -> Result<TradeWithTaskRow, sqlx::Error> {
        sqlx::query_as(
            // We `SELECT $1, $2, $3` here instead of `SELECT column names`. This is valid SQL.
            // We do this because we can only do a where clause if we SELECT. We don't want
            // to use any of the values from the tasks table for the insert, so we just provide
            // literal values that, after the validation is done, gets used by the insert
            // statement.
            "WITH new_trade AS (
                INSERT INTO trades (task_id, amount, user_id)
                SELECT $1, $2, $3
                FROM tasks
                WHERE tasks.id = $1 AND tasks.user_id = $3
                RETURNING id, task_id, reward_id, amount, created_at
            )
            SELECT
                nt.*,
                t.name AS task_name, t.created_at AS task_created_at, t.updated_at AS task_updated_at, t.deleted_at AS task_deleted_at, t.hidden_until AS task_hidden_until, t.due_by AS task_due_by, t.description AS task_description, t.min_daily_frequency AS task_min_daily_frequency, t.difficulty_rank AS task_difficulty_rank, t.habit AS task_habit
            FROM new_trade nt
            JOIN tasks t ON nt.task_id = t.id",
        )
        .bind(create_trade_options.task_id)
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
                RETURNING id, task_id, reward_id, amount, created_at
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
        sqlx::query_as("SELECT id, email, password, is_anonymous, device_id FROM users WHERE email = $1")
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
            "SELECT id, email, password, is_anonymous, device_id FROM users WHERE device_id = $1",
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

    /// Get all tasks for a user, optionally filtered by updated_at > since
    pub async fn get_tasks_since(
        &self,
        user_id: Uuid,
        since: Option<NaiveDateTime>,
    ) -> Result<Vec<TaskRow>, sqlx::Error> {
        match since {
            Some(since_time) => {
                sqlx::query_as(
                    "SELECT id, name, created_at, updated_at, deleted_at, hidden_until, due_by, description, min_daily_frequency, difficulty_rank, completed_at, habit
                     FROM tasks
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
                    "SELECT id, name, created_at, updated_at, deleted_at, hidden_until, due_by, description, min_daily_frequency, difficulty_rank, completed_at, habit
                     FROM tasks
                     WHERE user_id = $1
                     ORDER BY updated_at ASC",
                )
                .bind(user_id)
                .fetch_all(&self.pool)
                .await
            }
        }
    }

    /// Upsert a task - insert if not exists, update if exists and belongs to user.
    /// Also transfers ownership from anonymous users to the authenticated user.
    pub async fn upsert_task(
        &self,
        user_id: Uuid,
        task: UpsertTaskOptions,
    ) -> Result<TaskRow, sqlx::Error> {
        // The condition for allowing updates: either the task belongs to this user,
        // OR the task belongs to an anonymous user (allowing transfer of ownership)
        sqlx::query_as(
            "INSERT INTO tasks (id, user_id, name, description, created_at, deleted_at, hidden_until, due_by, min_daily_frequency, difficulty_rank, completed_at, habit)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
             ON CONFLICT (id) DO UPDATE SET
                user_id = CASE
                    WHEN tasks.user_id = $2 THEN tasks.user_id
                    WHEN EXISTS (SELECT 1 FROM users WHERE id = tasks.user_id AND is_anonymous = true) THEN $2
                    ELSE tasks.user_id
                END,
                name = CASE
                    WHEN tasks.user_id = $2 OR EXISTS (SELECT 1 FROM users WHERE id = tasks.user_id AND is_anonymous = true) THEN EXCLUDED.name
                    ELSE tasks.name
                END,
                description = CASE
                    WHEN tasks.user_id = $2 OR EXISTS (SELECT 1 FROM users WHERE id = tasks.user_id AND is_anonymous = true) THEN EXCLUDED.description
                    ELSE tasks.description
                END,
                deleted_at = CASE
                    WHEN tasks.user_id = $2 OR EXISTS (SELECT 1 FROM users WHERE id = tasks.user_id AND is_anonymous = true) THEN EXCLUDED.deleted_at
                    ELSE tasks.deleted_at
                END,
                hidden_until = CASE
                    WHEN tasks.user_id = $2 OR EXISTS (SELECT 1 FROM users WHERE id = tasks.user_id AND is_anonymous = true) THEN EXCLUDED.hidden_until
                    ELSE tasks.hidden_until
                END,
                due_by = CASE
                    WHEN tasks.user_id = $2 OR EXISTS (SELECT 1 FROM users WHERE id = tasks.user_id AND is_anonymous = true) THEN EXCLUDED.due_by
                    ELSE tasks.due_by
                END,
                min_daily_frequency = CASE
                    WHEN tasks.user_id = $2 OR EXISTS (SELECT 1 FROM users WHERE id = tasks.user_id AND is_anonymous = true) THEN EXCLUDED.min_daily_frequency
                    ELSE tasks.min_daily_frequency
                END,
                difficulty_rank = CASE
                    WHEN tasks.user_id = $2 OR EXISTS (SELECT 1 FROM users WHERE id = tasks.user_id AND is_anonymous = true) THEN EXCLUDED.difficulty_rank
                    ELSE tasks.difficulty_rank
                END,
                completed_at = CASE
                    WHEN tasks.user_id = $2 OR EXISTS (SELECT 1 FROM users WHERE id = tasks.user_id AND is_anonymous = true) THEN EXCLUDED.completed_at
                    ELSE tasks.completed_at
                END,
                habit = CASE
                    WHEN tasks.user_id = $2 OR EXISTS (SELECT 1 FROM users WHERE id = tasks.user_id AND is_anonymous = true) THEN EXCLUDED.habit
                    ELSE tasks.habit
                END
             RETURNING id, name, created_at, updated_at, deleted_at, hidden_until, due_by, description, min_daily_frequency, difficulty_rank, completed_at, habit",
        )
        .bind(task.id)
        .bind(user_id)
        .bind(&task.name)
        .bind(&task.description)
        .bind(task.created_at)
        .bind(task.deleted_at)
        .bind(task.hidden_until)
        .bind(task.due_by)
        .bind(task.min_daily_frequency)
        .bind(&task.difficulty_rank)
        .bind(task.completed_at)
        .bind(task.habit)
        .fetch_one(&self.pool)
        .await
    }

    /// Get a single task by ID for a specific user
    pub async fn get_task_by_id(
        &self,
        user_id: Uuid,
        task_id: Uuid,
    ) -> Result<Option<TaskRow>, sqlx::Error> {
        sqlx::query_as(
            "SELECT id, name, created_at, updated_at, deleted_at, hidden_until, due_by, description, min_daily_frequency, difficulty_rank, completed_at, habit
             FROM tasks
             WHERE id = $1 AND user_id = $2",
        )
        .bind(task_id)
        .bind(user_id)
        .fetch_optional(&self.pool)
        .await
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
                    "SELECT id, task_id, reward_id, amount, created_at, updated_at, deleted_at
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
                    "SELECT id, task_id, reward_id, amount, created_at, updated_at, deleted_at
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

    /// Upsert a trade and update user balance atomically.
    /// Returns the trade and the new balance.
    pub async fn upsert_trade_and_update_balance(
        &self,
        user_id: Uuid,
        trade: UpsertTradeOptions,
    ) -> Result<(TradeRow, f64), sqlx::Error> {
        // Use a transaction to ensure atomicity
        let mut tx = self.pool.begin().await?;

        // Check if trade already exists
        let existing_trade: Option<TradeRow> = sqlx::query_as(
            "SELECT id, task_id, reward_id, amount, created_at, updated_at, deleted_at
             FROM trades WHERE id = $1 AND user_id = $2",
        )
        .bind(trade.id)
        .bind(user_id)
        .fetch_optional(&mut *tx)
        .await?;

        let trade_row: TradeRow;
        let balance_delta: i32;

        if let Some(existing) = existing_trade {
            // Trade exists - check if we're soft-deleting or undeleting
            let was_deleted = existing.deleted_at.is_some();
            let is_deleting = trade.deleted_at.is_some();

            if was_deleted && !is_deleting {
                // Undeleting - add amount back
                balance_delta = trade.amount;
            } else if !was_deleted && is_deleting {
                // Deleting - remove amount
                balance_delta = -existing.amount;
            } else {
                // No change to deletion status - no balance change
                balance_delta = 0;
            }

            // Update the trade
            trade_row = sqlx::query_as(
                "UPDATE trades SET deleted_at = $3
                 WHERE id = $1 AND user_id = $2
                 RETURNING id, task_id, reward_id, amount, created_at, updated_at, deleted_at",
            )
            .bind(trade.id)
            .bind(user_id)
            .bind(trade.deleted_at)
            .fetch_one(&mut *tx)
            .await?;
        } else {
            // New trade - validate task belongs to user or anonymous user
            if let Some(task_id) = trade.task_id {
                let task_valid: Option<(Uuid,)> = sqlx::query_as(
                    "SELECT id FROM tasks
                     WHERE id = $1 AND (user_id = $2 OR EXISTS (SELECT 1 FROM users WHERE id = tasks.user_id AND is_anonymous = true))",
                )
                .bind(task_id)
                .bind(user_id)
                .fetch_optional(&mut *tx)
                .await?;

                if task_valid.is_none() {
                    return Err(sqlx::Error::RowNotFound);
                }
            }

            // Validate reward belongs to user
            if let Some(reward_id) = trade.reward_id {
                let reward_valid: Option<(Uuid,)> = sqlx::query_as(
                    "SELECT id FROM rewards WHERE id = $1 AND user_id = $2",
                )
                .bind(reward_id)
                .bind(user_id)
                .fetch_optional(&mut *tx)
                .await?;

                if reward_valid.is_none() {
                    return Err(sqlx::Error::RowNotFound);
                }
            }

            // Insert the trade
            trade_row = sqlx::query_as(
                "INSERT INTO trades (id, user_id, task_id, reward_id, amount, created_at, deleted_at)
                 VALUES ($1, $2, $3, $4, $5, $6, $7)
                 RETURNING id, task_id, reward_id, amount, created_at, updated_at, deleted_at",
            )
            .bind(trade.id)
            .bind(user_id)
            .bind(trade.task_id)
            .bind(trade.reward_id)
            .bind(trade.amount)
            .bind(trade.created_at)
            .bind(trade.deleted_at)
            .fetch_one(&mut *tx)
            .await?;

            // Only add to balance if not soft-deleted
            balance_delta = if trade.deleted_at.is_none() {
                trade.amount
            } else {
                0
            };
        }

        // Update user balance
        let (new_balance,): (f64,) = sqlx::query_as(
            "UPDATE users SET soy_balance = soy_balance + $2 WHERE id = $1 RETURNING soy_balance",
        )
        .bind(user_id)
        .bind(balance_delta)
        .fetch_one(&mut *tx)
        .await?;

        tx.commit().await?;

        Ok((trade_row, new_balance))
    }

    /// Get user balance
    pub async fn get_user_balance(&self, user_id: Uuid) -> Result<UserBalanceRow, sqlx::Error> {
        sqlx::query_as("SELECT soy_balance, tofu_balance FROM users WHERE id = $1")
            .bind(user_id)
            .fetch_one(&self.pool)
            .await
    }
}

pub struct CreateTaskOptions {
    pub user_id: Uuid,
    pub name: String,
    pub hidden_until: Option<NaiveDateTime>,
    pub due_by: Option<NaiveDateTime>,
    pub description: String,
    pub min_daily_frequency: Option<f64>,
    pub difficulty_rank: Option<String>,
    pub habit: bool,
}
impl CreateTaskOptions {
    pub fn new(input: CreateTaskInput, user_id: Uuid) -> Self {
        Self {
            user_id,
            name: input.name,
            hidden_until: input.hidden_until,
            due_by: input.due_by,
            description: input.description,
            min_daily_frequency: input.min_daily_frequency,
            difficulty_rank: input.difficulty_rank,
            habit: input.habit,
        }
    }
}

pub struct CreateTradeWithTaskOptions {
    user_id: Uuid,
    task_id: Uuid,
    amount: i32,
}
impl CreateTradeWithTaskOptions {
    pub fn new(user_id: Uuid, task_id: Uuid, amount: i32) -> Self {
        Self {
            user_id: user_id,
            task_id: task_id,
            amount: amount,
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
            user_id: user_id,
            reward_id: reward_id,
            amount: amount,
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
impl CreateRewardOptions {
    pub fn new(input: CreateRewardInput, user_id: Uuid) -> Self {
        Self {
            user_id,
            name: input.name,
            hidden_until: input.hidden_until,
            description: input.description,
            max_daily_frequency: input.max_daily_frequency,
        }
    }
}

pub struct UpsertTaskOptions {
    pub id: Uuid,
    pub name: String,
    pub description: String,
    pub created_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub hidden_until: Option<NaiveDateTime>,
    pub due_by: Option<NaiveDateTime>,
    pub min_daily_frequency: Option<f64>,
    pub difficulty_rank: Option<String>,
    pub completed_at: Option<NaiveDateTime>,
    pub habit: bool,
}

pub struct UpsertTradeOptions {
    pub id: Uuid,
    pub task_id: Option<Uuid>,
    pub reward_id: Option<Uuid>,
    pub amount: i32,
    pub created_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
}

#[derive(sqlx::FromRow)]
pub struct TradeRow {
    pub id: Uuid,
    pub task_id: Option<Uuid>,
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
pub struct UserRow {
    pub id: Uuid,
    #[allow(dead_code)]
    pub email: Option<String>,
    pub password: Option<String>,
    pub is_anonymous: bool,
    #[allow(dead_code)]
    pub device_id: Option<Uuid>,
}

#[derive(sqlx::FromRow)]
pub struct RefreshTokenRow {
    pub key: String,
    #[allow(dead_code)]
    pub created_at: NaiveDateTime,
    pub expires_at: Option<NaiveDateTime>,
}

#[derive(sqlx::FromRow)]
pub struct TaskRow {
    pub id: Uuid,
    pub name: String,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub hidden_until: Option<NaiveDateTime>,
    pub due_by: Option<NaiveDateTime>,
    pub description: String,
    pub min_daily_frequency: Option<f64>,
    pub difficulty_rank: Option<String>,
    pub completed_at: Option<NaiveDateTime>,
    pub habit: bool,
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
pub struct TradeWithTaskRow {
    pub id: Uuid,
    pub created_at: NaiveDateTime,
    pub amount: i32,
    pub task_id: Uuid,

    // Task join
    pub task_name: String,
    pub task_created_at: NaiveDateTime,
    pub task_updated_at: NaiveDateTime,
    pub task_deleted_at: Option<NaiveDateTime>,
    pub task_hidden_until: Option<NaiveDateTime>,
    pub task_due_by: Option<NaiveDateTime>,
    pub task_description: String,
    pub task_min_daily_frequency: Option<f64>,
    pub task_difficulty_rank: Option<String>,
    pub task_habit: bool,
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
