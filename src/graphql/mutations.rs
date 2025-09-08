use crate::{
    database::{self, CreateTaskOptions},
    router::AuthenticatedUser,
};
use async_graphql::{InputObject, Object};
use chrono::{NaiveDateTime, Utc};

use super::objects::TaskObject;
pub struct MutationRoot;

#[derive(InputObject)]
pub struct CreateTaskInput {
    #[graphql(validator(min_length = 1, max_length = 100))]
    pub name: String, // Max 100 utf-8 chars
    #[graphql(validator(max_length = 16384))]
    pub description: String,
    pub hidden_until: Option<NaiveDateTime>,
    pub due_by: Option<NaiveDateTime>, // Must be in future if exists
}

#[Object]
impl MutationRoot {
    async fn create_task(
        &self,
        ctx: &async_graphql::Context<'_>,
        input: CreateTaskInput,
    ) -> Result<TaskObject, &'static str> {
        let now = Utc::now().naive_utc();

        if let Some(hidden_at) = input.hidden_until {
            if hidden_at <= now {
                return Err("`hidden_until` must be in the future.");
            }
        }

        if let Some(due_at) = input.due_by {
            if due_at <= now {
                return Err("`due_by` must be in the future.");
            }
        }
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
}

#[derive(InputObject)]
pub struct CreateTradeInput {
    // Must have EITHER one or the other
    task_id: Option<String>,
    reward_id: Option<String>,
}
