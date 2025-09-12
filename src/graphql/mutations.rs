use std::{any::Any, sync::Arc};
use tracing::error;

use super::objects::{RewardObject, TaskObject};
use crate::{
    database::{self, CreateRewardOptions, CreateTaskOptions},
    router::AuthenticatedUser,
};
use async_graphql::{ErrorExtensionValues, InputObject, Object};
use chrono::{NaiveDateTime, Utc};

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
}

#[derive(InputObject)]
pub struct CreateRewardInput {
    pub name: String, // Max 100 utf-8 chars
    pub description: String,
    pub hidden_until: Option<NaiveDateTime>,
    pub max_daily_frequency: Option<f32>,
}

#[Object]
impl MutationRoot {
    async fn create_task(
        &self,
        ctx: &async_graphql::Context<'_>,
        input: CreateTaskInput,
    ) -> Result<TaskObject, async_graphql::Error> {
        let now = Utc::now().naive_utc();
        if input.name.len() > 100 || input.name.len() < 1 {
            let msg= format!(
                        "Please provide a name between 1 and 100 characters long. Your current name is {} characters.",
                        input.name.len()
                    );
            return Err(Error::Validation(msg).into_graphql_error());
        }

        if input.description.len() > 16384 {
            let msg = format!(
                "Description is too long ({} characters), max 16384.",
                input.description.len()
            );
            return Err(Error::Validation(msg).into_graphql_error());
        }

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
        let now = Utc::now().naive_utc();
        if input.name.len() > 100 || input.name.len() < 1 {
            let msg = format!("Please provide a name between 1 and 100 characters long. Your current name is {} characters.", input.name.len());
            return Err(Error::Validation(msg).into_graphql_error());
        }
        if input.description.len() > 16384 {
            let msg = format!(
                "Description is too long ({} characters), max 16384.",
                input.description.len()
            );
            return Err(Error::Validation(msg).into_graphql_error());
        }

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
}
