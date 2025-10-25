use crate::graphql::mutations::{CreateRewardInput, CreateTaskInput};
use chrono::NaiveDateTime;
use sqlx::{postgres::PgPoolOptions, Pool, Postgres};

#[derive(Clone)]
pub struct Database {
    pool: Pool<Postgres>,
}

impl Database {
    pub async fn new() -> Self {
        // Get configuration from environment variables
        let user = std::env::var("DB_USER").expect("DB_USER not set");
        let password = std::env::var("DB_PASSWORD").expect("DB_PASSWORD not set");
        let host = std::env::var("DB_HOST").expect("DB_HOST not set");
        let name = std::env::var("DB_NAME").expect("DB_NAME not set");

        let database_url = format!("postgres://{}:{}@{}/{}", user, password, host, name);
        let pool = PgPoolOptions::new()
            .max_connections(97) // 97 is the default limit for postgres. Change this if we ever have
            // another server connecting. All pools must add up to 97.
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
    ) -> Result<i32, sqlx::Error> {
        let (user_id,): (i32,) =
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
            (user_id, name, hidden_until, due_by, description) VALUES ($1, $2, $3, $4, $5) RETURNING id, name, created_at, deleted_at, hidden_until, due_by, description",
        )
        .bind(create_task_options.user_id)
        .bind(create_task_options.name)
        .bind(create_task_options.hidden_until)
        .bind(create_task_options.due_by)
        .bind(create_task_options.description)
        .fetch_one(&self.pool)
        .await
    }

    pub async fn create_reward(
        &self,
        create_reward_options: CreateRewardOptions,
    ) -> Result<RewardRow, sqlx::Error> {
        sqlx::query_as(
            "INSERT INTO rewards
            (user_id, name, description, hidden_until, max_daily_frequency) VALUES ($1, $2, $3, $4, $5) RETURNING id, name, description, created_at, deleted_at, hidden_until, max_daily_frequency",
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
            // We `SELECT $1, $2` here instead of `SELECT column names`. This is valid SQL.
            // We do this because we can only do a where claude if we SELECT. We don't want
            // to use any of the values from the tasks table for the insert, so we just provide
            // literal values that, after the validation is done, gets used by the insert 
            // statment.
            "WITH new_trade AS (
                INSERT INTO trades (task_id, amount)
                SELECT $1, $2
                FROM tasks
                WHERE tasks.id = $1 AND tasks.user_id = $3
                RETURNING id, task_id, reward_id, amount, created_at
            )
            SELECT
                nt.*,
                t.name AS task_name, t.created_at AS task_created_at, t.deleted_at AS task_deleted_at, t.hidden_until AS task_hidden_until, t.due_by AS task_due_by, t.description AS task_description
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
                INSERT INTO trades (reward_id, amount)
                SELECT $1, $2
                FROM rewards
                WHERE rewards.id = $1 AND rewards.user_id = $3
                RETURNING id, task_id, reward_id, amount, created_at
            )
            SELECT
                nt.*,
                r.name AS reward_name, r.created_at AS reward_created_at, r.deleted_at AS reward_deleted_at, r.hidden_until AS reward_hidden_until, r.description AS reward_description, r.max_daily_frequency as reward_max_daily_frequency
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
        user_id: i32,
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
        user_id: i32,
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
        user_id: i32,
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
        sqlx::query_as("SELECT id, email, password FROM users WHERE email = $1")
            .bind(email)
            .fetch_optional(&self.pool)
            .await?
            .ok_or(sqlx::Error::RowNotFound)
    }
}

pub struct CreateTaskOptions {
    pub user_id: i32,
    pub name: String,
    pub hidden_until: Option<NaiveDateTime>,
    pub due_by: Option<NaiveDateTime>,
    pub description: String,
}
impl CreateTaskOptions {
    pub fn new(input: CreateTaskInput, user_id: i32) -> Self {
        Self {
            user_id,
            name: input.name,
            hidden_until: input.hidden_until,
            due_by: input.due_by,
            description: input.description,
        }
    }
}

pub struct CreateTradeWithTaskOptions {
    user_id: i32,
    task_id: i32,
    amount: i32,
}
impl CreateTradeWithTaskOptions {
    pub fn new(user_id: i32, task_id: i32, amount: i32) -> Self {
        Self {
            user_id: user_id,
            task_id: task_id,
            amount: amount,
        }
    }
}

pub struct CreateTradeWithRewardOptions {
    user_id: i32,
    reward_id: i32,
    amount: i32,
}
impl CreateTradeWithRewardOptions {
    pub fn new(user_id: i32, reward_id: i32, amount: i32) -> Self {
        Self {
            user_id: user_id,
            reward_id: reward_id,
            amount: amount,
        }
    }
}

pub struct CreateRewardOptions {
    pub user_id: i32,
    pub name: String,
    pub description: String,
    pub hidden_until: Option<NaiveDateTime>,
    pub max_daily_frequency: Option<f32>,
}
impl CreateRewardOptions {
    pub fn new(input: CreateRewardInput, user_id: i32) -> Self {
        Self {
            user_id,
            name: input.name,
            hidden_until: input.hidden_until,
            description: input.description,
            max_daily_frequency: input.max_daily_frequency,
        }
    }
}

#[derive(sqlx::FromRow)]
pub struct UserRow {
    pub id: i32,
    #[allow(dead_code)]
    pub email: String,
    pub password: String,
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
    pub id: i32,
    pub name: String,
    pub created_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub hidden_until: Option<NaiveDateTime>,
    pub due_by: Option<NaiveDateTime>,
    pub description: String,
}

#[derive(sqlx::FromRow)]
pub struct RewardRow {
    pub id: i32,
    pub name: String,
    pub description: String,
    pub created_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub hidden_until: Option<NaiveDateTime>,
    pub max_daily_frequency: Option<f32>,
}

#[derive(sqlx::FromRow)]
pub struct TradeWithTaskRow {
    pub id: i32,
    pub created_at: NaiveDateTime,
    pub amount: i32,
    pub task_id: i32,

    // Task join
    pub task_name: String,
    pub task_created_at: NaiveDateTime,
    pub task_deleted_at: Option<NaiveDateTime>,
    pub task_hidden_until: Option<NaiveDateTime>,
    pub task_due_by: Option<NaiveDateTime>,
    pub task_description: String,
}

#[derive(sqlx::FromRow)]
pub struct TradeWithRewardRow {
    pub id: i32,
    pub created_at: NaiveDateTime,
    pub amount: i32,
    pub reward_id: i32,

    // Task join
    pub reward_name: String,
    pub reward_created_at: NaiveDateTime,
    pub reward_deleted_at: Option<NaiveDateTime>,
    pub reward_hidden_until: Option<NaiveDateTime>,
    pub reward_description: String,
    pub reward_max_daily_frequency: Option<f32>,
}
