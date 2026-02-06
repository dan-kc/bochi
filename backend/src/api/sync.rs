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
    pub habits: Option<Vec<SyncHabitInput>>,
    pub trades: Option<Vec<SyncTradeInput>>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncHabitInput {
    pub id: String,
    pub name: String,
    pub description: String,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub hidden_until: Option<NaiveDateTime>,
    pub min_daily_frequency: Option<f64>,
    pub difficulty_rank: Option<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncTradeInput {
    pub id: String,
    pub habit_id: Option<String>,
    pub reward_id: Option<String>,
    pub amount: i32,
    pub created_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncResponse {
    pub habits: Vec<HabitOutput>,
    pub trades: Vec<TradeOutput>,
    pub balance: BalanceOutput,
    pub server_time: NaiveDateTime,
    pub email: Option<String>,
    pub is_premium: bool,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HabitOutput {
    pub id: String,
    pub name: String,
    pub description: String,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub hidden_until: Option<NaiveDateTime>,
    pub min_daily_frequency: Option<f64>,
    pub difficulty_rank: Option<String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TradeOutput {
    pub id: String,
    pub habit_id: Option<String>,
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
    let habit_rows = app
        .database
        .get_habits_since(user.user_id, params.since)
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

    let profile_row = app.database.get_user_profile(user.user_id).await.map_err(|e| {
        error!("Database Error: {:?}", e);
        ApiError::Internal
    })?;

    let habits: Vec<HabitOutput> = habit_rows
        .into_iter()
        .map(|row| HabitOutput {
            id: row.id.to_string(),
            name: row.name,
            description: row.description,
            created_at: row.created_at,
            updated_at: row.updated_at,
            deleted_at: row.deleted_at,
            hidden_until: row.hidden_until,
            min_daily_frequency: row.min_daily_frequency,
            difficulty_rank: row.difficulty_rank,
        })
        .collect();

    let trades: Vec<TradeOutput> = trade_rows
        .into_iter()
        .map(|row| TradeOutput {
            id: row.id.to_string(),
            habit_id: row.habit_id.map(|id| id.to_string()),
            reward_id: row.reward_id.map(|id| id.to_string()),
            amount: row.amount,
            created_at: row.created_at,
            updated_at: row.updated_at,
            deleted_at: row.deleted_at,
        })
        .collect();

    let server_time = Utc::now().naive_utc();

    Ok(Json(SyncResponse {
        habits,
        trades,
        balance: BalanceOutput {
            soy_balance: balance_row.soy_balance,
            tofu_balance: balance_row.tofu_balance,
        },
        server_time,
        email: profile_row.email,
        is_premium: profile_row.premium,
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

    let mut result_habits = Vec::new();
    let mut result_trades = Vec::new();

    // Process habits first (trades may reference these)
    if let Some(habits) = input.habits {
        for habit_input in habits {
            // Validate habit ID is a valid UUID
            let habit_id = habit_input.id.parse::<Uuid>().map_err(|_| {
                ApiError::Validation(format!("Invalid habit id format: {}", habit_input.id))
            })?;

            // Validate name length
            let name_len = habit_input.name.chars().count();
            if name_len > 100 || name_len < 1 {
                let msg = format!(
                    "Please provide a name between 1 and 100 characters long. Your current name is {} characters.",
                    name_len
                );
                return Err(ApiError::Validation(msg));
            }

            // Validate description length
            let desc_len = habit_input.description.chars().count();
            if desc_len > 10000 {
                let msg = format!(
                    "Description is too long ({} characters), max 10,000.",
                    desc_len
                );
                return Err(ApiError::Validation(msg));
            }

            // Validate min_daily_frequency
            if let Some(freq) = habit_input.min_daily_frequency {
                if freq < 0.0 || freq > 100.0 {
                    let msg = format!(
                        "The 'min_daily_frequency must be between 0 and 100. You sent {}.",
                        freq as i32
                    );
                    return Err(ApiError::Validation(msg));
                }
            }

            let upsert_opts = database::UpsertHabitOptions {
                id: habit_id,
                name: habit_input.name,
                description: habit_input.description,
                created_at: habit_input.created_at,
                deleted_at: habit_input.deleted_at,
                hidden_until: habit_input.hidden_until,
                min_daily_frequency: habit_input.min_daily_frequency,
                difficulty_rank: habit_input.difficulty_rank,
            };

            let habit_row =
                Database::upsert_habit_tx(&mut tx, user.user_id, &upsert_opts)
                    .await
                    .map_err(|e| {
                        error!("Database Error upserting habit: {:?}", e);
                        ApiError::Internal
                    })?;

            result_habits.push(HabitOutput {
                id: habit_row.id.to_string(),
                name: habit_row.name,
                description: habit_row.description,
                created_at: habit_row.created_at,
                updated_at: habit_row.updated_at,
                deleted_at: habit_row.deleted_at,
                hidden_until: habit_row.hidden_until,
                min_daily_frequency: habit_row.min_daily_frequency,
                difficulty_rank: habit_row.difficulty_rank,
            });
        }
    }

    // Process trades second (they may reference habits created above)
    if let Some(trades) = input.trades {
        for trade_input in trades {
            // Validate trade ID is a valid UUID
            let trade_id = trade_input.id.parse::<Uuid>().map_err(|_| {
                ApiError::Validation(format!("Invalid trade id format: {}", trade_input.id))
            })?;

            // Validate habit_id if provided
            let habit_id = if let Some(habit_id_str) = &trade_input.habit_id {
                Some(habit_id_str.parse::<Uuid>().map_err(|_| {
                    ApiError::Validation(format!("Invalid habit_id format: {}", habit_id_str))
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

            // Trade must have either habit_id or reward_id
            if habit_id.is_none() && reward_id.is_none() {
                let msg = "Trade must have a habit_id or reward_id".to_string();
                return Err(ApiError::Validation(msg));
            }

            let upsert_opts = database::UpsertTradeOptions {
                id: trade_id,
                habit_id,
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
                habit_id: trade_row.habit_id.map(|id| id.to_string()),
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

    let profile_row = app.database.get_user_profile(user.user_id).await.map_err(|e| {
        error!("Database Error getting profile: {:?}", e);
        ApiError::Internal
    })?;

    let server_time = Utc::now().naive_utc();

    Ok(Json(SyncResponse {
        habits: result_habits,
        trades: result_trades,
        balance: BalanceOutput {
            soy_balance: new_balance,
            tofu_balance: balance_row.tofu_balance,
        },
        server_time,
        email: profile_row.email,
        is_premium: profile_row.premium,
    }))
}
