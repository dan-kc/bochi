use chrono::NaiveDateTime;
use serde::{Deserialize, Serialize};
use sqlx::{postgres::PgPoolOptions, Pool, Postgres, Transaction};
use url::form_urlencoded;
use uuid::Uuid;

#[derive(Clone, Copy, Debug, Deserialize, Serialize, Eq, PartialEq, sqlx::Type)]
#[serde(rename_all = "snake_case")]
#[sqlx(type_name = "habit_difficulty_tier", rename_all = "snake_case")]
pub enum HabitDifficultyTier {
    Trivial,
    Light,
    Medium,
    Hard,
    Extreme,
}

#[derive(Clone, Copy, Debug, Deserialize, Serialize, Eq, PartialEq, sqlx::Type)]
#[serde(rename_all = "snake_case")]
#[sqlx(type_name = "reward_damage_tier", rename_all = "snake_case")]
pub enum RewardDamageTier {
    Harmless,
    Light,
    Medium,
    Heavy,
    Extreme,
}

#[derive(Clone)]
pub struct Database {
    pool: Pool<Postgres>,
}

fn active_unresolved_task_trade_exists_sql(task_id_expr: &str, user_id_expr: &str) -> String {
    format!(
        "EXISTS (
            SELECT 1
            FROM trades task_trade
            WHERE task_trade.user_id = {user_id_expr}
              AND task_trade.task_id = {task_id_expr}
              AND task_trade.deleted_at IS NULL
              AND task_trade.refunds_trade_id IS NULL
              AND NOT EXISTS (
                SELECT 1
                FROM trades refund
                WHERE refund.refunds_trade_id = task_trade.id
                  AND refund.deleted_at IS NULL
              )
        )"
    )
}

fn derived_task_completed_at_sql(task_id_expr: &str, user_id_expr: &str) -> String {
    format!(
        "(SELECT task_trade.created_at
          FROM trades task_trade
          WHERE task_trade.user_id = {user_id_expr}
            AND task_trade.task_id = {task_id_expr}
            AND task_trade.deleted_at IS NULL
            AND task_trade.refunds_trade_id IS NULL
            AND NOT EXISTS (
              SELECT 1
              FROM trades refund
              WHERE refund.refunds_trade_id = task_trade.id
                AND refund.deleted_at IS NULL
            )
          ORDER BY task_trade.created_at DESC, task_trade.updated_at DESC, task_trade.id DESC
          LIMIT 1)"
    )
}

