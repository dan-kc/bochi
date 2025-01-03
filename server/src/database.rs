use chrono::NaiveDateTime;
use sqlx::{postgres::PgPoolOptions, Pool, Postgres};

#[derive(Clone)]
pub struct Database {
    pool: Pool<Postgres>,
}

impl Database {
    pub async fn new() -> Self {
        let database_url = std::env::var("DATABASE_URL").expect("Need db url");
        let pool = PgPoolOptions::new()
            .max_connections(97) // 97 is the default limit for postgres. Change this if we ever have
            // another server connecting. All pools must add up to 97.
            .connect(&database_url)
            .await
            .expect("Unable to create database pool");

        Database { pool }
    }

    /// Creates a user, returning the user id.
    pub async fn create_user(
        &self,
        email: &str,
        hashed_password: &str,
    ) -> Result<i32, sqlx::Error> {
        let (user_id,): (i32,) = sqlx::query_as(
            "INSERT INTO users (email, password) VALUES ($1, $2) RETURNING id",
        )
        .bind(email)
        .bind(hashed_password)
        .fetch_one(&self.pool)
        .await?;

        Ok(user_id)
    }

    /// Creates a task, returning the tasks..
    pub async fn create_task(
        &self,
        create_task_options: CreateTaskOptions,
    ) -> Result<TaskRow, sqlx::Error> {
        sqlx::query_as(
            "INSERT INTO tasks 
            (user_id, name, diffiulty, description, hidden_until, due_at, importance, duration) VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING *",
        )
        .bind(create_task_options.user_id)
        .bind(create_task_options.name)
        .bind(create_task_options.difficulty)
        .bind(create_task_options.description)
        .bind(create_task_options.hidden_until)
        .bind(create_task_options.due_at)
        .bind(create_task_options.importance)
        .bind(create_task_options.duration)
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
        sqlx::query(
            "DELETE FROM refresh_tokens WHERE name = $1 AND user_id = $2;",
        )
        .bind(name)
        .bind(user_id)
        .execute(&self.pool)
        .await?;

        let insert_query = match is_api_key{
            true => "INSERT INTO refresh_tokens (key, user_id, name, expires_at) VALUES ($1, $2, $3, NULL) RETURNING *",
            false => "INSERT INTO refresh_tokens (key, user_id, name) VALUES ($1, $2, $3) RETURNING *"
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

    pub async fn delete_refresh_token(
        &self,
        refresh_token: &str,
    ) -> Result<(), sqlx::Error> {
        sqlx::query("DELETE FROM refresh_tokens WHERE id = $1")
            .bind(refresh_token)
            .execute(&self.pool)
            .await?;

        Ok(())
    }

    pub async fn get_refresh_token_from_name_user(
        &self,
        name: &str,
        user_id: i32,
    ) -> Result<RefreshTokenRow, sqlx::Error> {
        sqlx::query_as("
            SELECT * FROM refresh_tokens
            INNER JOIN users ON refresh_tokens.user_id = users.id
            WHERE refresh_tokens.name = $1
            AND refresh_tokens.user_id = $2
            AND (refresh_tokens.expires_at > NOW() OR refresh_tokens.expires_at IS NULL);
        ")
        .bind(name)
        .bind(user_id)
            .fetch_optional(&self.pool)
            .await.unwrap()
            .ok_or(sqlx::Error::RowNotFound)
    }

    /// Returns the user from email.
    pub async fn get_user_from_email(
        &self,
        email: &str,
    ) -> Result<UserRow, sqlx::Error> {
        sqlx::query_as("SELECT * FROM users WHERE email = $1")
            .bind(email)
            .fetch_optional(&self.pool)
            .await?
            .ok_or(sqlx::Error::RowNotFound)
    }

    pub async fn get_user_from_user_id(
        &self,
        user_id: i32,
    ) -> Result<UserRow, sqlx::Error> {
        sqlx::query_as("SELECT * FROM users WHERE id = $1")
            .bind(user_id)
            .fetch_optional(&self.pool)
            .await?
            .ok_or(sqlx::Error::RowNotFound)
    }
}

pub struct CreateTaskOptions {
    pub user_id: i32,
    pub name: String, // Max 100 utf-8 chars
    pub difficulty: i32,
    pub description: String,
    pub hidden_until: Option<NaiveDateTime>,
    pub due_at: Option<NaiveDateTime>,
    pub importance: i32,
    pub duration: i32,
}

#[derive(sqlx::FromRow)]
pub struct UserRow {
    pub id: i32,
    pub email: String,
    pub password: String,
}

#[derive(sqlx::FromRow)]
pub struct RefreshTokenRow {
    pub key: String,
    pub created_at: NaiveDateTime,
    pub expires_at: Option<NaiveDateTime>,
}

#[derive(sqlx::FromRow)]
#[allow(unused)]
pub struct TaskRow {
    pub id: i32,
    pub user_id: i32,
    pub name: String, // Max 100 utf-8 chars
    pub difficulty: i32,
    pub created_at: NaiveDateTime,
    pub description: String,
    pub deleted_at: Option<NaiveDateTime>,
    pub hidden_until: Option<NaiveDateTime>,
    pub due_at: Option<NaiveDateTime>,
    pub importance: i32,
    pub duration: i32,
}
