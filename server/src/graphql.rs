use crate::{
    database::{self, CreateTaskOptions, TaskRow, UserRow},
    router::AuthenticatedUser,
    security,
};
use async_graphql::{
    EmptySubscription, InputObject, Object, Schema, SimpleObject, Union,
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
struct HabitObject {
    id: u32,
    name: String,
    created_at: NaiveDateTime,
    deleted_at: NaiveDateTime,
    hidden_until: NaiveDateTime,
    description: String,
    difficulty: u8,
    importance: u8,
    duration: u8,
    min_frequency: u8,
}

#[derive(SimpleObject)]
struct TaskObject {
    id: i32,
    name: String, // Max 100 utf-8 chars
    created_at: NaiveDateTime,
    deleted_at: Option<NaiveDateTime>,
    hidden_until: Option<NaiveDateTime>,
    due_by: Option<NaiveDateTime>,
    description: String,
    difficulty: i32,
    importance: i32,
    duration: i32,
}

#[derive(SimpleObject)]
struct ProjectObject {
    id: i32,
    name: String, // Max 100 utf-8 chars
    created_at: NaiveDateTime,
    deleted_at: Option<NaiveDateTime>,
    hidden_until: Option<NaiveDateTime>,
    due_by: Option<NaiveDateTime>,
    description: String,
    importance: i32,
}

#[derive(SimpleObject)]
struct RewardObject {
    id: i32,
    name: String, // Max 100 utf-8 chars
    created_at: NaiveDateTime,
    deleted_at: Option<NaiveDateTime>,
    hidden_until: Option<NaiveDateTime>,
    description: String,
    damage: i32,
    pleasure: i32,
    max_frequency: i32,
}

#[derive(SimpleObject)]
struct MegaRewardObject {
    id: i32,
    name: String, // Max 100 utf-8 chars
    created_at: NaiveDateTime,
    deleted_at: Option<NaiveDateTime>,
    hidden_until: Option<NaiveDateTime>,
    description: String,
    damage: i32,
    pleasure: i32,
}

#[derive(Union)]
enum ItemUnion {
    MegaReward(MegaRewardObject),
    Reward(RewardObject),
    Task(TaskObject),
    Habit(HabitObject),
    Project(ProjectObject),
}

#[derive(SimpleObject)]
struct TradeObject {
    id: i32,
    refunded: bool,
    amount: i32,
    created_at: NaiveDateTime,
    refunded_at: Option<NaiveDateTime>,
    item: ItemUnion,
    damage: i32,
    pleasure: i32,
}

impl From<TaskRow> for TaskObject {
    fn from(task_row: TaskRow) -> Self {
        Self {
            id: task_row.id,
            name: task_row.name,
            difficulty: task_row.difficulty,
            created_at: task_row.created_at,
            description: task_row.description,
            deleted_at: task_row.deleted_at,
            hidden_until: task_row.hidden_until,
            due_by: task_row.due_by,
            importance: task_row.importance,
            duration: task_row.duration,
        }
    }
}

#[derive(InputObject)]
struct CreateTaskInput {
    name: String, // Max 100 utf-8 chars
    difficulty: i32,
    hidden_until: Option<NaiveDateTime>,
    due_at: Option<NaiveDateTime>,
    description: String,
    importance: i32,
    duration: i32,
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

#[derive(InputObject)]
struct CreateApiKeyInput {
    name: String,
    password: String,
}

#[derive(SimpleObject)]
struct ApiKey {
    name: String,
    key: String,
    created_at: NaiveDateTime,
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
            return Err("Difficulty can only be between 0 and 10.");
        }
        if input.importance > 10 || input.importance < 0 {
            return Err("Importance can only be between 0 and 10.");
        }
        if input.duration < 0 {
            return Err("Duration can't be negative.");
        }
        if input.duration > 60 * 60 * 24 {
            return Err("Duration can't be more than 24hrs.");
        }
        if input.description.chars().count() > 3000 {
            return Err("Description can't be more than 3000 characters.");
        }

        let database = ctx
            .data::<database::Database>()
            .expect("No db pool in context");
        let user_id = ctx
            .data::<AuthenticatedUser>()
            .expect("No user in context.")
            .user_id;

        let opts = CreateTaskOptions {
            user_id,
            name: input.name,
            difficulty: input.difficulty,
            description: input.description,
            hidden_until: input.hidden_until,
            due_at: input.due_at,
            importance: input.importance,
            duration: input.duration,
        };
        let task_row = database
            .create_task(opts)
            .await
            .expect("No task made sorry");

        Ok(task_row.into())
    }
    async fn create_habit(
        &self,
        _ctx: &async_graphql::Context<'_>,
        _input: CreateHabitInput,
    ) -> Result<HabitObject, &'static str> {
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
    async fn create_api_key(
        &self,
        ctx: &async_graphql::Context<'_>,
        input: CreateApiKeyInput,
    ) -> Result<ApiKey, &'static str> {
        let user_id = ctx
            .data::<AuthenticatedUser>()
            .expect("No user in context")
            .user_id;
        let database = ctx
            .data::<database::Database>()
            .expect("No db pool in context");

        // Get password from user
        let user = database
            .get_user_from_user_id(user_id)
            .await
            .map_err(|_| "User does not exist")?;

        // Validate password
        if !security::check_password(
            user.password.as_str(),
            input.password.as_str(),
        ) {
            return Err("Incorrect password");
        };

        let (_, refresh_token, hashed_uuid_part) =
            security::jwt::create_jwt(user_id, input.name.as_str());

        let token_row = database
            .create_or_overwrite_refresh_token(
                hashed_uuid_part.as_str(),
                user_id,
                input.name.as_str(),
                true,
            )
            .await
            .map_err(|_| "Could not create token")?;

        // database.create_or_overwrite_refresh_token(refresh_token, user_id, name, is_api_key)

        //
        // Insert then return
        Ok(ApiKey {
            name: input.name,
            key: refresh_token,
            created_at: token_row.created_at,
        })
    }
}
