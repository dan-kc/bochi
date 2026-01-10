use async_graphql::Object;
use chrono::{NaiveDateTime, Utc};
use tracing::error;

use crate::database;
use crate::router::AuthenticatedUser;

use super::objects::{SyncPullResponse, TaskObject};

pub struct QueryRoot;

#[Object]
impl QueryRoot {
    async fn hello(&self, _ctx: &async_graphql::Context<'_>) -> &'static str {
        "Wag1"
    }

    async fn sync_pull(
        &self,
        ctx: &async_graphql::Context<'_>,
        since: Option<NaiveDateTime>,
    ) -> Result<SyncPullResponse, async_graphql::Error> {
        let database = ctx.data::<database::Database>().map_err(|e| {
            error!("Database pool not found in context: {:?}", e);
            async_graphql::Error::new("Internal server error")
        })?;

        let user_id = ctx
            .data::<AuthenticatedUser>()
            .map_err(|e| {
                error!("User not found in context: {:?}", e);
                async_graphql::Error::new("Internal server error")
            })?
            .user_id;

        let task_rows = database
            .get_tasks_since(user_id, since)
            .await
            .map_err(|e| {
                error!("Database Error: {:?}", e);
                async_graphql::Error::new("Internal server error")
            })?;

        let tasks: Vec<TaskObject> = task_rows.into_iter().map(|row| row.into()).collect();
        let server_time = Utc::now().naive_utc();

        Ok(SyncPullResponse { tasks, server_time })
    }
}
