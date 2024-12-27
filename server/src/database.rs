use std::str::FromStr;

use chrono::NaiveDateTime;
use sqlx::{postgres::PgPoolOptions, Acquire, Pool, Postgres, Transaction};

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

    /// Creates refresh token in the db. Api keys have expires_at = NULL
    pub async fn create_or_overwrite_refresh_token(
        &self,
        refresh_token: &str,
        user_id: i32,
        name: &str,
        is_api_key: bool,
    ) -> Result<(), sqlx::Error> {
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
            true => "INSERT INTO refresh_tokens (key, user_id, name, expires_at) VALUES ($1, $2, $3, NULL)",
            false => "INSERT INTO refresh_tokens (key, user_id, name) VALUES ($1, $2, $3)"
        };
        sqlx::query(insert_query)
            .bind(refresh_token)
            .bind(user_id)
            .bind(name)
            .execute(&self.pool)
            .await?;

        Ok(())
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
    pub name: String,
    pub user_id: i32,
    pub expires_at: Option<NaiveDateTime>,
    pub created_at: NaiveDateTime,
}

#[derive(sqlx::FromRow)]
#[allow(unused)]
struct TaskRow {
    id: i32,
    user_id: i32,
    name: String, // Max 100 utf-8 chars
    difficulty: i32,
    created_at: NaiveDateTime,
    description: Option<String>,
    deleted_at: Option<NaiveDateTime>,
    hidden_until: Option<NaiveDateTime>,
    due_at: Option<NaiveDateTime>,
    importance: i32,
    duration: i32,
}
