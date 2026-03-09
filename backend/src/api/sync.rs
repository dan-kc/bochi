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
    pub tags: Option<Vec<SyncTagInput>>,
    pub habit_tags: Option<Vec<SyncHabitTagInput>>,
    pub rewards: Option<Vec<SyncRewardInput>>,
    pub reward_tags: Option<Vec<SyncRewardTagInput>>,
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

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncTagInput {
    pub id: String,
    pub name: String,
    pub color_hex: String,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncHabitTagInput {
    pub habit_id: String,
    pub tag_id: String,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncRewardInput {
    pub id: String,
    pub name: String,
    pub description: String,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub max_daily_frequency: Option<f64>,
    pub damage_rank: Option<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncRewardTagInput {
    pub reward_id: String,
    pub tag_id: String,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncResponse {
    pub habits: Vec<HabitOutput>,
    pub trades: Vec<TradeOutput>,
    pub tags: Vec<TagOutput>,
    pub habit_tags: Vec<HabitTagOutput>,
    pub rewards: Vec<RewardOutput>,
    pub reward_tags: Vec<RewardTagOutput>,
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
pub struct TagOutput {
    pub id: String,
    pub name: String,
    pub color_hex: String,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HabitTagOutput {
    pub habit_id: String,
    pub tag_id: String,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RewardOutput {
    pub id: String,
    pub name: String,
    pub description: String,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub max_daily_frequency: Option<f64>,
    pub damage_rank: Option<String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RewardTagOutput {
    pub reward_id: String,
    pub tag_id: String,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BalanceOutput {
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

    let balance_row = app
        .database
        .get_user_balance(user.user_id)
        .await
        .map_err(|e| {
            error!("Database Error: {:?}", e);
            ApiError::Internal
        })?;

    let profile_row = app
        .database
        .get_user_profile(user.user_id)
        .await
        .map_err(|e| {
            error!("Database Error: {:?}", e);
            ApiError::Internal
        })?;

    let tag_rows = app
        .database
        .get_tags_since(user.user_id, params.since)
        .await
        .map_err(|e| {
            error!("Database Error: {:?}", e);
            ApiError::Internal
        })?;

    let habit_tag_rows = app
        .database
        .get_habit_tags_since(user.user_id, params.since)
        .await
        .map_err(|e| {
            error!("Database Error: {:?}", e);
            ApiError::Internal
        })?;

    let reward_rows = app
        .database
        .get_rewards_since(user.user_id, params.since)
        .await
        .map_err(|e| {
            error!("Database Error: {:?}", e);
            ApiError::Internal
        })?;

    let reward_tag_rows = app
        .database
        .get_reward_tags_since(user.user_id, params.since)
        .await
        .map_err(|e| {
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

    let tags: Vec<TagOutput> = tag_rows
        .into_iter()
        .map(|row| TagOutput {
            id: row.id.to_string(),
            name: row.name,
            color_hex: row.color_hex.trim().to_string(),
            created_at: row.created_at,
            updated_at: row.updated_at,
            deleted_at: row.deleted_at,
        })
        .collect();

    let habit_tags: Vec<HabitTagOutput> = habit_tag_rows
        .into_iter()
        .map(|row| HabitTagOutput {
            habit_id: row.habit_id.to_string(),
            tag_id: row.tag_id.to_string(),
            created_at: row.created_at,
            updated_at: row.updated_at,
            deleted_at: row.deleted_at,
        })
        .collect();

    let rewards: Vec<RewardOutput> = reward_rows
        .into_iter()
        .map(|row| RewardOutput {
            id: row.id.to_string(),
            name: row.name,
            description: row.description,
            created_at: row.created_at,
            updated_at: row.updated_at,
            deleted_at: row.deleted_at,
            max_daily_frequency: row.max_daily_frequency.map(|f| f as f64),
            damage_rank: row.damage_rank,
        })
        .collect();

    let reward_tags: Vec<RewardTagOutput> = reward_tag_rows
        .into_iter()
        .map(|row| RewardTagOutput {
            reward_id: row.reward_id.to_string(),
            tag_id: row.tag_id.to_string(),
            created_at: row.created_at,
            updated_at: row.updated_at,
            deleted_at: row.deleted_at,
        })
        .collect();

    let server_time = Utc::now().naive_utc();

    Ok(Json(SyncResponse {
        habits,
        trades,
        tags,
        habit_tags,
        rewards,
        reward_tags,
        balance: BalanceOutput {
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
    let mut result_tags = Vec::new();
    let mut result_habit_tags = Vec::new();
    let mut result_rewards = Vec::new();
    let mut result_reward_tags = Vec::new();

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
                min_daily_frequency: habit_input.min_daily_frequency,
                difficulty_rank: habit_input.difficulty_rank,
            };

            let habit_row = Database::upsert_habit_tx(&mut tx, user.user_id, &upsert_opts)
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
                min_daily_frequency: habit_row.min_daily_frequency,
                difficulty_rank: habit_row.difficulty_rank,
            });
        }
    }

    // Process rewards second (trades may reference these)
    if let Some(rewards) = input.rewards {
        for reward_input in rewards {
            // Validate reward ID is a valid UUID
            let reward_id = reward_input.id.parse::<Uuid>().map_err(|_| {
                ApiError::Validation(format!("Invalid reward id format: {}", reward_input.id))
            })?;

            // Validate name length
            let name_len = reward_input.name.chars().count();
            if name_len > 100 || name_len < 1 {
                let msg = format!(
                    "Please provide a name between 1 and 100 characters long. Your current name is {} characters.",
                    name_len
                );
                return Err(ApiError::Validation(msg));
            }

            // Validate description length
            let desc_len = reward_input.description.chars().count();
            if desc_len > 10000 {
                let msg = format!(
                    "Description is too long ({} characters), max 10,000.",
                    desc_len
                );
                return Err(ApiError::Validation(msg));
            }

            // Validate max_daily_frequency
            if let Some(freq) = reward_input.max_daily_frequency {
                if freq < 0.0 || freq > 100.0 {
                    let msg = format!(
                        "The 'max_daily_frequency' must be between 0 and 100. You sent {}.",
                        freq as i32
                    );
                    return Err(ApiError::Validation(msg));
                }
            }

            let upsert_opts = database::UpsertRewardOptions {
                id: reward_id,
                name: reward_input.name,
                description: reward_input.description,
                created_at: reward_input.created_at,
                deleted_at: reward_input.deleted_at,
                max_daily_frequency: reward_input.max_daily_frequency,
                damage_rank: reward_input.damage_rank,
            };

            let reward_row = Database::upsert_reward_tx(&mut tx, user.user_id, &upsert_opts)
                .await
                .map_err(|e| {
                    error!("Database Error upserting reward: {:?}", e);
                    ApiError::Internal
                })?;

            result_rewards.push(RewardOutput {
                id: reward_row.id.to_string(),
                name: reward_row.name,
                description: reward_row.description,
                created_at: reward_row.created_at,
                updated_at: reward_row.updated_at,
                deleted_at: reward_row.deleted_at,
                max_daily_frequency: reward_row.max_daily_frequency.map(|f| f as f64),
                damage_rank: reward_row.damage_rank,
            });
        }
    }

    // Process trades third (they may reference habits or rewards created above)
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

            let trade_row = Database::upsert_trade_tx(&mut tx, user.user_id, &upsert_opts)
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

    // Process tags third (habit_tags may reference these)
    if let Some(tags) = input.tags {
        for tag_input in tags {
            // Validate tag ID is a valid UUID
            let tag_id = tag_input.id.parse::<Uuid>().map_err(|_| {
                ApiError::Validation(format!("Invalid tag id format: {}", tag_input.id))
            })?;

            // Validate name length
            let name_len = tag_input.name.chars().count();
            if name_len > 100 || name_len < 1 {
                let msg = format!(
                    "Tag name must be between 1 and 100 characters. Your current name is {} characters.",
                    name_len
                );
                return Err(ApiError::Validation(msg));
            }

            // Validate color_hex format (should be #RRGGBBAA)
            let color_hex = &tag_input.color_hex;
            let valid_format = color_hex.starts_with('#')
                && (color_hex.len() == 7 || color_hex.len() == 9)
                && color_hex[1..].chars().all(|c| c.is_ascii_hexdigit());
            if !valid_format {
                let msg = format!(
                    "Invalid color_hex format: {}. Expected format: #RRGGBB or #RRGGBBAA",
                    color_hex
                );
                return Err(ApiError::Validation(msg));
            }

            let upsert_opts = database::UpsertTagOptions {
                id: tag_id,
                name: tag_input.name,
                color_hex: tag_input.color_hex,
                created_at: tag_input.created_at,
                deleted_at: tag_input.deleted_at,
            };

            let tag_row = Database::upsert_tag_tx(&mut tx, user.user_id, &upsert_opts)
                .await
                .map_err(|e| {
                    error!("Database Error upserting tag: {:?}", e);
                    ApiError::Internal
                })?;

            result_tags.push(TagOutput {
                id: tag_row.id.to_string(),
                name: tag_row.name,
                color_hex: tag_row.color_hex.trim().to_string(),
                created_at: tag_row.created_at,
                updated_at: tag_row.updated_at,
                deleted_at: tag_row.deleted_at,
            });
        }
    }

    // Process habit_tags fourth (they reference habits and tags)
    if let Some(habit_tags) = input.habit_tags {
        for habit_tag_input in habit_tags {
            // Validate habit_id is a valid UUID
            let habit_id = habit_tag_input.habit_id.parse::<Uuid>().map_err(|_| {
                ApiError::Validation(format!(
                    "Invalid habit_id format: {}",
                    habit_tag_input.habit_id
                ))
            })?;

            // Validate tag_id is a valid UUID
            let tag_id = habit_tag_input.tag_id.parse::<Uuid>().map_err(|_| {
                ApiError::Validation(format!(
                    "Invalid tag_id format: {}",
                    habit_tag_input.tag_id
                ))
            })?;

            let upsert_opts = database::UpsertHabitTagOptions {
                habit_id,
                tag_id,
                created_at: habit_tag_input.created_at,
                deleted_at: habit_tag_input.deleted_at,
            };

            let habit_tag_row =
                Database::upsert_habit_tag_tx(&mut tx, user.user_id, &upsert_opts)
                    .await
                    .map_err(|e| {
                        error!("Database Error upserting habit_tag: {:?}", e);
                        ApiError::Validation(format!(
                            "Invalid habit or tag reference for habit_id: {}, tag_id: {}",
                            habit_id, tag_id
                        ))
                    })?;

            result_habit_tags.push(HabitTagOutput {
                habit_id: habit_tag_row.habit_id.to_string(),
                tag_id: habit_tag_row.tag_id.to_string(),
                created_at: habit_tag_row.created_at,
                updated_at: habit_tag_row.updated_at,
                deleted_at: habit_tag_row.deleted_at,
            });
        }
    }

    // Process reward_tags sixth (they reference rewards and tags)
    if let Some(reward_tags) = input.reward_tags {
        for reward_tag_input in reward_tags {
            // Validate reward_id is a valid UUID
            let reward_id = reward_tag_input.reward_id.parse::<Uuid>().map_err(|_| {
                ApiError::Validation(format!(
                    "Invalid reward_id format: {}",
                    reward_tag_input.reward_id
                ))
            })?;

            // Validate tag_id is a valid UUID
            let tag_id = reward_tag_input.tag_id.parse::<Uuid>().map_err(|_| {
                ApiError::Validation(format!(
                    "Invalid tag_id format: {}",
                    reward_tag_input.tag_id
                ))
            })?;

            let upsert_opts = database::UpsertRewardTagOptions {
                reward_id,
                tag_id,
                created_at: reward_tag_input.created_at,
                deleted_at: reward_tag_input.deleted_at,
            };

            let reward_tag_row =
                Database::upsert_reward_tag_tx(&mut tx, user.user_id, &upsert_opts)
                    .await
                    .map_err(|e| {
                        error!("Database Error upserting reward_tag: {:?}", e);
                        ApiError::Validation(format!(
                            "Invalid reward or tag reference for reward_id: {}, tag_id: {}",
                            reward_id, tag_id
                        ))
                    })?;

            result_reward_tags.push(RewardTagOutput {
                reward_id: reward_tag_row.reward_id.to_string(),
                tag_id: reward_tag_row.tag_id.to_string(),
                created_at: reward_tag_row.created_at,
                updated_at: reward_tag_row.updated_at,
                deleted_at: reward_tag_row.deleted_at,
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

    let profile_row = app
        .database
        .get_user_profile(user.user_id)
        .await
        .map_err(|e| {
            error!("Database Error getting profile: {:?}", e);
            ApiError::Internal
        })?;

    let server_time = Utc::now().naive_utc();

    Ok(Json(SyncResponse {
        habits: result_habits,
        trades: result_trades,
        tags: result_tags,
        habit_tags: result_habit_tags,
        rewards: result_rewards,
        reward_tags: result_reward_tags,
        balance: BalanceOutput {
            tofu_balance: new_balance,
        },
        server_time,
        email: profile_row.email,
        is_premium: profile_row.premium,
    }))
}