pub(crate) fn task_select_columns(task_alias: &str, user_id_expr: &str) -> String {
    let task_id_expr = format!("{task_alias}.id");
    format!(
        "{task_alias}.id,
         {task_alias}.name,
         {task_alias}.description,
         {task_alias}.created_at,
         {task_alias}.updated_at,
         {task_alias}.deleted_at,
         {} AS completed_at,
         {task_alias}.difficulty_tier,
         {task_alias}.duration_seconds,
         {task_alias}.skip_consequence,
         {task_alias}.due_date",
        derived_task_completed_at_sql(&task_id_expr, user_id_expr)
    )
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
            (user_id, name, description, min_daily_frequency, difficulty_tier, duration_seconds, lockout_duration_seconds, skip_consequence)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
            RETURNING id, name, created_at, updated_at, deleted_at, description, min_daily_frequency, difficulty_tier, duration_seconds, lockout_duration_seconds, skip_consequence",
        )
        .bind(create_habit_options.user_id)
        .bind(create_habit_options.name)
        .bind(create_habit_options.description)
        .bind(create_habit_options.min_daily_frequency)
        .bind(create_habit_options.difficulty_tier)
        .bind(create_habit_options.duration_seconds)
        .bind(create_habit_options.lockout_duration_seconds)
        .bind(create_habit_options.skip_consequence)
        .fetch_one(&self.pool)
        .await
    }

    pub async fn create_task(
        &self,
        create_task_options: CreateTaskOptions,
    ) -> Result<TaskRow, sqlx::Error> {
        sqlx::query_as(
            "INSERT INTO tasks
            (user_id, name, description, difficulty_tier, duration_seconds, skip_consequence, due_date)
            VALUES ($1, $2, $3, $4, $5, $6, $7)
            RETURNING id, name, description, created_at, updated_at, deleted_at, completed_at, difficulty_tier, duration_seconds, skip_consequence, due_date",
        )
        .bind(create_task_options.user_id)
        .bind(create_task_options.name)
        .bind(create_task_options.description)
        .bind(create_task_options.difficulty_tier)
        .bind(create_task_options.duration_seconds)
        .bind(create_task_options.skip_consequence)
        .bind(create_task_options.due_date)
        .fetch_one(&self.pool)
        .await
    }

    pub async fn get_task_for_user(
        &self,
        user_id: Uuid,
        task_id: Uuid,
    ) -> Result<TaskRow, sqlx::Error> {
        let query = format!(
            "SELECT {}
             FROM tasks
             WHERE id = $1 AND user_id = $2",
            task_select_columns("tasks", "tasks.user_id")
        );
        sqlx::query_as(&query)
            .bind(task_id)
            .bind(user_id)
            .fetch_one(&self.pool)
            .await
    }

    pub async fn task_has_incomplete_dependencies(
        &self,
        user_id: Uuid,
        task_id: Uuid,
    ) -> Result<bool, sqlx::Error> {
        let mut tx = self.pool.begin().await?;
        let blocked = Self::task_has_incomplete_dependencies_tx(&mut tx, user_id, task_id).await?;
        tx.rollback().await?;
        Ok(blocked)
    }

    pub async fn create_reward(
        &self,
        create_reward_options: CreateRewardOptions,
    ) -> Result<RewardRow, sqlx::Error> {
        sqlx::query_as(
            "INSERT INTO rewards
            (user_id, name, description, max_daily_frequency, damage_tier) VALUES ($1, $2, $3, $4, $5) RETURNING id, name, description, created_at, updated_at, deleted_at, max_daily_frequency, damage_tier",
        )
        .bind(create_reward_options.user_id)
        .bind(create_reward_options.name)
        .bind(create_reward_options.description)
        .bind(create_reward_options.max_daily_frequency)
        .bind(create_reward_options.damage_tier)
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
                INSERT INTO trades (habit_id, source_name, amount, user_id)
                SELECT $1, habits.name, $2, $3
                FROM habits
                WHERE habits.id = $1 AND habits.user_id = $3
                RETURNING id, habit_id, reward_id, amount, created_at
            )
            SELECT
                nt.*,
                h.name AS habit_name, h.created_at AS habit_created_at, h.updated_at AS habit_updated_at, h.deleted_at AS habit_deleted_at, h.description AS habit_description, h.min_daily_frequency AS habit_min_daily_frequency, h.difficulty_tier AS habit_difficulty_tier, h.duration_seconds AS habit_duration_seconds, h.lockout_duration_seconds AS habit_lockout_duration_seconds, h.skip_consequence AS habit_skip_consequence
            FROM new_trade nt
            JOIN habits h ON nt.habit_id = h.id",
        )
        .bind(create_trade_options.habit_id)
        .bind(create_trade_options.amount)
        .bind(create_trade_options.user_id)
        .fetch_one(&self.pool)
        .await
    }

    pub async fn create_trade_with_task(
        &self,
        create_trade_options: CreateTradeWithTaskOptions,
    ) -> Result<TradeWithTaskRow, sqlx::Error> {
        let query = format!(
            "WITH candidate_task AS (
                SELECT id, name, description, created_at, updated_at, deleted_at, difficulty_tier, duration_seconds, skip_consequence, due_date
                FROM tasks
                WHERE tasks.id = $1
                  AND tasks.user_id = $3
                  AND tasks.deleted_at IS NULL
                  AND NOT {}
            ),
            new_trade AS (
                INSERT INTO trades (task_id, source_name, amount, user_id)
                SELECT id, name, $2, $3
                FROM candidate_task
                RETURNING id, task_id, habit_id, reward_id, amount, created_at
            )
            SELECT
                nt.id,
                nt.created_at,
                nt.amount,
                nt.task_id,
                t.name AS task_name,
                t.description AS task_description,
                t.created_at AS task_created_at,
                t.updated_at AS task_updated_at,
                t.deleted_at AS task_deleted_at,
                nt.created_at AS task_completed_at,
                t.difficulty_tier AS task_difficulty_tier,
                t.duration_seconds AS task_duration_seconds,
                t.skip_consequence AS task_skip_consequence,
                t.due_date AS task_due_date
            FROM new_trade nt
            JOIN candidate_task t ON nt.task_id = t.id",
            active_unresolved_task_trade_exists_sql("tasks.id", "tasks.user_id")
        );
        sqlx::query_as(&query)
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
                INSERT INTO trades (reward_id, source_name, amount, user_id)
                SELECT $1, rewards.name, $2, $3
                FROM rewards
                WHERE rewards.id = $1 AND rewards.user_id = $3
                RETURNING id, habit_id, reward_id, amount, created_at
            )
            SELECT
                nt.*,
                r.name AS reward_name, r.created_at AS reward_created_at, r.updated_at AS reward_updated_at, r.deleted_at AS reward_deleted_at, r.description AS reward_description, r.max_daily_frequency as reward_max_daily_frequency, r.damage_tier AS reward_damage_tier
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
        sqlx::query_as(
            "SELECT
                id,
                email,
                password
             FROM users
             WHERE email = $1",
        )
        .bind(email)
        .fetch_optional(&self.pool)
        .await?
        .ok_or(sqlx::Error::RowNotFound)
    }

    /// Returns the user by ID.
    pub async fn get_user_by_id(&self, user_id: Uuid) -> Result<UserRow, sqlx::Error> {
        sqlx::query_as(
            "SELECT
                id,
                email,
                password
             FROM users
             WHERE id = $1",
        )
        .bind(user_id)
        .fetch_optional(&self.pool)
        .await?
        .ok_or(sqlx::Error::RowNotFound)
    }

    /// Updates a user's password.
    pub async fn update_user_password(
        &self,
        user_id: Uuid,
        hashed_password: &str,
    ) -> Result<(), sqlx::Error> {
        let result = sqlx::query("UPDATE users SET password = $2 WHERE id = $1")
            .bind(user_id)
            .bind(hashed_password)
            .execute(&self.pool)
            .await?;

        if result.rows_affected() == 0 {
            return Err(sqlx::Error::RowNotFound);
        }

        Ok(())
    }

    /// Updates a user's email.
    pub async fn update_user_email(&self, user_id: Uuid, email: &str) -> Result<(), sqlx::Error> {
        let result = sqlx::query("UPDATE users SET email = $2 WHERE id = $1")
            .bind(user_id)
            .bind(email)
            .execute(&self.pool)
            .await?;

        if result.rows_affected() == 0 {
            return Err(sqlx::Error::RowNotFound);
        }

        Ok(())
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
        let select_columns = task_select_columns("tasks", "tasks.user_id");
        match since {
            Some(since_time) => {
                let query = format!(
                    "SELECT {}
                     FROM tasks
                     WHERE user_id = $1 AND updated_at > $2
                     ORDER BY updated_at ASC",
                    select_columns
                );
                sqlx::query_as(&query)
                    .bind(user_id)
                    .bind(since_time)
                    .fetch_all(&self.pool)
                    .await
            }
            None => {
                let query = format!(
                    "SELECT {}
                     FROM tasks
                     WHERE user_id = $1
                     ORDER BY updated_at ASC",
                    select_columns
                );
                sqlx::query_as(&query)
                    .bind(user_id)
                    .fetch_all(&self.pool)
                    .await
            }
        }
    }

    /// Get all habits for a user, optionally filtered by updated_at > since
    pub async fn get_habits_since(
        &self,
        user_id: Uuid,
        since: Option<NaiveDateTime>,
    ) -> Result<Vec<HabitRow>, sqlx::Error> {
        match since {
            Some(since_time) => {
                sqlx::query_as(
                    "SELECT id, name, created_at, updated_at, deleted_at, description, min_daily_frequency, difficulty_tier, duration_seconds, lockout_duration_seconds, skip_consequence
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
                    "SELECT id, name, created_at, updated_at, deleted_at, description, min_daily_frequency, difficulty_tier, duration_seconds, lockout_duration_seconds, skip_consequence
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
                    "SELECT id, task_id, habit_id, reward_id, source_name, amount, created_at, updated_at, deleted_at, refunds_trade_id
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
                    "SELECT id, task_id, habit_id, reward_id, source_name, amount, created_at, updated_at, deleted_at, refunds_trade_id
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

    /// Calculate a user's balance directly from non-deleted ledger entries.
    pub async fn calculate_balance_from_trades(&self, user_id: Uuid) -> Result<f64, sqlx::Error> {
        let (total,): (Option<i64>,) = sqlx::query_as(
            "SELECT COALESCE(SUM(amount), 0)
             FROM trades
             WHERE user_id = $1 AND deleted_at IS NULL",
        )
        .bind(user_id)
        .fetch_one(&self.pool)
        .await?;

        Ok(total.unwrap_or(0) as f64)
    }

    /// Get user profile (email, entitlement state, and general difficulty)
    pub async fn get_user_profile(&self, user_id: Uuid) -> Result<UserProfileRow, sqlx::Error> {
        sqlx::query_as(
            "SELECT
                email,
                general_difficulty,
                subscription_status
             FROM users
             WHERE id = $1",
        )
        .bind(user_id)
        .fetch_one(&self.pool)
        .await
    }

    /// Get the account-level auth and subscription state needed by the client.
    pub async fn get_user_account_state(
        &self,
        user_id: Uuid,
    ) -> Result<UserAccountStateRow, sqlx::Error> {
        sqlx::query_as(
            "SELECT
                email,
                subscription_source,
                subscription_status,
                subscription_expires_at
             FROM users
             WHERE id = $1",
        )
        .bind(user_id)
        .fetch_one(&self.pool)
        .await
    }

    /// Returns the user who already owns a given Apple original transaction, if any.
    pub async fn get_user_id_from_app_store_original_transaction_id(
        &self,
        original_transaction_id: &str,
    ) -> Result<Option<Uuid>, sqlx::Error> {
        let row: Option<(Uuid,)> = sqlx::query_as(
            "SELECT id
             FROM users
             WHERE app_store_original_transaction_id = $1",
        )
        .bind(original_transaction_id)
        .fetch_optional(&self.pool)
        .await?;

        Ok(row.map(|(id,)| id))
    }

    /// Attaches an Apple subscription to the given user account and returns
    /// the client-facing account state after linking.
    pub async fn link_apple_subscription(
        &self,
        user_id: Uuid,
        original_transaction_id: &str,
        subscription_status: &str,
        subscription_expires_at: Option<NaiveDateTime>,
    ) -> Result<UserAccountStateRow, sqlx::Error> {
        sqlx::query_as(
            "UPDATE users
             SET subscription_source = 'apple',
                 subscription_status = $2,
                 subscription_expires_at = $3,
                 app_store_original_transaction_id = $4
             WHERE id = $1
             RETURNING email, subscription_source, subscription_status, subscription_expires_at",
        )
        .bind(user_id)
        .bind(subscription_status)
        .bind(subscription_expires_at)
        .bind(original_transaction_id)
        .fetch_one(&self.pool)
        .await
    }

    /// Update general_difficulty within a transaction
    pub async fn update_general_difficulty_tx(
        tx: &mut Transaction<'_, Postgres>,
        user_id: Uuid,
        general_difficulty: f64,
    ) -> Result<(), sqlx::Error> {
        sqlx::query("UPDATE users SET general_difficulty = $2 WHERE id = $1")
            .bind(user_id)
            .bind(general_difficulty)
            .execute(&mut **tx)
            .await?;
        Ok(())
    }

    // ============================================================================
    // Tag Sync Operations
    // ============================================================================

    /// Get all tags for a user, optionally filtered by updated_at > since
    pub async fn get_tags_since(
        &self,
        user_id: Uuid,
        since: Option<NaiveDateTime>,
    ) -> Result<Vec<TagRow>, sqlx::Error> {
        match since {
            Some(since_time) => {
                sqlx::query_as(
                    "SELECT id, name, color_hex, created_at, updated_at, deleted_at
                     FROM tags
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
                    "SELECT id, name, color_hex, created_at, updated_at, deleted_at
                     FROM tags
                     WHERE user_id = $1
                     ORDER BY updated_at ASC",
                )
                .bind(user_id)
                .fetch_all(&self.pool)
                .await
            }
        }
    }

    /// Get all habit_tags for a user's habits, optionally filtered by updated_at > since
    pub async fn get_habit_tags_since(
        &self,
        user_id: Uuid,
        since: Option<NaiveDateTime>,
    ) -> Result<Vec<HabitTagRow>, sqlx::Error> {
        match since {
            Some(since_time) => {
                sqlx::query_as(
                    "SELECT ht.habit_id, ht.tag_id, ht.created_at, ht.updated_at, ht.deleted_at
                     FROM habit_tags ht
                     JOIN habits h ON ht.habit_id = h.id
                     WHERE h.user_id = $1 AND ht.updated_at > $2
                     ORDER BY ht.updated_at ASC",
                )
                .bind(user_id)
                .bind(since_time)
                .fetch_all(&self.pool)
                .await
            }
            None => {
                sqlx::query_as(
                    "SELECT ht.habit_id, ht.tag_id, ht.created_at, ht.updated_at, ht.deleted_at
                     FROM habit_tags ht
                     JOIN habits h ON ht.habit_id = h.id
                     WHERE h.user_id = $1
                     ORDER BY ht.updated_at ASC",
                )
                .bind(user_id)
                .fetch_all(&self.pool)
                .await
            }
        }
    }

    /// Get all task_tags for a user's tasks, optionally filtered by updated_at > since
    pub async fn get_task_tags_since(
        &self,
        user_id: Uuid,
        since: Option<NaiveDateTime>,
    ) -> Result<Vec<TaskTagRow>, sqlx::Error> {
        match since {
            Some(since_time) => {
                sqlx::query_as(
                    "SELECT tt.task_id, tt.tag_id, tt.created_at, tt.updated_at, tt.deleted_at
                     FROM task_tags tt
                     JOIN tasks t ON tt.task_id = t.id
                     WHERE t.user_id = $1 AND tt.updated_at > $2
                     ORDER BY tt.updated_at ASC",
                )
                .bind(user_id)
                .bind(since_time)
                .fetch_all(&self.pool)
                .await
            }
            None => {
                sqlx::query_as(
                    "SELECT tt.task_id, tt.tag_id, tt.created_at, tt.updated_at, tt.deleted_at
                     FROM task_tags tt
                     JOIN tasks t ON tt.task_id = t.id
                     WHERE t.user_id = $1
                     ORDER BY tt.updated_at ASC",
                )
                .bind(user_id)
                .fetch_all(&self.pool)
                .await
            }
        }
    }

    /// Get all task_task_dependencies for a user's tasks, optionally filtered by updated_at > since
    pub async fn get_task_task_dependencies_since(
        &self,
        user_id: Uuid,
        since: Option<NaiveDateTime>,
    ) -> Result<Vec<TaskTaskDependencyRow>, sqlx::Error> {
        match since {
            Some(since_time) => {
                sqlx::query_as(
                    "SELECT ttd.task_id, ttd.depends_on_task_id, ttd.created_at, ttd.updated_at, ttd.deleted_at
                     FROM task_task_dependencies ttd
                     JOIN tasks t ON ttd.task_id = t.id
                     WHERE t.user_id = $1 AND ttd.updated_at > $2
                     ORDER BY ttd.updated_at ASC",
                )
                .bind(user_id)
                .bind(since_time)
                .fetch_all(&self.pool)
                .await
            }
            None => {
                sqlx::query_as(
                    "SELECT ttd.task_id, ttd.depends_on_task_id, ttd.created_at, ttd.updated_at, ttd.deleted_at
                     FROM task_task_dependencies ttd
                     JOIN tasks t ON ttd.task_id = t.id
                     WHERE t.user_id = $1
                     ORDER BY ttd.updated_at ASC",
                )
                .bind(user_id)
                .fetch_all(&self.pool)
                .await
            }
        }
    }

    /// Get all task_habit_dependencies for a user's tasks, optionally filtered by updated_at > since
    pub async fn get_task_habit_dependencies_since(
        &self,
        user_id: Uuid,
        since: Option<NaiveDateTime>,
    ) -> Result<Vec<TaskHabitDependencyRow>, sqlx::Error> {
        match since {
            Some(since_time) => {
                sqlx::query_as(
                    "SELECT thd.task_id, thd.habit_id, thd.required_completions, thd.baseline_completion_count, thd.created_at, thd.updated_at, thd.deleted_at
                     FROM task_habit_dependencies thd
                     JOIN tasks t ON thd.task_id = t.id
                     WHERE t.user_id = $1 AND thd.updated_at > $2
                     ORDER BY thd.updated_at ASC",
                )
                .bind(user_id)
                .bind(since_time)
                .fetch_all(&self.pool)
                .await
            }
            None => {
                sqlx::query_as(
                    "SELECT thd.task_id, thd.habit_id, thd.required_completions, thd.baseline_completion_count, thd.created_at, thd.updated_at, thd.deleted_at
                     FROM task_habit_dependencies thd
                     JOIN tasks t ON thd.task_id = t.id
                     WHERE t.user_id = $1
                     ORDER BY thd.updated_at ASC",
                )
                .bind(user_id)
                .fetch_all(&self.pool)
                .await
            }
        }
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
            "INSERT INTO habits (id, user_id, name, description, created_at, deleted_at, min_daily_frequency, difficulty_tier, duration_seconds, lockout_duration_seconds, skip_consequence)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
             ON CONFLICT (id) DO UPDATE SET
                user_id = CASE
                    WHEN habits.user_id = $2 THEN habits.user_id
                    ELSE habits.user_id
                END,
                name = CASE
                    WHEN habits.user_id = $2 THEN EXCLUDED.name
                    ELSE habits.name
                END,
                description = CASE
                    WHEN habits.user_id = $2 THEN EXCLUDED.description
                    ELSE habits.description
                END,
                deleted_at = CASE
                    WHEN habits.user_id = $2 THEN EXCLUDED.deleted_at
                    ELSE habits.deleted_at
                END,
                min_daily_frequency = CASE
                    WHEN habits.user_id = $2 THEN EXCLUDED.min_daily_frequency
                    ELSE habits.min_daily_frequency
                END,
                difficulty_tier = CASE
                    WHEN habits.user_id = $2 THEN EXCLUDED.difficulty_tier
                    ELSE habits.difficulty_tier
                END
                ,
                duration_seconds = CASE
                    WHEN habits.user_id = $2 THEN EXCLUDED.duration_seconds
                    ELSE habits.duration_seconds
                END,
                lockout_duration_seconds = CASE
                    WHEN habits.user_id = $2 THEN EXCLUDED.lockout_duration_seconds
                    ELSE habits.lockout_duration_seconds
                END,
                skip_consequence = CASE
                    WHEN habits.user_id = $2 THEN EXCLUDED.skip_consequence
                    ELSE habits.skip_consequence
                END
             RETURNING id, name, created_at, updated_at, deleted_at, description, min_daily_frequency, difficulty_tier, duration_seconds, lockout_duration_seconds, skip_consequence",
        )
        .bind(habit.id)
        .bind(user_id)
        .bind(&habit.name)
        .bind(&habit.description)
        .bind(habit.created_at)
        .bind(habit.deleted_at)
        .bind(habit.min_daily_frequency)
        .bind(habit.difficulty_tier)
        .bind(habit.duration_seconds)
        .bind(habit.lockout_duration_seconds)
        .bind(habit.skip_consequence)
        .fetch_one(&mut **tx)
        .await
    }

    /// Upsert a task within a transaction
    pub async fn upsert_task_tx(
        tx: &mut Transaction<'_, Postgres>,
        user_id: Uuid,
        task: &UpsertTaskOptions,
    ) -> Result<TaskRow, sqlx::Error> {
        sqlx::query_as(
            "INSERT INTO tasks (id, user_id, name, description, created_at, deleted_at, completed_at, difficulty_tier, duration_seconds, skip_consequence, due_date)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
             ON CONFLICT (id) DO UPDATE SET
                name = CASE WHEN tasks.user_id = $2 THEN EXCLUDED.name ELSE tasks.name END,
                description = CASE WHEN tasks.user_id = $2 THEN EXCLUDED.description ELSE tasks.description END,
                deleted_at = CASE WHEN tasks.user_id = $2 THEN EXCLUDED.deleted_at ELSE tasks.deleted_at END,
                difficulty_tier = CASE WHEN tasks.user_id = $2 THEN EXCLUDED.difficulty_tier ELSE tasks.difficulty_tier END,
                duration_seconds = CASE WHEN tasks.user_id = $2 THEN EXCLUDED.duration_seconds ELSE tasks.duration_seconds END,
                skip_consequence = CASE WHEN tasks.user_id = $2 THEN EXCLUDED.skip_consequence ELSE tasks.skip_consequence END,
                due_date = CASE WHEN tasks.user_id = $2 THEN EXCLUDED.due_date ELSE tasks.due_date END
             RETURNING id, name, description, created_at, updated_at, deleted_at, completed_at, difficulty_tier, duration_seconds, skip_consequence, due_date",
        )
        .bind(task.id)
        .bind(user_id)
        .bind(&task.name)
        .bind(&task.description)
        .bind(task.created_at)
        .bind(task.deleted_at)
        .bind(Option::<NaiveDateTime>::None)
        .bind(task.difficulty_tier)
        .bind(task.duration_seconds)
        .bind(task.skip_consequence)
        .bind(task.due_date)
        .fetch_one(&mut **tx)
        .await
    }

    /// Upsert a trade within a transaction.
    pub async fn upsert_trade_tx(
        tx: &mut Transaction<'_, Postgres>,
        user_id: Uuid,
        trade: &UpsertTradeOptions,
    ) -> Result<TradeRow, sqlx::Error> {
        let source_count = usize::from(trade.task_id.is_some())
            + usize::from(trade.habit_id.is_some())
            + usize::from(trade.reward_id.is_some());
        if source_count != 1 {
            return Err(sqlx::Error::Protocol(
                "Trade must reference exactly one source entity".into(),
            ));
        }

        // Validate task belongs to user if task_id is provided
        if let Some(task_id) = trade.task_id {
            let task_valid: Option<(Uuid,)> = sqlx::query_as(
                "SELECT id FROM tasks
                 WHERE id = $1 AND user_id = $2",
            )
            .bind(task_id)
            .bind(user_id)
            .fetch_optional(&mut **tx)
            .await?;

            if task_valid.is_none() {
                return Err(sqlx::Error::RowNotFound);
            }
        }

        // Validate habit belongs to user if habit_id is provided
        if let Some(habit_id) = trade.habit_id {
            let habit_valid: Option<(Uuid,)> = sqlx::query_as(
                "SELECT id FROM habits
                 WHERE id = $1 AND user_id = $2",
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
            let reward_valid: Option<(Uuid,)> =
                sqlx::query_as("SELECT id FROM rewards WHERE id = $1 AND user_id = $2")
                    .bind(reward_id)
                    .bind(user_id)
                    .fetch_optional(&mut **tx)
                    .await?;

            if reward_valid.is_none() {
                return Err(sqlx::Error::RowNotFound);
            }
        }

        if let Some(refunds_trade_id) = trade.refunds_trade_id {
            let refunded_trade: Option<TradeRow> = sqlx::query_as(
                "SELECT id, task_id, habit_id, reward_id, source_name, amount, created_at, updated_at, deleted_at, refunds_trade_id
                 FROM trades
                 WHERE id = $1 AND user_id = $2",
            )
            .bind(refunds_trade_id)
            .bind(user_id)
            .fetch_optional(&mut **tx)
            .await?;

            let refunded_trade = refunded_trade.ok_or(sqlx::Error::RowNotFound)?;

            if refunded_trade.deleted_at.is_some() || refunded_trade.refunds_trade_id.is_some() {
                return Err(sqlx::Error::Protocol(
                    "Refund trades must target an active non-refund trade".into(),
                ));
            }

            if refunded_trade.task_id != trade.task_id
                || refunded_trade.habit_id != trade.habit_id
                || refunded_trade.reward_id != trade.reward_id
            {
                return Err(sqlx::Error::Protocol(
                    "Refund trades must match the original trade source".into(),
                ));
            }

            if trade.amount != -refunded_trade.amount {
                return Err(sqlx::Error::Protocol(
                    "Refund trades must negate the original trade amount".into(),
                ));
            }

            if trade.created_at < refunded_trade.created_at {
                return Err(sqlx::Error::Protocol(
                    "Refund trades cannot be created before the original trade.".into(),
                ));
            }

            let latest_trade_id = Self::latest_unresolved_trade_id_for_source_tx(
                tx,
                user_id,
                trade.task_id,
                trade.habit_id,
                trade.reward_id,
            )
            .await?;

            if latest_trade_id != Some(refunds_trade_id) {
                return Err(sqlx::Error::Protocol(
                    "Refund trades may only reverse the latest unresolved trade for that source"
                        .into(),
                ));
            }
        }

        // Upsert the trade
        sqlx::query_as(
            "INSERT INTO trades (id, user_id, task_id, habit_id, reward_id, source_name, amount, created_at, deleted_at, refunds_trade_id)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
             ON CONFLICT (id) DO UPDATE SET
                source_name = EXCLUDED.source_name,
                deleted_at = EXCLUDED.deleted_at,
                refunds_trade_id = EXCLUDED.refunds_trade_id
             RETURNING id, task_id, habit_id, reward_id, source_name, amount, created_at, updated_at, deleted_at, refunds_trade_id",
        )
        .bind(trade.id)
        .bind(user_id)
        .bind(trade.task_id)
        .bind(trade.habit_id)
        .bind(trade.reward_id)
        .bind(&trade.source_name)
        .bind(trade.amount)
        .bind(trade.created_at)
        .bind(trade.deleted_at)
        .bind(trade.refunds_trade_id)
        .fetch_one(&mut **tx)
        .await
    }

    /// Upsert a task_tag association within a transaction
    pub async fn upsert_task_tag_tx(
        tx: &mut Transaction<'_, Postgres>,
        user_id: Uuid,
        task_tag: &UpsertTaskTagOptions,
    ) -> Result<TaskTagRow, sqlx::Error> {
        let task_valid: Option<(Uuid,)> =
            sqlx::query_as("SELECT id FROM tasks WHERE id = $1 AND user_id = $2")
                .bind(task_tag.task_id)
                .bind(user_id)
                .fetch_optional(&mut **tx)
                .await?;

        if task_valid.is_none() {
            return Err(sqlx::Error::RowNotFound);
        }

        let tag_valid: Option<(Uuid,)> =
            sqlx::query_as("SELECT id FROM tags WHERE id = $1 AND user_id = $2")
                .bind(task_tag.tag_id)
                .bind(user_id)
                .fetch_optional(&mut **tx)
                .await?;

        if tag_valid.is_none() {
            return Err(sqlx::Error::RowNotFound);
        }

        sqlx::query_as(
            "INSERT INTO task_tags (task_id, tag_id, created_at, deleted_at)
             VALUES ($1, $2, $3, $4)
             ON CONFLICT (task_id, tag_id) DO UPDATE SET
                deleted_at = EXCLUDED.deleted_at
             RETURNING task_id, tag_id, created_at, updated_at, deleted_at",
        )
        .bind(task_tag.task_id)
        .bind(task_tag.tag_id)
        .bind(task_tag.created_at)
        .bind(task_tag.deleted_at)
        .fetch_one(&mut **tx)
        .await
    }

    /// Upsert a task-task dependency within a transaction
    pub async fn upsert_task_task_dependency_tx(
        tx: &mut Transaction<'_, Postgres>,
        user_id: Uuid,
        dependency: &UpsertTaskTaskDependencyOptions,
    ) -> Result<TaskTaskDependencyRow, sqlx::Error> {
        let task_valid: Option<(Uuid,)> =
            sqlx::query_as("SELECT id FROM tasks WHERE id = $1 AND user_id = $2")
                .bind(dependency.task_id)
                .bind(user_id)
                .fetch_optional(&mut **tx)
                .await?;

        if task_valid.is_none() {
            return Err(sqlx::Error::RowNotFound);
        }

        let depends_on_task_valid: Option<(Uuid,)> =
            sqlx::query_as("SELECT id FROM tasks WHERE id = $1 AND user_id = $2")
                .bind(dependency.depends_on_task_id)
                .bind(user_id)
                .fetch_optional(&mut **tx)
                .await?;

        if depends_on_task_valid.is_none() {
            return Err(sqlx::Error::RowNotFound);
        }

        sqlx::query_as(
            "INSERT INTO task_task_dependencies (task_id, depends_on_task_id, created_at, deleted_at)
             VALUES ($1, $2, $3, $4)
             ON CONFLICT (task_id, depends_on_task_id) DO UPDATE SET
                deleted_at = EXCLUDED.deleted_at
             RETURNING task_id, depends_on_task_id, created_at, updated_at, deleted_at",
        )
        .bind(dependency.task_id)
        .bind(dependency.depends_on_task_id)
        .bind(dependency.created_at)
        .bind(dependency.deleted_at)
        .fetch_one(&mut **tx)
        .await
    }

    /// Upsert a task-habit dependency within a transaction
    pub async fn upsert_task_habit_dependency_tx(
        tx: &mut Transaction<'_, Postgres>,
        user_id: Uuid,
        dependency: &UpsertTaskHabitDependencyOptions,
    ) -> Result<TaskHabitDependencyRow, sqlx::Error> {
        let task_valid: Option<(Uuid,)> =
            sqlx::query_as("SELECT id FROM tasks WHERE id = $1 AND user_id = $2")
                .bind(dependency.task_id)
                .bind(user_id)
                .fetch_optional(&mut **tx)
                .await?;

        if task_valid.is_none() {
            return Err(sqlx::Error::RowNotFound);
        }

        let habit_valid: Option<(Uuid,)> =
            sqlx::query_as("SELECT id FROM habits WHERE id = $1 AND user_id = $2")
                .bind(dependency.habit_id)
                .bind(user_id)
                .fetch_optional(&mut **tx)
                .await?;

        if habit_valid.is_none() {
            return Err(sqlx::Error::RowNotFound);
        }

        sqlx::query_as(
            "INSERT INTO task_habit_dependencies (task_id, habit_id, required_completions, baseline_completion_count, created_at, deleted_at)
             VALUES ($1, $2, $3, $4, $5, $6)
             ON CONFLICT (task_id, habit_id) DO UPDATE SET
                required_completions = EXCLUDED.required_completions,
                baseline_completion_count = EXCLUDED.baseline_completion_count,
                deleted_at = EXCLUDED.deleted_at
             RETURNING task_id, habit_id, required_completions, baseline_completion_count, created_at, updated_at, deleted_at",
        )
        .bind(dependency.task_id)
        .bind(dependency.habit_id)
        .bind(dependency.required_completions)
        .bind(dependency.baseline_completion_count)
        .bind(dependency.created_at)
        .bind(dependency.deleted_at)
        .fetch_one(&mut **tx)
        .await
    }

    async fn latest_unresolved_trade_id_for_source_tx(
        tx: &mut Transaction<'_, Postgres>,
        user_id: Uuid,
        task_id: Option<Uuid>,
        habit_id: Option<Uuid>,
        reward_id: Option<Uuid>,
    ) -> Result<Option<Uuid>, sqlx::Error> {
        sqlx::query_scalar(
            "SELECT candidate.id
             FROM trades candidate
             WHERE candidate.user_id = $1
               AND candidate.deleted_at IS NULL
               AND candidate.refunds_trade_id IS NULL
               AND candidate.task_id IS NOT DISTINCT FROM $2
               AND candidate.habit_id IS NOT DISTINCT FROM $3
               AND candidate.reward_id IS NOT DISTINCT FROM $4
               AND NOT EXISTS (
                    SELECT 1
                    FROM trades refund
                    WHERE refund.refunds_trade_id = candidate.id
                      AND refund.deleted_at IS NULL
               )
             ORDER BY candidate.created_at DESC, candidate.updated_at DESC, candidate.id DESC
             LIMIT 1",
        )
        .bind(user_id)
        .bind(task_id)
        .bind(habit_id)
        .bind(reward_id)
        .fetch_optional(&mut **tx)
        .await
    }

    pub async fn task_has_incomplete_dependencies_tx(
        tx: &mut Transaction<'_, Postgres>,
        user_id: Uuid,
        task_id: Uuid,
    ) -> Result<bool, sqlx::Error> {
        let dependency_task_is_completed = active_unresolved_task_trade_exists_sql(
            "dependency_task.id",
            "dependency_task.user_id",
        );
        let blocked_by_task: bool = sqlx::query_scalar(&format!(
            "SELECT EXISTS (
                SELECT 1
                FROM task_task_dependencies ttd
                JOIN tasks dependency_task ON dependency_task.id = ttd.depends_on_task_id
                WHERE ttd.task_id = $2
                  AND ttd.deleted_at IS NULL
                  AND dependency_task.user_id = $1
                  AND (dependency_task.deleted_at IS NOT NULL OR NOT {})
            )",
            dependency_task_is_completed
        ))
        .bind(user_id)
        .bind(task_id)
        .fetch_one(&mut **tx)
        .await?;

        if blocked_by_task {
            return Ok(true);
        }

        let blocked_by_habit: bool = sqlx::query_scalar(
            "SELECT EXISTS (
                SELECT 1
                FROM task_habit_dependencies thd
                WHERE thd.task_id = $2
                  AND thd.deleted_at IS NULL
                  AND (
                    SELECT COUNT(*)
                    FROM trades trade
                    WHERE trade.user_id = $1
                      AND trade.habit_id = thd.habit_id
                      AND trade.deleted_at IS NULL
                      AND trade.refunds_trade_id IS NULL
                      AND NOT EXISTS (
                        SELECT 1
                        FROM trades refund
                        WHERE refund.refunds_trade_id = trade.id
                          AND refund.deleted_at IS NULL
                      )
                  ) < (thd.baseline_completion_count + thd.required_completions)
            )",
        )
        .bind(user_id)
        .bind(task_id)
        .fetch_one(&mut **tx)
        .await?;

        Ok(blocked_by_habit)
    }

    pub async fn user_has_task_dependency_cycles_tx(
        tx: &mut Transaction<'_, Postgres>,
        user_id: Uuid,
    ) -> Result<bool, sqlx::Error> {
        sqlx::query_scalar(
            "WITH RECURSIVE reach(task_id, depends_on_task_id) AS (
                SELECT ttd.task_id, ttd.depends_on_task_id
                FROM task_task_dependencies ttd
                JOIN tasks t ON ttd.task_id = t.id
                WHERE t.user_id = $1
                  AND ttd.deleted_at IS NULL
                UNION
                SELECT reach.task_id, ttd.depends_on_task_id
                FROM reach
                JOIN task_task_dependencies ttd
                  ON ttd.task_id = reach.depends_on_task_id
                WHERE ttd.deleted_at IS NULL
            )
            SELECT EXISTS (
                SELECT 1
                FROM reach
                WHERE task_id = depends_on_task_id
            )",
        )
        .bind(user_id)
        .fetch_one(&mut **tx)
        .await
    }

    pub async fn soft_delete_task_task_dependencies_for_task_tx(
        tx: &mut Transaction<'_, Postgres>,
        user_id: Uuid,
        task_id: Uuid,
        deleted_at: NaiveDateTime,
    ) -> Result<Vec<TaskTaskDependencyRow>, sqlx::Error> {
        sqlx::query_as(
            "UPDATE task_task_dependencies ttd
             SET deleted_at = $3
             FROM tasks dependent_task
             WHERE dependent_task.id = ttd.task_id
               AND dependent_task.user_id = $1
               AND ttd.deleted_at IS NULL
               AND (ttd.task_id = $2 OR ttd.depends_on_task_id = $2)
             RETURNING ttd.task_id, ttd.depends_on_task_id, ttd.created_at, ttd.updated_at, ttd.deleted_at",
        )
        .bind(user_id)
        .bind(task_id)
        .bind(deleted_at)
        .fetch_all(&mut **tx)
        .await
    }

    pub async fn soft_delete_task_habit_dependencies_for_task_tx(
        tx: &mut Transaction<'_, Postgres>,
        user_id: Uuid,
        task_id: Uuid,
        deleted_at: NaiveDateTime,
    ) -> Result<Vec<TaskHabitDependencyRow>, sqlx::Error> {
        sqlx::query_as(
            "UPDATE task_habit_dependencies thd
             SET deleted_at = $3
             FROM tasks dependent_task
             WHERE dependent_task.id = thd.task_id
               AND dependent_task.user_id = $1
               AND thd.deleted_at IS NULL
               AND thd.task_id = $2
             RETURNING thd.task_id, thd.habit_id, thd.required_completions, thd.baseline_completion_count, thd.created_at, thd.updated_at, thd.deleted_at",
        )
        .bind(user_id)
        .bind(task_id)
        .bind(deleted_at)
        .fetch_all(&mut **tx)
        .await
    }

    pub async fn habit_has_active_dependents_tx(
        tx: &mut Transaction<'_, Postgres>,
        user_id: Uuid,
        habit_id: Uuid,
    ) -> Result<bool, sqlx::Error> {
        let dependent_task_is_completed =
            active_unresolved_task_trade_exists_sql("dependent_task.id", "dependent_task.user_id");
        sqlx::query_scalar(&format!(
            "SELECT EXISTS (
                SELECT 1
                FROM task_habit_dependencies thd
                JOIN tasks dependent_task ON dependent_task.id = thd.task_id
                WHERE thd.habit_id = $2
                  AND thd.deleted_at IS NULL
                  AND dependent_task.user_id = $1
                  AND dependent_task.deleted_at IS NULL
                  AND NOT {}
            )",
            dependent_task_is_completed
        ))
        .bind(user_id)
        .bind(habit_id)
        .fetch_one(&mut **tx)
        .await
    }

    /// Calculate a user's balance from non-deleted ledger rows within a transaction.
    pub async fn calculate_balance_from_trades_tx(
        tx: &mut Transaction<'_, Postgres>,
        user_id: Uuid,
    ) -> Result<f64, sqlx::Error> {
        let (total,): (Option<i64>,) = sqlx::query_as(
            "SELECT COALESCE(SUM(amount), 0)
             FROM trades
             WHERE user_id = $1 AND deleted_at IS NULL",
        )
        .bind(user_id)
        .fetch_one(&mut **tx)
        .await?;

        Ok(total.unwrap_or(0) as f64)
    }

    /// Upsert a tag within a transaction
    pub async fn upsert_tag_tx(
        tx: &mut Transaction<'_, Postgres>,
        user_id: Uuid,
        tag: &UpsertTagOptions,
    ) -> Result<TagRow, sqlx::Error> {
        sqlx::query_as(
            "INSERT INTO tags (id, user_id, name, color_hex, created_at, deleted_at)
             VALUES ($1, $2, $3, $4, $5, $6)
             ON CONFLICT (id) DO UPDATE SET
                name = CASE WHEN tags.user_id = $2 THEN EXCLUDED.name ELSE tags.name END,
                color_hex = CASE WHEN tags.user_id = $2 THEN EXCLUDED.color_hex ELSE tags.color_hex END,
                deleted_at = CASE WHEN tags.user_id = $2 THEN EXCLUDED.deleted_at ELSE tags.deleted_at END
             RETURNING id, name, color_hex, created_at, updated_at, deleted_at",
        )
        .bind(tag.id)
        .bind(user_id)
        .bind(&tag.name)
        .bind(&tag.color_hex)
        .bind(tag.created_at)
        .bind(tag.deleted_at)
        .fetch_one(&mut **tx)
        .await
    }

    /// Upsert a habit_tag association within a transaction
    pub async fn upsert_habit_tag_tx(
        tx: &mut Transaction<'_, Postgres>,
        user_id: Uuid,
        habit_tag: &UpsertHabitTagOptions,
    ) -> Result<HabitTagRow, sqlx::Error> {
        // Validate habit belongs to user
        let habit_valid: Option<(Uuid,)> =
            sqlx::query_as("SELECT id FROM habits WHERE id = $1 AND user_id = $2")
                .bind(habit_tag.habit_id)
                .bind(user_id)
                .fetch_optional(&mut **tx)
                .await?;

        if habit_valid.is_none() {
            return Err(sqlx::Error::RowNotFound);
        }

        // Validate tag belongs to user
        let tag_valid: Option<(Uuid,)> =
            sqlx::query_as("SELECT id FROM tags WHERE id = $1 AND user_id = $2")
                .bind(habit_tag.tag_id)
                .bind(user_id)
                .fetch_optional(&mut **tx)
                .await?;

        if tag_valid.is_none() {
            return Err(sqlx::Error::RowNotFound);
        }

        sqlx::query_as(
            "INSERT INTO habit_tags (habit_id, tag_id, created_at, deleted_at)
             VALUES ($1, $2, $3, $4)
             ON CONFLICT (habit_id, tag_id) DO UPDATE SET
                deleted_at = EXCLUDED.deleted_at
             RETURNING habit_id, tag_id, created_at, updated_at, deleted_at",
        )
        .bind(habit_tag.habit_id)
        .bind(habit_tag.tag_id)
        .bind(habit_tag.created_at)
        .bind(habit_tag.deleted_at)
        .fetch_one(&mut **tx)
        .await
    }

    // ============================================================================
    // Reward Sync Operations
    // ============================================================================

    /// Get all rewards for a user, optionally filtered by updated_at > since
    pub async fn get_rewards_since(
        &self,
        user_id: Uuid,
        since: Option<NaiveDateTime>,
    ) -> Result<Vec<RewardRow>, sqlx::Error> {
        match since {
            Some(since_time) => {
                sqlx::query_as(
                    "SELECT id, name, description, created_at, updated_at, deleted_at, max_daily_frequency, damage_tier
                     FROM rewards
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
                    "SELECT id, name, description, created_at, updated_at, deleted_at, max_daily_frequency, damage_tier
                     FROM rewards
                     WHERE user_id = $1
                     ORDER BY updated_at ASC",
                )
                .bind(user_id)
                .fetch_all(&self.pool)
                .await
            }
        }
    }

    /// Get all reward_tags for a user's rewards, optionally filtered by updated_at > since
    pub async fn get_reward_tags_since(
        &self,
        user_id: Uuid,
        since: Option<NaiveDateTime>,
    ) -> Result<Vec<RewardTagRow>, sqlx::Error> {
        match since {
            Some(since_time) => {
                sqlx::query_as(
                    "SELECT rt.reward_id, rt.tag_id, rt.created_at, rt.updated_at, rt.deleted_at
                     FROM reward_tags rt
                     JOIN rewards r ON rt.reward_id = r.id
                     WHERE r.user_id = $1 AND rt.updated_at > $2
                     ORDER BY rt.updated_at ASC",
                )
                .bind(user_id)
                .bind(since_time)
                .fetch_all(&self.pool)
                .await
            }
            None => {
                sqlx::query_as(
                    "SELECT rt.reward_id, rt.tag_id, rt.created_at, rt.updated_at, rt.deleted_at
                     FROM reward_tags rt
                     JOIN rewards r ON rt.reward_id = r.id
                     WHERE r.user_id = $1
                     ORDER BY rt.updated_at ASC",
                )
                .bind(user_id)
                .fetch_all(&self.pool)
                .await
            }
        }
    }

    /// Upsert a reward within a transaction
    pub async fn upsert_reward_tx(
        tx: &mut Transaction<'_, Postgres>,
        user_id: Uuid,
        reward: &UpsertRewardOptions,
    ) -> Result<RewardRow, sqlx::Error> {
        sqlx::query_as(
            "INSERT INTO rewards (id, user_id, name, description, created_at, deleted_at, max_daily_frequency, damage_tier)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
             ON CONFLICT (id) DO UPDATE SET
                name = CASE WHEN rewards.user_id = $2 THEN EXCLUDED.name ELSE rewards.name END,
                description = CASE WHEN rewards.user_id = $2 THEN EXCLUDED.description ELSE rewards.description END,
                deleted_at = CASE WHEN rewards.user_id = $2 THEN EXCLUDED.deleted_at ELSE rewards.deleted_at END,
                max_daily_frequency = CASE WHEN rewards.user_id = $2 THEN EXCLUDED.max_daily_frequency ELSE rewards.max_daily_frequency END,
                damage_tier = CASE WHEN rewards.user_id = $2 THEN EXCLUDED.damage_tier ELSE rewards.damage_tier END
             RETURNING id, name, description, created_at, updated_at, deleted_at, max_daily_frequency, damage_tier",
        )
        .bind(reward.id)
        .bind(user_id)
        .bind(&reward.name)
        .bind(&reward.description)
        .bind(reward.created_at)
        .bind(reward.deleted_at)
        .bind(reward.max_daily_frequency)
        .bind(reward.damage_tier)
        .fetch_one(&mut **tx)
        .await
    }

    /// Upsert a reward_tag association within a transaction
    pub async fn upsert_reward_tag_tx(
        tx: &mut Transaction<'_, Postgres>,
        user_id: Uuid,
        reward_tag: &UpsertRewardTagOptions,
    ) -> Result<RewardTagRow, sqlx::Error> {
        // Validate reward belongs to user
        let reward_valid: Option<(Uuid,)> =
            sqlx::query_as("SELECT id FROM rewards WHERE id = $1 AND user_id = $2")
                .bind(reward_tag.reward_id)
                .bind(user_id)
                .fetch_optional(&mut **tx)
                .await?;

        if reward_valid.is_none() {
            return Err(sqlx::Error::RowNotFound);
        }

        // Validate tag belongs to user
        let tag_valid: Option<(Uuid,)> =
            sqlx::query_as("SELECT id FROM tags WHERE id = $1 AND user_id = $2")
                .bind(reward_tag.tag_id)
                .bind(user_id)
                .fetch_optional(&mut **tx)
                .await?;

        if tag_valid.is_none() {
            return Err(sqlx::Error::RowNotFound);
        }

        sqlx::query_as(
            "INSERT INTO reward_tags (reward_id, tag_id, created_at, deleted_at)
             VALUES ($1, $2, $3, $4)
             ON CONFLICT (reward_id, tag_id) DO UPDATE SET
                deleted_at = EXCLUDED.deleted_at
             RETURNING reward_id, tag_id, created_at, updated_at, deleted_at",
        )
        .bind(reward_tag.reward_id)
        .bind(reward_tag.tag_id)
        .bind(reward_tag.created_at)
        .bind(reward_tag.deleted_at)
        .fetch_one(&mut **tx)
        .await
    }
}

