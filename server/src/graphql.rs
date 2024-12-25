use crate::database::{self, UserRow};
use async_graphql::{
    EmptySubscription, InputObject, Object, Schema, SimpleObject,
};
use chrono::NaiveDateTime;

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

#[Object]
impl MutationRoot {
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
}
