use axum::{
    extract::{Query, State},
    response::IntoResponse,
    Extension, Json,
};
use chrono::{NaiveDateTime, Utc};
use serde::{Deserialize, Serialize};
use tracing::error;
use uuid::Uuid;

use crate::{
    database::{self, Database},
    router::{App, AuthenticatedUser},
};

use super::ApiError;

// ============================================================================
// Request/Response Types
// ============================================================================

#[derive(Deserialize)]
pub struct SyncQueryParams {
    pub since: Option<NaiveDateTime>,
}

#[derive(Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct SyncPushRequest {
    pub tasks: Option<Vec<SyncTaskInput>>,
    pub trades: Option<Vec<SyncTradeInput>>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncTaskInput {
    pub id: String,
    pub name: String,
    pub description: String,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub hidden_until: Option<NaiveDateTime>,
    pub due_by: Option<NaiveDateTime>,
    pub min_daily_frequency: Option<f64>,
    pub difficulty_rank: Option<String>,
    pub completed_at: Option<NaiveDateTime>,
    pub habit: bool,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncTradeInput {
    pub id: String,
    pub task_id: Option<String>,
    pub reward_id: Option<String>,
    pub amount: i32,
    pub created_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncResponse {
    pub tasks: Vec<TaskOutput>,
    pub trades: Vec<TradeOutput>,
    pub balance: BalanceOutput,
    pub server_time: NaiveDateTime,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TaskOutput {
    pub id: String,
    pub name: String,
    pub description: String,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub hidden_until: Option<NaiveDateTime>,
    pub due_by: Option<NaiveDateTime>,
    pub min_daily_frequency: Option<f64>,
    pub difficulty_rank: Option<String>,
    pub completed_at: Option<NaiveDateTime>,
    pub habit: bool,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TradeOutput {
    pub id: String,
    pub task_id: Option<String>,
    pub reward_id: Option<String>,
    pub amount: i32,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BalanceOutput {
    pub soy_balance: f64,
    pub tofu_balance: f64,
}

// ============================================================================
// Handlers
// ============================================================================

/// GET /api/sync - Pull changes since timestamp
pub async fn get_sync(
    State(app): State<App>,
    Extension(user): Extension<AuthenticatedUser>,
    Query(params): Query<SyncQueryParams>,
) -> Result<impl IntoResponse, ApiError> {
    let task_rows = app
        .database
        .get_tasks_since(user.user_id, params.since)
        .await
        .map_err(|e| {
            error!("Database Error: {:?}", e);
            ApiError::Internal
        })?;

    let trade_rows = app
        .database
        .get_trades_since(user.user_id, params.since)
        .await
        .map_err(|e| {
            error!("Database Error: {:?}", e);
            ApiError::Internal
        })?;

    let balance_row = app.database.get_user_balance(user.user_id).await.map_err(|e| {
        error!("Database Error: {:?}", e);
        ApiError::Internal
    })?;

    let tasks: Vec<TaskOutput> = task_rows
        .into_iter()
        .map(|row| TaskOutput {
            id: row.id.to_string(),
            name: row.name,
            description: row.description,
            created_at: row.created_at,
            updated_at: row.updated_at,
            deleted_at: row.deleted_at,
            hidden_until: row.hidden_until,
            due_by: row.due_by,
            min_daily_frequency: row.min_daily_frequency,
            difficulty_rank: row.difficulty_rank,
            completed_at: row.completed_at,
            habit: row.habit,
        })
        .collect();

    let trades: Vec<TradeOutput> = trade_rows
        .into_iter()
        .map(|row| TradeOutput {
            id: row.id.to_string(),
            task_id: row.task_id.map(|id| id.to_string()),
            reward_id: row.reward_id.map(|id| id.to_string()),
            amount: row.amount,
            created_at: row.created_at,
            updated_at: row.updated_at,
            deleted_at: row.deleted_at,
        })
        .collect();

    let server_time = Utc::now().naive_utc();

    Ok(Json(SyncResponse {
        tasks,
        trades,
        balance: BalanceOutput {
            soy_balance: balance_row.soy_balance,
            tofu_balance: balance_row.tofu_balance,
        },
        server_time,
    }))
}

/// POST /api/sync - Push changes (atomic batch upsert)
pub async fn post_sync(
    State(app): State<App>,
    Extension(user): Extension<AuthenticatedUser>,
    Json(input): Json<SyncPushRequest>,
) -> Result<impl IntoResponse, ApiError> {
    // Begin transaction for atomicity
    let mut tx = app.database.begin_transaction().await.map_err(|e| {
        error!("Failed to begin transaction: {:?}", e);
        ApiError::Internal
    })?;

    let mut result_tasks = Vec::new();
    let mut result_trades = Vec::new();

    // Process tasks first (trades may reference these)
    if let Some(tasks) = input.tasks {
        for task_input in tasks {
            // Validate task ID is a valid UUID
            let task_id = task_input.id.parse::<Uuid>().map_err(|_| {
                ApiError::Validation(format!("Invalid task id format: {}", task_input.id))
            })?;

            // Validate name length
            let name_len = task_input.name.chars().count();
            if name_len > 100 || name_len < 1 {
                let msg = format!(
                    "Please provide a name between 1 and 100 characters long. Your current name is {} characters.",
                    name_len
                );
                return Err(ApiError::Validation(msg));
            }

            // Validate description length
            let desc_len = task_input.description.chars().count();
            if desc_len > 10000 {
                let msg = format!(
                    "Description is too long ({} characters), max 10,000.",
                    desc_len
                );
                return Err(ApiError::Validation(msg));
            }

            // Validate min_daily_frequency
            if let Some(freq) = task_input.min_daily_frequency {
                if freq < 0.0 || freq > 100.0 {
                    let msg = format!(
                        "The 'min_daily_frequency must be between 0 and 100. You sent {}.",
                        freq as i32
                    );
                    return Err(ApiError::Validation(msg));
                }
            }

            // Habit validation: habits cannot have completed_at
            if task_input.habit && task_input.completed_at.is_some() {
                let msg = "Habits cannot have a 'completed_at' timestamp. Either set 'habit' to false or remove 'completed_at'.".to_string();
                return Err(ApiError::Validation(msg));
            }

            // Habit validation: non-habits cannot have min_daily_frequency
            if !task_input.habit && task_input.min_daily_frequency.is_some() {
                let msg = "Non-habit tasks cannot have 'min_daily_frequency'. Either set 'habit' to true or remove 'min_daily_frequency'.".to_string();
                return Err(ApiError::Validation(msg));
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

            let task_row =
                Database::upsert_task_tx(&mut tx, user.user_id, &upsert_opts)
                    .await
                    .map_err(|e| {
                        error!("Database Error upserting task: {:?}", e);
                        ApiError::Internal
                    })?;

            result_tasks.push(TaskOutput {
                id: task_row.id.to_string(),
                name: task_row.name,
                description: task_row.description,
                created_at: task_row.created_at,
                updated_at: task_row.updated_at,
                deleted_at: task_row.deleted_at,
                hidden_until: task_row.hidden_until,
                due_by: task_row.due_by,
                min_daily_frequency: task_row.min_daily_frequency,
                difficulty_rank: task_row.difficulty_rank,
                completed_at: task_row.completed_at,
                habit: task_row.habit,
            });
        }
    }

    // Process trades second (they may reference tasks created above)
    if let Some(trades) = input.trades {
        for trade_input in trades {
            // Validate trade ID is a valid UUID
            let trade_id = trade_input.id.parse::<Uuid>().map_err(|_| {
                ApiError::Validation(format!("Invalid trade id format: {}", trade_input.id))
            })?;

            // Validate task_id if provided
            let task_id = if let Some(task_id_str) = &trade_input.task_id {
                Some(task_id_str.parse::<Uuid>().map_err(|_| {
                    ApiError::Validation(format!("Invalid task_id format: {}", task_id_str))
                })?)
            } else {
                None
            };

            // Validate reward_id if provided
            let reward_id = if let Some(reward_id_str) = &trade_input.reward_id {
                Some(reward_id_str.parse::<Uuid>().map_err(|_| {
                    ApiError::Validation(format!("Invalid reward_id format: {}", reward_id_str))
                })?)
            } else {
                None
            };

            // Trade must have either task_id or reward_id
            if task_id.is_none() && reward_id.is_none() {
                let msg = "Trade must have a task_id or reward_id".to_string();
                return Err(ApiError::Validation(msg));
            }

            let upsert_opts = database::UpsertTradeOptions {
                id: trade_id,
                task_id,
                reward_id,
                amount: trade_input.amount,
                created_at: trade_input.created_at,
                deleted_at: trade_input.deleted_at,
            };

            let trade_row =
                Database::upsert_trade_tx(&mut tx, user.user_id, &upsert_opts)
                    .await
                    .map_err(|e| {
                        error!("Database Error upserting trade: {:?}", e);
                        ApiError::Internal
                    })?;

            result_trades.push(TradeOutput {
                id: trade_row.id.to_string(),
                task_id: trade_row.task_id.map(|id| id.to_string()),
                reward_id: trade_row.reward_id.map(|id| id.to_string()),
                amount: trade_row.amount,
                created_at: trade_row.created_at,
                updated_at: trade_row.updated_at,
                deleted_at: trade_row.deleted_at,
            });
        }
    }

    // Recalculate balance from all trades
    let new_balance = Database::recalculate_balance_tx(&mut tx, user.user_id)
        .await
        .map_err(|e| {
            error!("Database Error recalculating balance: {:?}", e);
            ApiError::Internal
        })?;

    // Commit the transaction
    tx.commit().await.map_err(|e| {
        error!("Failed to commit transaction: {:?}", e);
        ApiError::Internal
    })?;

    // Get current tofu balance (not modified by trades)
    let balance_row = app.database.get_user_balance(user.user_id).await.map_err(|e| {
        error!("Database Error getting balance: {:?}", e);
        ApiError::Internal
    })?;

    let server_time = Utc::now().naive_utc();

    Ok(Json(SyncResponse {
        tasks: result_tasks,
        trades: result_trades,
        balance: BalanceOutput {
            soy_balance: new_balance,
            tofu_balance: balance_row.tofu_balance,
        },
        server_time,
    }))
}