pub struct CreateTaskOptions {
    pub user_id: Uuid,
    pub name: String,
    pub description: String,
    pub difficulty_tier: Option<HabitDifficultyTier>,
    pub duration_seconds: Option<i32>,
    pub skip_consequence: Option<i16>,
    pub due_date: Option<NaiveDateTime>,
}

pub struct CreateHabitOptions {
    pub user_id: Uuid,
    pub name: String,
    pub description: String,
    pub min_daily_frequency: Option<f64>,
    pub difficulty_tier: Option<HabitDifficultyTier>,
    pub duration_seconds: Option<i32>,
    pub lockout_duration_seconds: Option<i32>,
    pub skip_consequence: Option<i16>,
}

pub struct CreateTradeWithTaskOptions {
    user_id: Uuid,
    task_id: Uuid,
    amount: i32,
}
impl CreateTradeWithTaskOptions {
    pub fn new(user_id: Uuid, task_id: Uuid, amount: i32) -> Self {
        Self {
            user_id,
            task_id,
            amount,
        }
    }
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
    pub max_daily_frequency: Option<f64>,
    pub damage_tier: Option<RewardDamageTier>,
}

pub struct UpsertTaskOptions {
    pub id: Uuid,
    pub name: String,
    pub description: String,
    pub created_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub difficulty_tier: Option<HabitDifficultyTier>,
    pub duration_seconds: Option<i32>,
    pub skip_consequence: Option<i16>,
    pub due_date: Option<NaiveDateTime>,
}

