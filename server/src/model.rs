#[allow(unused)]
use argon2::{password_hash::SaltString, Argon2, PasswordHasher};
use argon2::{PasswordHash, PasswordVerifier};
use async_graphql::{
    EmptySubscription, InputObject, Object, Schema, SimpleObject,
};
use chrono::NaiveDateTime;
use regex::Regex;
use sqlx::{Pool, Postgres};
use uuid::Uuid;

pub type ServiceSchema = Schema<QueryRoot, MutationRoot, EmptySubscription>;

pub struct QueryRoot;

#[Object]
impl QueryRoot {
    async fn hello(&self, _ctx: &async_graphql::Context<'_>) -> &'static str {
        "Wag1"
    }
    // async fn user(
    //     &self,
    //     _ctx: &async_graphql::Context<'_>,
    // ) -> Result<User, &'static str> {
    //     todo!();
    // }
}

pub struct MutationRoot;

#[derive(sqlx::FromRow)]
struct UserRow {
    id: i32,
    email: String,
    password: String,
}

impl From<UserRow> for User {
    fn from(value: UserRow) -> Self {
        Self {
            id: value.id,
            email: value.email,
        }
    }
}

#[derive(SimpleObject)]
struct User {
    id: i32,
    email: String,
}

#[derive(SimpleObject)]
struct AuthResponse {
    user: User,
    session_id: String,
}

#[derive(SimpleObject)]
struct LogoutResponse {
    success: bool,
}

#[derive(SimpleObject)]
struct Task {
    id: u32,
    name: String,
    difficulty: u8,
    importance: u8,
    duration: u8,
    created_at: NaiveDateTime,
    deleted_at: NaiveDateTime,
    hidden_until: NaiveDateTime,
    due_at: NaiveDateTime,
}

#[derive(SimpleObject)]
struct Habit {
    id: u32,
    name: String,
    difficulty: u8,
    importance: u8,
    duration: u8,
    daily_frequency: u8,
    created_at: NaiveDateTime,
    deleted_at: NaiveDateTime,
    hidden_until: NaiveDateTime,
}

#[derive(SimpleObject)]
struct Tag {
    id: u32,
    name: String,
    color_hex: String,
}

#[derive(SimpleObject)]
struct Trade {
    id: u32,
    color_hex: String,
    amount: u8,
    created_at: NaiveDateTime,
    task_id: u32,
    habit_id: u32,
}

#[derive(InputObject)]
struct CreateUserInput {
    email: String,
    password: String,
    confirm_password: String,
}

#[derive(InputObject)]
struct LoginInput {
    email: String,
    password: String,
}

#[derive(SimpleObject)]
struct CreateApiKeyResponse {
    api_key: String,
}

#[derive(InputObject)]
struct CreateTaskInput {
    name: String,
    difficulty: i32,
    importance: i32,
    duration: i32,
    hidden_until: Option<NaiveDateTime>,
    due_at: Option<NaiveDateTime>,
}

#[derive(InputObject)]
struct CreateHabitInput {
    name: String,
    difficulty: i32,
    importance: i32,
    duration: i32,
    hidden_until: Option<NaiveDateTime>,
    due_at: Option<NaiveDateTime>,
}

#[derive(InputObject)]
struct CreateTagInput {
    name: String,
    color_hex: String,
}

#[derive(InputObject)]
struct TradeInput {
    id: String,
    amount: i32,
}

#[derive(InputObject)]
struct CreateApiKeyInput {
    id: String,
    amount: i32,
}

#[Object]
impl MutationRoot {
    async fn create_api_key(
        &self,
        _ctx: &async_graphql::Context<'_>,
        _input: CreateApiKeyInput,
    ) -> Result<CreateApiKeyResponse, &'static str> {
        todo!()
    }
    async fn create_task(
        &self,
        _ctx: &async_graphql::Context<'_>,
        _input: CreateTaskInput,
    ) -> Result<Task, &'static str> {
        todo!()
    }
    async fn create_habit(
        &self,
        _ctx: &async_graphql::Context<'_>,
        _input: CreateHabitInput,
    ) -> Result<Habit, &'static str> {
        todo!()
    }
    async fn create_tag(
        &self,
        _ctx: &async_graphql::Context<'_>,
        _input: CreateTagInput,
    ) -> Result<Tag, &'static str> {
        todo!()
    }
    async fn trade(
        &self,
        _ctx: &async_graphql::Context<'_>,
        _input: TradeInput,
    ) -> Result<Trade, &'static str> {
        todo!()
    }
    async fn login(
        &self,
        ctx: &async_graphql::Context<'_>,
        input: LoginInput,
    ) -> Result<AuthResponse, &'static str> {
        let err = Err("Incorrect email or password.");
        let valid_email =
            Regex::new(r"^[\w\.-]+@[a-zA-Z\d\.-]+\.[a-zA-Z]{2,}$")
                .unwrap()
                .is_match(input.email.as_str());
        let email_too_long = input.email.len() > 40;
        let password_ascii = input.password.is_ascii();
        let password_in_bounds =
            input.password.len() < 64 && input.password.len() > 8;
        if !valid_email
            || email_too_long
            || !password_ascii
            || !password_in_bounds
        {
            return err;
        }

        let db_pool =
            ctx.data::<Pool<Postgres>>().expect("No db pool in context");

        let user_row: Option<UserRow> =
            sqlx::query_as("SELECT * FROM users WHERE email = $1")
                .bind(input.email.as_str())
                .fetch_optional(&db_pool.clone())
                .await
                .expect("Failed to find user");

        if let Some(row) = user_row {
            let parsed_hash = PasswordHash::new(&row.password).unwrap();
            if Argon2::default()
                .verify_password(input.password.as_bytes(), &parsed_hash)
                .is_err()
            {
                return err;
            };

            // Add session
            let session_id = Uuid::new_v4().to_string().replace('-', "_");
            sqlx::query("INSERT INTO sessions (id, user_id) VALUES ($1, $2)")
                .bind(session_id.as_str())
                .bind(row.id)
                .execute(&db_pool.clone())
                .await
                .expect("Failed to create session id");

            return Ok(AuthResponse {
                user: row.into(),
                session_id,
            });
        } else {
            return err;
        }
    }

    async fn logout(
        &self,
        ctx: &async_graphql::Context<'_>,
        id: String,
    ) -> Result<LogoutResponse, &'static str> {
        let db_pool =
            ctx.data::<Pool<Postgres>>().expect("No db pool in context");

        let res = sqlx::query("DELETE FROM sessions WHERE id = $1")
            .bind(id)
            .execute(&db_pool.clone())
            .await
            .unwrap();

        let success = res.rows_affected() > 0;
        if !success {
            return Err("Session does not exist. Already logged out.");
        }

        Ok(LogoutResponse { success })
    }

    async fn create_user(
        &self,
        ctx: &async_graphql::Context<'_>,
        input: CreateUserInput,
    ) -> Result<AuthResponse, &'static str> {
        let is_valid_email =
            Regex::new(r"^[\w\.-]+@[a-zA-Z\d\.-]+\.[a-zA-Z]{2,}$")
                .unwrap()
                .is_match(input.email.as_str());
        if !is_valid_email {
            return Err("Invalid email address.");
        }
        if input.email.len() > 40 {
            return Err("Email too long. The max email length is 40.");
        }

        if !input.password.is_ascii() {
            return Err("Password must contain only standard English letters, numbers, and common punctuation.");
        }
        if input.password.len() > 64 {
            return Err("Password too long. The max password length is 64.");
        }
        if input.password.len() < 8 {
            return Err("Password too short. The min password length is 8.");
        }
        if input.password != input.confirm_password {
            return Err("Passwords do not match.");
        }

        let db_pool =
            ctx.data::<Pool<Postgres>>().expect("No db pool in context");

        // Check if the user already exists.
        let (email_taken,): (bool,) = sqlx::query_as(
            "SELECT EXISTS(SELECT 1 FROM users WHERE email = $1)",
        )
        .bind(input.email.as_str())
        .fetch_one(&db_pool.clone())
        .await
        .expect("failed to check if user already exists");
        if email_taken {
            return Err("User already exists.");
        }

        let salt = SaltString::generate(rand::thread_rng());
        let hashed_password = Argon2::default()
            .hash_password(input.password.as_bytes(), &salt)
            .unwrap()
            .to_string();

        let (user_id,): (i32,) = sqlx::query_as(
        "INSERT INTO users (email, password) VALUES ($1, $2) RETURNING id",
        )
        .bind(input.email.as_str())
        .bind(hashed_password)
        .fetch_one(&db_pool.clone())
        .await
        .expect("Failed to insert user");

        // log user in
        let session_id = Uuid::new_v4().to_string().replace('-', "_");
        sqlx::query("INSERT INTO sessions (id, user_id) VALUES ($1, $2)")
            .bind(session_id.clone())
            .bind(user_id)
            .execute(&db_pool.clone())
            .await
            .expect("Failed to create session id");

        let user = User {
            id: user_id,
            email: input.email,
        };

        Ok(AuthResponse { user, session_id })
    }
}
