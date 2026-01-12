use std::{any::Any, sync::Arc};
use tracing::error;

use super::objects::{
    RewardObject, SyncInput, SyncResponse, TaskObject, TradeObject, UserBalanceResponse,
};
use crate::{
    database::{
        self, CreateRewardOptions, CreateTaskOptions, CreateTradeWithRewardOptions,
        CreateTradeWithTaskOptions,
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
    pub habit: bool,
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

        // Habit validation: non-habits cannot have min_daily_frequency
        if !input.habit && input.min_daily_frequency.is_some() {
            let msg = "Non-habit tasks cannot have 'min_daily_frequency'. Either set 'habit' to true or remove 'min_daily_frequency'.".to_string();
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

    /// Unified sync mutation - atomically processes tasks and trades in a single transaction
    async fn sync(
        &self,
        ctx: &async_graphql::Context<'_>,
        input: SyncInput,
    ) -> Result<SyncResponse, async_graphql::Error> {
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

        // Begin transaction for atomicity
        let mut tx = database.begin_transaction().await.map_err(|e| {
            error!("Failed to begin transaction: {:?}", e);
            Error::Internal.into_graphql_error()
        })?;

        let mut result_tasks = Vec::new();
        let mut result_trades = Vec::new();

        // Process tasks first (trades may reference these)
        if let Some(tasks) = input.tasks {
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

                // Habit validation: habits cannot have completed_at
                if task_input.habit && task_input.completed_at.is_some() {
                    let msg = "Habits cannot have a 'completed_at' timestamp. Either set 'habit' to false or remove 'completed_at'.".to_string();
                    return Err(Error::Validation(msg).into_graphql_error());
                }

                // Habit validation: non-habits cannot have min_daily_frequency
                if !task_input.habit && task_input.min_daily_frequency.is_some() {
                    let msg = "Non-habit tasks cannot have 'min_daily_frequency'. Either set 'habit' to true or remove 'min_daily_frequency'.".to_string();
                    return Err(Error::Validation(msg).into_graphql_error());
                }

                let upsert_opts = database::UpsertTaskOptions {
                    id: task_id,
                    name: task_input.name,
                    description: task_input.description,
                    created_at: task_input.created_at,
                    deleted_at: task_input.deleted_at,
                    hidden_until: task_input.hidden_until,
                    due_by: task_input.due_by,
                    min_daily_frequency: task_input.min_daily_frequency,
                    difficulty_rank: task_input.difficulty_rank,
                    completed_at: task_input.completed_at,
                    habit: task_input.habit,
                };

                let task_row = database::Database::upsert_task_tx(&mut tx, user_id, &upsert_opts)
                    .await
                    .map_err(|e| {
                        error!("Database Error upserting task: {:?}", e);
                        Error::Internal.into_graphql_error()
                    })?;

                result_tasks.push(task_row.into());
            }
        }

        // Process trades second (they may reference tasks created above)
        if let Some(trades) = input.trades {
            for trade_input in trades {
                // Validate trade ID is a valid UUID
                let trade_id = trade_input.id.parse::<Uuid>().map_err(|_| {
                    Error::Validation(format!("Invalid trade id format: {}", trade_input.id))
                        .into_graphql_error()
                })?;

                // Validate task_id if provided
                let task_id = if let Some(task_id_str) = &trade_input.task_id {
                    Some(task_id_str.parse::<Uuid>().map_err(|_| {
                        Error::Validation(format!("Invalid task_id format: {}", task_id_str))
                            .into_graphql_error()
                    })?)
                } else {
                    None
                };

                // Validate reward_id if provided
                let reward_id = if let Some(reward_id_str) = &trade_input.reward_id {
                    Some(reward_id_str.parse::<Uuid>().map_err(|_| {
                        Error::Validation(format!("Invalid reward_id format: {}", reward_id_str))
                            .into_graphql_error()
                    })?)
                } else {
                    None
                };

                // Trade must have either task_id or reward_id
                if task_id.is_none() && reward_id.is_none() {
                    let msg = "Trade must have a task_id or reward_id".to_string();
                    return Err(Error::Validation(msg).into_graphql_error());
                }

                let upsert_opts = database::UpsertTradeOptions {
                    id: trade_id,
                    task_id,
                    reward_id,
                    amount: trade_input.amount,
                    created_at: trade_input.created_at,
                    deleted_at: trade_input.deleted_at,
                };

                let trade_row = database::Database::upsert_trade_tx(&mut tx, user_id, &upsert_opts)
                    .await
                    .map_err(|e| {
                        error!("Database Error upserting trade: {:?}", e);
                        // Return validation error for foreign key issues
                        if matches!(e, sqlx::Error::RowNotFound) {
                            Error::Validation("Referenced task or reward not found".to_string())
                                .into_graphql_error()
                        } else {
                            Error::Internal.into_graphql_error()
                        }
                    })?;

                result_trades.push(trade_row.into());
            }
        }

        // Recalculate balance from all trades
        let new_balance = database::Database::recalculate_balance_tx(&mut tx, user_id)
            .await
            .map_err(|e| {
                error!("Database Error recalculating balance: {:?}", e);
                Error::Internal.into_graphql_error()
            })?;

        // Commit the transaction
        tx.commit().await.map_err(|e| {
            error!("Failed to commit transaction: {:?}", e);
            Error::Internal.into_graphql_error()
        })?;

        // Get current tofu balance (not modified by trades)
        let balance_row = database.get_user_balance(user_id).await.map_err(|e| {
            error!("Database Error getting balance: {:?}", e);
            Error::Internal.into_graphql_error()
        })?;

        let server_time = Utc::now().naive_utc();

        Ok(SyncResponse {
            tasks: result_tasks,
            trades: result_trades,
            balance: UserBalanceResponse {
                soy_balance: new_balance,
                tofu_balance: balance_row.tofu_balance,
            },
            server_time,
        })
    }
}