pub struct UpsertHabitOptions {
    pub id: Uuid,
    pub name: String,
    pub description: String,
    pub created_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub min_daily_frequency: Option<f64>,
    pub difficulty_tier: Option<HabitDifficultyTier>,
    pub duration_seconds: Option<i32>,
    pub lockout_duration_seconds: Option<i32>,
    pub skip_consequence: Option<i16>,
}

pub struct UpsertTradeOptions {
    pub id: Uuid,
    pub task_id: Option<Uuid>,
    pub habit_id: Option<Uuid>,
    pub reward_id: Option<Uuid>,
    pub source_name: Option<String>,
    pub amount: i32,
    pub created_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub refunds_trade_id: Option<Uuid>,
}

pub struct UpsertTagOptions {
    pub id: Uuid,
    pub name: String,
    pub color_hex: String,
    pub created_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
}

pub struct UpsertHabitTagOptions {
    pub habit_id: Uuid,
    pub tag_id: Uuid,
    pub created_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
}

pub struct UpsertTaskTagOptions {
    pub task_id: Uuid,
    pub tag_id: Uuid,
    pub created_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
}

pub struct UpsertTaskTaskDependencyOptions {
    pub task_id: Uuid,
    pub depends_on_task_id: Uuid,
    pub created_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
}

