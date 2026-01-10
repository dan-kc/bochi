use std::{any::Any, sync::Arc};
use tracing::error;

use super::objects::{RewardObject, SyncPushResponse, SyncTaskInput, TaskObject, TradeObject};
use crate::{
    database::{
        self, CreateRewardOptions, CreateTaskOptions, CreateTradeWithRewardOptions,
        CreateTradeWithTaskOptions, UpsertTaskOptions,
    },
    router::AuthenticatedUser,
};
use async_graphql::{ErrorExtensionValues, InputObject, Object};
use chrono::{NaiveDateTime, Utc};
use uuid::Uuid;

pub struct MutationRoot;

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("Validation Error: {0}")]
    Validation(String),
    #[error("An unexpected internal server error occurred.")]
    Internal,
}
// Implement an `into_graphql_error` method directly on AppError
impl Error {
    pub fn into_graphql_error(self) -> async_graphql::Error {
        let mut extensions = ErrorExtensionValues::default();
        let message = self.to_string();

        match &self {
            Error::Validation(_) => {
                extensions.set("code", "BAD_USER_INPUT");
                extensions.set("details", &message);
            }
            Error::Internal => {
                extensions.set("code", "INTERNAL_SERVER_ERROR");
                extensions.set("details", Error::Internal.to_string());
            }
        }

        async_graphql::Error {
            message,
            extensions: Some(extensions),
            source: Some(Arc::new(self) as Arc<dyn Any + Send + Sync>),
        }
    }
}

#[derive(InputObject)]
pub struct CreateTaskInput {
    pub name: String, // Max 100 utf-8 chars
    pub description: String,
    pub hidden_until: Option<NaiveDateTime>,
    pub due_by: Option<NaiveDateTime>,
    pub min_daily_frequency: Option<f64>,
    pub difficulty_rank: Option<String>,
}

#[derive(InputObject)]
pub struct CreateRewardInput {
    pub name: String, // Max 100 utf-8 chars
    pub description: String,
    pub hidden_until: Option<NaiveDateTime>,
    pub max_daily_frequency: Option<f32>,
}

#[derive(InputObject)]
pub struct CreateTradeInput {
    pub task_id: Option<String>,
    pub reward_id: Option<String>,
}

#[Object]
impl MutationRoot {
    async fn create_task(
        &self,
        ctx: &async_graphql::Context<'_>,
        input: CreateTaskInput,
    ) -> Result<TaskObject, async_graphql::Error> {
        let name_len = input.name.chars().count();
        if name_len > 100 || name_len < 1 {
            let msg= format!(
                        "Please provide a name between 1 and 100 characters long. Your current name is {} characters.",
                        input.name.len()
                    );
            return Err(Error::Validation(msg).into_graphql_error());
        }

        let desc_len = input.description.chars().count();
        if desc_len > 10000 {
            let msg = format!(
                "Description is too long ({} characters), max 10,000.",
                desc_len
            );
            return Err(Error::Validation(msg).into_graphql_error());
        }

        let now = Utc::now().naive_utc();
        if let Some(hidden_at) = input.hidden_until {
            if hidden_at <= now {
                let msg = format!("The 'hidden until' date ({}) has already passed or is the current moment. Please select a future date.", input.hidden_until.unwrap());
                return Err(Error::Validation(msg).into_graphql_error());
            }
        }

        if let Some(due_at) = input.due_by {
            if due_at <= now {
                let msg = format!("The 'due_by' date ({}) has already passed or is the current moment. Please select a future date.", input.due_by.unwrap());
                return Err(Error::Validation(msg).into_graphql_error());
            }
        }

        if input.due_by.is_some() && input.min_daily_frequency.is_some() {
            let msg = "A task cannot have both 'due_by' and 'min_daily_frequency'. Please provide only one.".to_string();
            return Err(Error::Validation(msg).into_graphql_error());
        }

        if let Some(freq) = input.min_daily_frequency {
            if freq < 0.0 || freq > 100.0 {
                let msg = format!(
                    "The 'min_daily_frequency must be between 0 and 100. You sent {}.",
                    freq as f32
                );
                return Err(Error::Validation(msg).into_graphql_error());
            }
        }

        let database = ctx.data::<database::Database>().map_err(|e| {
            error!("Database pool not found in context: {:?}", e);
            Error::Internal.into_graphql_error()
        })?;

        let user_id = ctx
            .data::<AuthenticatedUser>()
            .map_err(|e| {
                error!("User not found in context: {:?}", e);
                Error::Internal.into_graphql_error()
            })?
            .user_id;

        let opts = CreateTaskOptions::new(input, user_id);
        let task_row = database.create_task(opts).await.map_err(|e| {
            error!("Database Error: {:?}", e);
            Error::Internal.into_graphql_error()
        })?;

        Ok(task_row.into())
    }

