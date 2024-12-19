use crate::{
    database::{self, UserRow},
    security,
};
use async_graphql::{
    EmptySubscription, InputObject, Object, Schema, SimpleObject,
};
use chrono::NaiveDateTime;
use regex::Regex;

pub struct MutationRoot;
pub struct QueryRoot;
pub type ServiceSchema = Schema<QueryRoot, MutationRoot, EmptySubscription>;

#[Object]
impl QueryRoot {
    async fn hello(&self, _ctx: &async_graphql::Context<'_>) -> &'static str {
        "Wag1"
    }
}

#[derive(SimpleObject)]
struct User {
    id: i32,
    email: String,
}

// We need a dedicated UserRow type as it needs to include password which is not present in the
// object we return
impl From<UserRow> for User {
    fn from(value: UserRow) -> Self {
        Self {
            id: value.id,
            email: value.email,
        }
    }
}

#[derive(SimpleObject)]
struct AuthResponse {
    refresh_token: String,
    access_token: String,
}

#[derive(SimpleObject)]
struct LogoutResponse {
    success: bool,
}

#[derive(sqlx::FromRow)]
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

#[derive(SimpleObject)]
struct TaskObject {
    id: i32,
    name: String, // Max 100 utf-8 chars
    difficulty: i32,
    created_at: NaiveDateTime,
    deleted_at: Option<NaiveDateTime>,
    hidden_until: Option<NaiveDateTime>,
    due_at: Option<NaiveDateTime>,
    description: Option<String>,
    importance: i32,
    duration: i32,
}

#[derive(InputObject)]
struct CreateTaskInput {
    name: String, // Max 100 utf-8 chars
    difficulty: i32,
    hidden_until: Option<NaiveDateTime>,
    due_at: Option<NaiveDateTime>,
    description: Option<String>,
    importance: i32,
    duration: i32,
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
    async fn refresh_tokens(
        &self,
        ctx: &async_graphql::Context<'_>,
        refresh_token: String,
    ) -> Result<AuthResponse, &'static str> {
        let database = &ctx
            .data::<database::Database>()
            .expect("No db pool in context");
        if let Some(user) = database
            .get_user_from_active_refresh_token(refresh_token.as_str())
            .await
        {
            let (new_access_token, new_refresh_token) =
                security::jwt::create_jwt_pair(user.id);
            database
                .create_refresh_token(new_refresh_token.as_str(), user.id)
                .await;

            return Ok(AuthResponse {
                access_token: new_access_token,
                refresh_token: new_refresh_token,
            });
        };

        Err("Invalid refresh token")
    }
    async fn create_task(
        &self,
        ctx: &async_graphql::Context<'_>,
        input: CreateTaskInput,
    ) -> Result<TaskObject, &'static str> {
        if input.name.as_str().len() > 10 {
            return Err("Name is too long. Must be fewer than 100 chars.");
        };
        if input.difficulty > 10 || input.difficulty < 0 {
            return Err("Difficulty can only be between 0 and 10");
        }
        if input.importance > 10 || input.importance < 0 {
            return Err("Importance can only be between 0 and 10");
        }
        if input.duration < 0 {
            return Err("Duration can't be negative");
        }
        // if input.

        let _database = &ctx
            .data::<database::Database>()
            .expect("No db pool in context");
        //
        // let user_id = "";
        // let _row: TaskRow = sqlx::query_as(
        //     "INSERT INTO tasks (user_id, name, difficulty, hidden_until, due_at, importance, duration) VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING id",
        // )
        // .bind(user_id)
        // .bind(input.name)
        // .bind(input.difficulty)
        // .bind(input.hidden_until)
        // .bind(input.due_at)
        // .bind(input.importance)
        // .bind(input.duration)
        // .fetch_one(&db_pool.clone())
        // .await
        // .expect("Failed to insert user");

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

        let database = &ctx.data::<database::Database>().expect("No database");

        if let Some(user) =
            database.get_user_from_email(input.email.as_str()).await
        {
            if !security::check_password(
                user.password.as_str(),
                input.password.as_str(),
            ) {
                return err;
            }

            let (access_token, refresh_token) =
                security::jwt::create_jwt_pair(user.id);

            database
                .create_refresh_token(refresh_token.as_str(), user.id)
                .await;

            Ok(AuthResponse {
                refresh_token,
                access_token,
            })
        } else {
            err
        }
    }

    async fn logout(
        &self,
        ctx: &async_graphql::Context<'_>,
        refresh_token: String,
    ) -> Result<LogoutResponse, &'static str> {
        let database = &ctx.data::<database::Database>().expect("No database");
        database.delete_refresh_token(refresh_token.as_str()).await;

        Ok(LogoutResponse { success: true })
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

        let database = &ctx.data::<database::Database>().expect("No database");

        let user_already_exists =
            database.check_user_exists(input.email.as_str()).await;
        if user_already_exists {
            return Err("User already exists.");
        }

        let hashed_password = security::hash_password(input.password.as_str());

        let user_id = database
            .create_user(input.email.as_str(), hashed_password.as_str())
            .await;

        let (access_token, refresh_token) =
            security::jwt::create_jwt_pair(user_id);

        database
            .create_refresh_token(refresh_token.as_str(), user_id)
            .await;

        Ok(AuthResponse {
            refresh_token,
            access_token,
        })
    }
}