pub struct UpsertTaskHabitDependencyOptions {
    pub task_id: Uuid,
    pub habit_id: Uuid,
    pub required_completions: i32,
    pub baseline_completion_count: i32,
    pub created_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
}

pub struct UpsertRewardOptions {
    pub id: Uuid,
    pub name: String,
    pub description: String,
    pub created_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub max_daily_frequency: Option<f64>,
    pub damage_tier: Option<RewardDamageTier>,
}

pub struct UpsertRewardTagOptions {
    pub reward_id: Uuid,
    pub tag_id: Uuid,
    pub created_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
}

#[derive(sqlx::FromRow)]
pub struct TradeRow {
    pub id: Uuid,
    pub task_id: Option<Uuid>,
    pub habit_id: Option<Uuid>,
    pub reward_id: Option<Uuid>,
    pub source_name: Option<String>,
    pub amount: i32,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub refunds_trade_id: Option<Uuid>,
}

#[derive(sqlx::FromRow)]
pub struct UserProfileRow {
    pub email: Option<String>,
    pub general_difficulty: f64,
    pub subscription_status: String,
}

#[derive(sqlx::FromRow)]
pub struct UserRow {
    pub id: Uuid,
    pub email: Option<String>,
    pub password: Option<String>,
}

#[derive(sqlx::FromRow)]
pub struct UserAccountStateRow {
    pub email: Option<String>,
    pub subscription_source: Option<String>,
    pub subscription_status: String,
    pub subscription_expires_at: Option<NaiveDateTime>,
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
    pub description: String,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub completed_at: Option<NaiveDateTime>,
    pub difficulty_tier: Option<HabitDifficultyTier>,
    pub duration_seconds: Option<i32>,
    pub skip_consequence: Option<i16>,
    pub due_date: Option<NaiveDateTime>,
}

