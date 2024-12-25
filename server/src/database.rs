use chrono::NaiveDateTime;
use sqlx::{postgres::PgPoolOptions, Pool, Postgres};

#[derive(Clone)]
pub struct Database {
    pool: Pool<Postgres>,
}
pub enum Error {
    UserDoesNotExist,
    FailedToCreateUser,
    FailedToFetchUser,
    FailedToDeleteRefreshToken,
    FailedToCreateRefreshToken,
    FailedToCreateApiKey,
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
    ) -> Result<i32, Error> {
        let (user_id,): (i32,) = sqlx::query_as(
            "INSERT INTO users (email, password) VALUES ($1, $2) RETURNING id",
        )
        .bind(email)
        .bind(hashed_password)
        .fetch_one(&self.pool)
        .await
        .map_err(|_| Error::FailedToCreateUser)?;

        Ok(user_id)
    }

    /// Creates refresh token in the db.
    pub async fn create_refresh_token(
        &self,
        refresh_token: &str,
        user_id: i32,
    ) -> Result<(), Error> {
        sqlx::query("INSERT INTO refresh_tokens (id, user_id) VALUES ($1, $2)")
            .bind(refresh_token)
            .bind(user_id)
            .execute(&self.pool)
            .await
            .map_err(|_| Error::FailedToCreateRefreshToken)?;

        Ok(())
    }

    pub async fn delete_refresh_token(
        &self,
        refresh_token: &str,
    ) -> Result<(), Error> {
        sqlx::query("DELETE FROM refresh_tokens WHERE id = $1")
            .bind(refresh_token)
            .execute(&self.pool)
            .await
            .map_err(|_| Error::FailedToDeleteRefreshToken)?;

        Ok(())
    }

    /// Returns the user from email.
    pub async fn get_user_from_email(
        &self,
        email: &str,
    ) -> Result<UserRow, Error> {
        sqlx::query_as("SELECT * FROM users WHERE email = $1")
            .bind(email)
            .fetch_optional(&self.pool)
            .await
            .map_err(|_| Error::FailedToFetchUser)?
            .ok_or(Error::FailedToFetchUser)
    }

    // Returns the user from api_key.
    pub async fn get_user_from_api_key(
        &self,
        api_key: &str,
    ) -> Result<UserRow, Error> {
        sqlx::query_as("SELECT users.* FROM api_keys INNER JOIN users ON api_keys.user_id = users.id WHERE api_keys.id = $1")
        .bind(api_key)
            .fetch_optional(&self.pool)
            .await
            .map_err(|_| Error::FailedToFetchUser)?
            .ok_or(Error::FailedToFetchUser)
    }

    // Returns the user from active refresh token.
    pub async fn get_user_from_active_refresh_token(
        &self,
        refresh_token: &str,
    ) -> Result<UserRow, Error> {
        sqlx::query_as("SELECT users.* FROM refresh_tokens INNER JOIN users ON refresh_tokens.user_id = users.id WHERE refresh_tokens.id = $1 AND refresh_tokens.expires_at > NOW()")
        .bind(refresh_token)
            .fetch_optional(&self.pool)
            .await
            .map_err(|_| Error::FailedToFetchUser)?
            .ok_or(Error::FailedToFetchUser)
    }

    /// Creates api key in the db.
    pub async fn create_api_key(
        &self,
        api_key: &str,
        user_id: i32,
    ) -> Result<(), Error> {
        sqlx::query("INSERT INTO api_keys (id, user_id) VALUES ($1, $2)")
            .bind(api_key)
            .bind(user_id)
            .execute(&self.pool)
            .await
            // .map_err(|_| Error::FailedToCreateApiKey)?;
            .map_err(|db_err| {
                dbg!(db_err);
                Error::FailedToCreateApiKey
            })?;

        Ok(())
    }
}

#[derive(sqlx::FromRow)]
pub struct UserRow {
    pub id: i32,
    pub email: String,
    pub password: String,
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
