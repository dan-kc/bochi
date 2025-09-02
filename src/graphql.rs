use crate::{
    database::{
        self, CreateHabitOptions, CreateProjectOptions, CreateRewardOptions,
        CreateTagOptions, CreateTaskOptions, CreateTreatOptions, HabitRow,
        MegaRewardRow, ProjectRow, RewardRow, TagRow, TaskRow, UserRow,
    },
    router::AuthenticatedUser,
    security::{self, jwt::JWTManager},
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
    created_at: NaiveDateTime,
    deleted_at: Option<NaiveDateTime>,
    hidden_until: Option<NaiveDateTime>,
    due_by: Option<NaiveDateTime>,
    description: String,
    difficulty: i32,
    importance: i32,
    duration: i32,
}
impl From<TaskRow> for TaskObject {
    fn from(task_row: TaskRow) -> Self {
        Self {
            id: task_row.id,
            name: task_row.name,
            created_at: task_row.created_at,
            deleted_at: task_row.deleted_at,
            hidden_until: task_row.hidden_until,
            due_by: task_row.due_by,
            description: task_row.description,
            difficulty: task_row.difficulty,
            importance: task_row.importance,
            duration: task_row.duration,
        }
    }
}

#[derive(SimpleObject)]
struct HabitObject {
    id: i32,
    name: String,
    created_at: NaiveDateTime,
    deleted_at: Option<NaiveDateTime>,
    hidden_until: Option<NaiveDateTime>,
    description: String,
    difficulty: i32,
    importance: i32,
    duration: i32,
    min_frequency: i32,
}
impl From<HabitRow> for HabitObject {
    fn from(habit_row: HabitRow) -> Self {
        Self {
            id: habit_row.id,
            name: habit_row.name,
            difficulty: habit_row.difficulty,
            created_at: habit_row.created_at,
            description: habit_row.description,
            deleted_at: habit_row.deleted_at,
            hidden_until: habit_row.hidden_until,
            importance: habit_row.importance,
            duration: habit_row.duration,
            min_frequency: habit_row.min_frequency,
        }
    }
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
impl From<ProjectRow> for ProjectObject {
    fn from(project_row: ProjectRow) -> Self {
        Self {
            id: project_row.id,
            name: project_row.name,
            created_at: project_row.created_at,
            deleted_at: project_row.deleted_at,
            hidden_until: project_row.hidden_until,
            due_by: project_row.due_by,
            description: project_row.description,
            importance: project_row.importance,
        }
    }
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
impl From<RewardRow> for RewardObject {
    fn from(reward_row: RewardRow) -> Self {
        Self {
            id: reward_row.id,
            name: reward_row.name,
            created_at: reward_row.created_at,
            deleted_at: reward_row.deleted_at,
            hidden_until: reward_row.hidden_until,
            description: reward_row.description,
            damage: reward_row.damage,
            pleasure: reward_row.pleasure,
            max_frequency: reward_row.max_frequency,
        }
    }
}

#[derive(SimpleObject)]
struct TreatObject {
    id: i32,
    name: String, // Max 100 utf-8 chars
    created_at: NaiveDateTime,
    deleted_at: Option<NaiveDateTime>,
    hidden_until: Option<NaiveDateTime>,
    description: String,
    damage: i32,
    pleasure: i32,
}
impl From<MegaRewardRow> for TreatObject {
    fn from(mega_reward_row: MegaRewardRow) -> Self {
        Self {
            id: mega_reward_row.id,
            name: mega_reward_row.name,
            created_at: mega_reward_row.created_at,
            deleted_at: mega_reward_row.deleted_at,
            hidden_until: mega_reward_row.hidden_until,
            description: mega_reward_row.description,
            damage: mega_reward_row.damage,
            pleasure: mega_reward_row.pleasure,
        }
    }
}

#[derive(Union)]
enum ItemUnion {
    MegaReward(TreatObject),
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

#[derive(SimpleObject)]
struct TagObject {
    id: i32,
    name: String,
    created_at: NaiveDateTime,
    deleted_at: Option<NaiveDateTime>,
    color_hex: String,
}
impl From<TagRow> for TagObject {
    fn from(tag_row: TagRow) -> Self {
        Self {
            id: tag_row.id,
            name: tag_row.name,
            created_at: tag_row.created_at,
            deleted_at: tag_row.deleted_at,
            color_hex: tag_row.color_hex,
        }
    }
}

#[derive(InputObject)]
pub struct CreateTaskInput {
    #[graphql(validator(max_length = 100))]
    pub name: String, // Max 100 utf-8 chars
    // TODO: Validate
    pub hidden_until: Option<NaiveDateTime>,
    // TODO: Validate
    pub due_by: Option<NaiveDateTime>,
    #[graphql(validator(max_length = 3000))]
    pub description: String,
    #[graphql(validator(minimum = 0, maximum = 10))]
    pub difficulty: i32,
    #[graphql(validator(minimum = 0, maximum = 10))]
    pub importance: i32,
    #[graphql(validator(minimum = 0, maximum = 86400))]
    pub duration: i32,
}

#[derive(InputObject)]
pub struct CreateHabitInput {
    #[graphql(validator(max_length = 100))]
    pub name: String,
    // TODO: Validate
    pub hidden_until: Option<NaiveDateTime>,
    #[graphql(validator(max_length = 3000))]
    pub description: String,
    #[graphql(validator(minimum = 0, maximum = 10))]
    pub difficulty: i32,
    #[graphql(validator(minimum = 0, maximum = 10))]
    pub importance: i32,
    #[graphql(validator(minimum = 0, maximum = 86400))]
    pub duration: i32,
    #[graphql(validator(minimum = 1, maximum = 365000))]
    pub min_frequency: i32,
}

#[derive(InputObject)]
pub struct CreateProjectInput {
    #[graphql(validator(max_length = 100))]
    pub name: String,
    // TODO: Validate
    pub hidden_until: Option<NaiveDateTime>,
    // TODO: Validate
    pub due_by: Option<NaiveDateTime>,
    #[graphql(validator(max_length = 3000))]
    pub description: Option<String>,
    #[graphql(validator(minimum = 0, maximum = 10))]
    pub importance: i32,
}

#[derive(InputObject)]
pub struct CreateRewardInput {
    #[graphql(validator(max_length = 100))]
    pub name: String,
    // TODO: Validate
    pub hidden_until: Option<NaiveDateTime>,
    #[graphql(validator(max_length = 3000))]
    pub description: String,
    #[graphql(validator(minimum = 0, maximum = 10))]
    pub damage: i32,
    #[graphql(validator(minimum = 0, maximum = 10))]
    pub pleasure: i32,
    #[graphql(validator(minimum = 1, maximum = 365000))]
    pub max_frequency: i32,
}

#[derive(InputObject)]
pub struct CreateTreatInput {
    #[graphql(validator(max_length = 100))]
    pub name: String,
    // TODO: Validate
    pub hidden_until: Option<NaiveDateTime>,
    #[graphql(validator(max_length = 3000))]
    pub description: String,
    #[graphql(validator(minimum = 0, maximum = 10))]
    pub damage: i32,
    #[graphql(validator(minimum = 0, maximum = 10))]
    pub pleasure: i32,
}

#[derive(InputObject)]
pub struct CreateTagInput {
    #[graphql(validator(max_length = 100))]
    pub name: String,
    // TODO: Validate
    pub color_hex: String,
}

#[derive(InputObject)]
pub struct TradeInput {
    pub id: String,
    pub amount: i32,
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
        let database = ctx
            .data::<database::Database>()
            .expect("No db pool in context");
        let user_id = ctx
            .data::<AuthenticatedUser>()
            .expect("No user in context.")
            .user_id;