#[derive(sqlx::FromRow)]
pub struct HabitRow {
    pub id: Uuid,
    pub name: String,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub description: String,
    pub min_daily_frequency: Option<f64>,
    pub difficulty_tier: Option<HabitDifficultyTier>,
    pub duration_seconds: Option<i32>,
    pub lockout_duration_seconds: Option<i32>,
    pub skip_consequence: Option<i16>,
}

#[derive(sqlx::FromRow)]
pub struct RewardRow {
    pub id: Uuid,
    pub name: String,
    pub description: String,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub max_daily_frequency: Option<f64>,
    pub damage_tier: Option<RewardDamageTier>,
}

#[derive(sqlx::FromRow)]
pub struct TaskTagRow {
    pub task_id: Uuid,
    pub tag_id: Uuid,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
}

#[derive(sqlx::FromRow)]
pub struct TaskTaskDependencyRow {
    pub task_id: Uuid,
    pub depends_on_task_id: Uuid,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
}

#[derive(sqlx::FromRow)]
pub struct TaskHabitDependencyRow {
    pub task_id: Uuid,
    pub habit_id: Uuid,
    pub required_completions: i32,
    pub baseline_completion_count: i32,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
}

#[derive(sqlx::FromRow)]
pub struct RewardTagRow {
    pub reward_id: Uuid,
    pub tag_id: Uuid,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
}

