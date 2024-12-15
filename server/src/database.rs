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

    // Check if the user already exists in database.
    pub async fn check_user_exists(&self, email: &str) -> bool {
        let (email_taken,): (bool,) = sqlx::query_as(
            "SELECT EXISTS(SELECT 1 FROM users WHERE email = $1)",
        )
        .bind(email)
        .fetch_one(&self.pool)
        .await
        .expect("failed to check if user already exists");

        email_taken
    }

    /// Creates a user, returning the user id.
    pub async fn create_user(&self, email: &str, hashed_password: &str) -> i32 {
        let (user_id,): (i32,) = sqlx::query_as(
            "INSERT INTO users (email, password) VALUES ($1, $2) RETURNING id",
        )
        .bind(email)
        .bind(hashed_password)
        .fetch_one(&self.pool)
        .await
        .expect("Failed to insert user");

        user_id
    }

    /// Creates refresh token in the db.
    pub async fn create_refresh_token(
        &self,
        refresh_token: &str,
        user_id: i32,
    ) {
        sqlx::query("INSERT INTO refresh_tokens (id, user_id) VALUES ($1, $2)")
            .bind(refresh_token)
            .bind(user_id)
            .execute(&self.pool)
            .await
            .expect("Failed to create refresh token");
    }

    pub async fn delete_refresh_token(&self, refresh_token: &str) {
        sqlx::query("DELETE FROM refresh_tokens WHERE id = $1")
            .bind(refresh_token)
            .execute(&self.pool)
            .await
            .expect("Could not delete refresh token");
    }

    /// Returns the user from email.
    pub async fn get_user_from_email(&self, email: &str) -> Option<UserRow> {
        sqlx::query_as("SELECT * FROM users WHERE email = $1")
            .bind(email)
            .fetch_optional(&self.pool)
            .await
            .expect("Failed to find user")
    }

    // Returns the user from api_key.
    pub async fn get_user_from_api_key(
        &self,
        api_key: &str,
    ) -> Option<UserRow> {
        sqlx::query_as("SELECT users.* FROM api_keys INNER JOIN users ON api_keys.user_id = users.id WHERE api_keys.id = $1")
        .bind(api_key)
            .fetch_optional(&self.pool)
            .await
        .expect("Failed to find user")
    }
}

#[derive(sqlx::FromRow)]
pub struct UserRow {
    pub id: i32,
    pub email: String,
    pub password: String,
}