        let opts = CreateTaskOptions::new(input, user_id);
        let task_row = database
            .create_task(opts)
            .await
            .expect("No task made sorry");

        Ok(task_row.into())
    }

    async fn create_habit(
        &self,
        ctx: &async_graphql::Context<'_>,
        input: CreateHabitInput,
    ) -> Result<HabitObject, &'static str> {
        let database = ctx
            .data::<database::Database>()
            .expect("No db pool in context");
        let user_id = ctx
            .data::<AuthenticatedUser>()
            .expect("No user in context.")
            .user_id;

        let opts = CreateHabitOptions::new(input, user_id);
        let habit_row = database
            .create_habit(opts)
            .await
            .expect("No habit made sorry");

        Ok(habit_row.into())
    }

    async fn create_project(
        &self,
        ctx: &async_graphql::Context<'_>,
        input: CreateProjectInput,
    ) -> Result<ProjectObject, &'static str> {
        let database = ctx
            .data::<database::Database>()
            .expect("No db pool in context");
        let user_id = ctx
            .data::<AuthenticatedUser>()
            .expect("No user in context.")
            .user_id;

        let opts = CreateProjectOptions::new(input, user_id);
        let project_row = database
            .create_project(opts)
            .await
            .expect("No project made sorry");

        Ok(project_row.into())
    }