#[derive(sqlx::FromRow)]
pub struct SpecialOfferRow {
    pub id: Uuid,
    pub task_id: Option<Uuid>,
    pub habit_id: Option<Uuid>,
    pub reward_id: Option<Uuid>,
    pub modifier_percent: i16,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub expires_at: NaiveDateTime,
}

#[derive(sqlx::FromRow)]
pub struct TradeWithTaskRow {
    pub id: Uuid,
    pub created_at: NaiveDateTime,
    pub amount: i32,
    pub task_id: Uuid,

    pub task_name: String,
    pub task_created_at: NaiveDateTime,
    pub task_updated_at: NaiveDateTime,
    pub task_deleted_at: Option<NaiveDateTime>,
    pub task_completed_at: Option<NaiveDateTime>,
    pub task_description: String,
    pub task_difficulty_tier: Option<HabitDifficultyTier>,
    pub task_duration_seconds: Option<i32>,
    pub task_skip_consequence: Option<i16>,
    pub task_due_date: Option<NaiveDateTime>,
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
    pub habit_description: String,
    pub habit_min_daily_frequency: Option<f64>,
    pub habit_difficulty_tier: Option<HabitDifficultyTier>,
    pub habit_duration_seconds: Option<i32>,
    pub habit_lockout_duration_seconds: Option<i32>,
    pub habit_skip_consequence: Option<i16>,
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
    pub reward_description: String,
    pub reward_max_daily_frequency: Option<f64>,
    pub reward_damage_tier: Option<RewardDamageTier>,
}

#[derive(sqlx::FromRow)]
pub struct TagRow {
    pub id: Uuid,
    pub name: String,
    pub color_hex: String,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
}

#[derive(sqlx::FromRow)]
pub struct HabitTagRow {
    pub habit_id: Uuid,
    pub tag_id: Uuid,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
}