    async fn create_reward(
        &self,
        ctx: &async_graphql::Context<'_>,
        input: CreateRewardInput,
    ) -> Result<RewardObject, async_graphql::Error> {
        let name_len = input.name.chars().count();
        if name_len > 100 || name_len < 1 {
            let msg = format!("Please provide a name between 1 and 100 characters long. Your current name is {} characters.", input.name.len());
            return Err(Error::Validation(msg).into_graphql_error());
        }

        let desc_len = input.description.chars().count();
        if desc_len > 10000 {
            let msg = format!(
                "Description is too long ({} characters), max 10,000.",
                desc_len
            );
            return Err(Error::Validation(msg).into_graphql_error());
        }

        let now = Utc::now().naive_utc();
        if let Some(hidden_at) = input.hidden_until {
            if hidden_at <= now {
                let msg = format!(
                    "The 'hidden until' date ({}) has already passed or is the current moment. Please select a future date.", 
                    input.hidden_until.unwrap()
                );
                return Err(Error::Validation(msg).into_graphql_error());
            }
        }

        if let Some(freq) = input.max_daily_frequency {
            if freq < 0.0 || freq > 100.0 {
                let msg = format!(
                    "The 'max_daily_frequency must be between 0 and 100. You sent {}.",
                    freq
                );
                return Err(Error::Validation(msg).into_graphql_error());
            }
        }

        let database = ctx.data::<database::Database>().map_err(|e| {
            error!("Database pool not found in context: {:?}", e);
            Error::Internal.into_graphql_error()
        })?;

        let user_id = ctx
            .data::<AuthenticatedUser>()
            .map_err(|e| {
                error!("User not found in context: {:?}", e);
                Error::Internal.into_graphql_error()
            })?
            .user_id;

        let opts = CreateRewardOptions::new(input, user_id);
        let task_row = database.create_reward(opts).await.map_err(|e| {
            error!("Database Error: {:?}", e);
            Error::Internal.into_graphql_error()
        })?;

        Ok(task_row.into())
    }

    async fn create_trade(
        &self,
        ctx: &async_graphql::Context<'_>,
        input: CreateTradeInput,
    ) -> Result<TradeObject, async_graphql::Error> {
        if (input.task_id.is_some() && input.reward_id.is_some())
            || input.task_id.is_none() && input.reward_id.is_none()
        {
            let msg = "Must have exactly one of either `task_id` or `reward_id`".to_string();
            return Err(Error::Validation(msg).into_graphql_error());
        };

        let database = ctx.data::<database::Database>().map_err(|e| {
            error!("Database pool not found in context: {:?}", e);
            Error::Internal.into_graphql_error()
        })?;

        let user_id = ctx
            .data::<AuthenticatedUser>()
            .map_err(|e| {
                error!("User not found in context: {:?}", e);
                Error::Internal.into_graphql_error()
            })?
            .user_id;

        if input.task_id.is_some() {
            let task_id = input.task_id.unwrap().parse::<Uuid>().map_err(|_| {
                Error::Validation("Invalid task_id format".to_string()).into_graphql_error()
            })?;
            let opts = CreateTradeWithTaskOptions::new(user_id, task_id, 1000);
            let trade_row = database.create_trade_with_task(opts).await.map_err(|e| {
                error!("Database Error: {:?}", e);
                Error::Internal.into_graphql_error()
            })?;

            Ok(trade_row.into())
        } else {
            let reward_id = input.reward_id.unwrap().parse::<Uuid>().map_err(|_| {
                Error::Validation("Invalid reward_id format".to_string()).into_graphql_error()
            })?;
            let opts = CreateTradeWithRewardOptions::new(user_id, reward_id, 1000);
            let trade_row = database.create_trade_with_reward(opts).await.map_err(|e| {
                error!("Database Error: {:?}", e);
                Error::Internal.into_graphql_error()
            })?;

            Ok(trade_row.into())
        }
    }