    async fn create_reward(
        &self,
        ctx: &async_graphql::Context<'_>,
        input: CreateRewardInput,
    ) -> Result<RewardObject, &'static str> {
        let database = ctx
            .data::<database::Database>()
            .expect("No db pool in context");
        let user_id = ctx
            .data::<AuthenticatedUser>()
            .expect("No user in context.")
            .user_id;

        let opts = CreateRewardOptions::new(input, user_id);
        let reward_row = database
            .create_reward(opts)
            .await
            .expect("No reward made sorry");

        Ok(reward_row.into())
    }
    async fn create_treat(
        &self,
        ctx: &async_graphql::Context<'_>,
        input: CreateTreatInput,
    ) -> Result<TreatObject, &'static str> {
        let database = ctx
            .data::<database::Database>()
            .expect("No db pool in context");
        let user_id = ctx
            .data::<AuthenticatedUser>()
            .expect("No user in context.")
            .user_id;

        let opts = CreateTreatOptions::new(input, user_id);
        let treat_row = database
            .create_treat_reward(opts)
            .await
            .expect("No treat made sorry");

        Ok(treat_row.into())
    }
    async fn create_tag(
        &self,
        ctx: &async_graphql::Context<'_>,
        input: CreateTagInput,
    ) -> Result<TagObject, &'static str> {
        let database = ctx
            .data::<database::Database>()
            .expect("No db pool in context");
        let user_id = ctx
            .data::<AuthenticatedUser>()
            .expect("No user in context.")
            .user_id;

        let opts = CreateTagOptions::new(input, user_id);
        let tag_row =
            database.create_tag(opts).await.expect("No tag made sorry");

        Ok(tag_row.into())
    }

    async fn trade(
        &self,
        _ctx: &async_graphql::Context<'_>,
        _input: TradeInput,
    ) -> Result<TradeObject, &'static str> {
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
        let jwt_manager = ctx.data::<JWTManager>().expect("No JWT manager");
        let user = database
            .get_user_from_user_id(user_id)
            .await
            .map_err(|_| "User does not exist")?;

        if !security::check_password(
            user.password.as_str(),
            input.password.as_str(),
        ) {
            return Err("Incorrect password");
        };

        let (_, refresh_token, hashed_uuid_part) =
            jwt_manager.create(user_id, input.name.as_str());

        let token_row = database
            .create_or_overwrite_refresh_token(
                hashed_uuid_part.as_str(),
                user_id,
                input.name.as_str(),
                true,
            )
            .await
            .map_err(|_| "Could not create token")?;

        Ok(ApiKey {
            name: input.name,
            key: refresh_token,
            created_at: token_row.created_at,
        })
    }
}
