use async_graphql::Object;
use chrono::{NaiveDateTime, Utc};
use tracing::error;

use crate::database;
use crate::router::AuthenticatedUser;

use super::objects::{SyncResponse, SyncTradeObject, TaskObject, UserBalanceResponse};

pub struct QueryRoot;

#[Object]
impl QueryRoot {
    async fn hello(&self, _ctx: &async_graphql::Context<'_>) -> &'static str {
        "Wag1"
    }

    async fn balance(
        &self,
        ctx: &async_graphql::Context<'_>,
    ) -> Result<UserBalanceResponse, async_graphql::Error> {
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

        let balance_row = database.get_user_balance(user_id).await.map_err(|e| {
            error!("Database Error: {:?}", e);
            async_graphql::Error::new("Internal server error")
        })?;

        Ok(UserBalanceResponse {
            soy_balance: balance_row.soy_balance,
            tofu_balance: balance_row.tofu_balance,
        })
    }

    /// Unified sync query - returns all entity types (tasks, trades) modified since timestamp
    async fn sync(
        &self,
        ctx: &async_graphql::Context<'_>,
        since: Option<NaiveDateTime>,
    ) -> Result<SyncResponse, async_graphql::Error> {
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

        // Fetch all entity types
        let task_rows = database
            .get_tasks_since(user_id, since)
            .await
            .map_err(|e| {
                error!("Database Error: {:?}", e);
                async_graphql::Error::new("Internal server error")
            })?;

        let trade_rows = database
            .get_trades_since(user_id, since)
            .await
            .map_err(|e| {
                error!("Database Error: {:?}", e);
                async_graphql::Error::new("Internal server error")
            })?;

        let balance_row = database.get_user_balance(user_id).await.map_err(|e| {
            error!("Database Error: {:?}", e);
            async_graphql::Error::new("Internal server error")
        })?;

        let tasks: Vec<TaskObject> = task_rows.into_iter().map(|row| row.into()).collect();
        let trades: Vec<SyncTradeObject> = trade_rows.into_iter().map(|row| row.into()).collect();
        let server_time = Utc::now().naive_utc();

        Ok(SyncResponse {
            tasks,
            trades,
            balance: UserBalanceResponse {
                soy_balance: balance_row.soy_balance,
                tofu_balance: balance_row.tofu_balance,
            },
            server_time,
        })
    }
}