    async fn sync_push(
        &self,
        ctx: &async_graphql::Context<'_>,
        tasks: Vec<SyncTaskInput>,
    ) -> Result<SyncPushResponse, async_graphql::Error> {
        let database = ctx.data::<database::Database>().map_err(|e| {
            error!("Database pool not found in context: {:?}", e);
            Error::Internal.into_graphql_error()
        })?;

        let user_id = ctx
            .data::<AuthenticatedUser>()
            .map_err(|e| {
                error!("User not found in context: {:?}", e);
                Error::Internal.into_graphql_error()
            })?
            .user_id;

        let mut result_tasks = Vec::new();

        for task_input in tasks {
            // Validate task ID is a valid UUID
            let task_id = task_input.id.parse::<Uuid>().map_err(|_| {
                Error::Validation(format!("Invalid task id format: {}", task_input.id))
                    .into_graphql_error()
            })?;

            // Validate name length
            let name_len = task_input.name.chars().count();
            if name_len > 100 || name_len < 1 {
                let msg = format!(
                    "Please provide a name between 1 and 100 characters long. Your current name is {} characters.",
                    name_len
                );
                return Err(Error::Validation(msg).into_graphql_error());
            }

            // Validate description length
            let desc_len = task_input.description.chars().count();
            if desc_len > 10000 {
                let msg = format!(
                    "Description is too long ({} characters), max 10,000.",
                    desc_len
                );
                return Err(Error::Validation(msg).into_graphql_error());
            }

            // Validate min_daily_frequency
            if let Some(freq) = task_input.min_daily_frequency {
                if freq < 0.0 || freq > 100.0 {
                    let msg = format!(
                        "The 'min_daily_frequency must be between 0 and 100. You sent {}.",
                        freq as f32
                    );
                    return Err(Error::Validation(msg).into_graphql_error());
                }
            }

            // Check if this task already exists and belongs to this user
            let existing_task = database
                .get_task_by_id(user_id, task_id)
                .await
                .map_err(|e| {
                    error!("Database Error: {:?}", e);
                    Error::Internal.into_graphql_error()
                })?;

            // Save name for comparison after move
            let input_name = task_input.name.clone();

            // If task doesn't exist for this user, check if it exists for any user
            // by attempting upsert - the upsert query handles ownership check
            let upsert_opts = UpsertTaskOptions {
                id: task_id,
                name: task_input.name,
                description: task_input.description,
                created_at: task_input.created_at,
                deleted_at: task_input.deleted_at,
                hidden_until: task_input.hidden_until,
                due_by: task_input.due_by,
                min_daily_frequency: task_input.min_daily_frequency,
                difficulty_rank: task_input.difficulty_rank,
            };

            let task_row = database
                .upsert_task(user_id, upsert_opts)
                .await
                .map_err(|e| {
                    error!("Database Error: {:?}", e);
                    Error::Internal.into_graphql_error()
                })?;

            // Only include task if it belongs to this user (upsert returns the task regardless)
            // Check by comparing if we actually modified it or if it was owned by someone else
            if existing_task.is_some() || task_row.name == input_name {
                result_tasks.push(task_row.into());
            }
        }

        let server_time = Utc::now().naive_utc();

        Ok(SyncPushResponse {
            tasks: result_tasks,
            server_time,
        })
    }
}
