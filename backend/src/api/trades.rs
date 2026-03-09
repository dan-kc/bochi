use axum::{extract::State, http::StatusCode, response::IntoResponse, Extension, Json};
use chrono::NaiveDateTime;
use serde::{Deserialize, Serialize};
use tracing::error;
use uuid::Uuid;

use crate::{
    database::{CreateTradeWithHabitOptions, CreateTradeWithRewardOptions},
    router::{App, AuthenticatedUser},
};

use super::ApiError;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CreateTradeRequest {
    pub habit_id: Option<String>,
    pub reward_id: Option<String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TradeResponse {
    pub id: String,
    pub amount: i32,
    pub created_at: NaiveDateTime,
    pub tradable_item: TradableItem,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TradableItem {
    #[serde(rename = "type")]
    pub item_type: String,
    pub id: String,
    pub name: String,
    pub description: String,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    // Habit fields
    #[serde(skip_serializing_if = "Option::is_none")]
    pub min_daily_frequency: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub difficulty_rank: Option<String>,
    // Reward fields
    #[serde(skip_serializing_if = "Option::is_none")]
    pub max_daily_frequency: Option<f32>,
}

pub async fn create_trade(
    State(app): State<App>,
    Extension(user): Extension<AuthenticatedUser>,
    Json(input): Json<CreateTradeRequest>,
) -> Result<impl IntoResponse, ApiError> {
    // Validate: must have exactly one of habit_id or reward_id
    if (input.habit_id.is_some() && input.reward_id.is_some())
        || (input.habit_id.is_none() && input.reward_id.is_none())
    {
        let msg = "Must have exactly one of either `habit_id` or `reward_id`".to_string();
        return Err(ApiError::Validation(msg));
    }

    if let Some(habit_id_str) = input.habit_id {
        let habit_id = habit_id_str
            .parse::<Uuid>()
            .map_err(|_| ApiError::Validation("Invalid habit_id format".to_string()))?;

        let opts = CreateTradeWithHabitOptions::new(user.user_id, habit_id, 1000);
        let trade_row = app
            .database
            .create_trade_with_habit(opts)
            .await
            .map_err(|e| {
                error!("Database Error: {:?}", e);
                ApiError::Internal
            })?;

        Ok((
            StatusCode::CREATED,
            Json(TradeResponse {
                id: trade_row.id.to_string(),
                amount: trade_row.amount,
                created_at: trade_row.created_at,
                tradable_item: TradableItem {
                    item_type: "Habit".to_string(),
                    id: trade_row.habit_id.to_string(),
                    name: trade_row.habit_name,
                    description: trade_row.habit_description,
                    created_at: trade_row.habit_created_at,
                    updated_at: trade_row.habit_updated_at,
                    deleted_at: trade_row.habit_deleted_at,
                    min_daily_frequency: trade_row.habit_min_daily_frequency,
                    difficulty_rank: trade_row.habit_difficulty_rank,
                    max_daily_frequency: None,
                },
            }),
        ))
    } else {
        let reward_id_str = input.reward_id.unwrap();
        let reward_id = reward_id_str
            .parse::<Uuid>()
            .map_err(|_| ApiError::Validation("Invalid reward_id format".to_string()))?;

        let opts = CreateTradeWithRewardOptions::new(user.user_id, reward_id, 1000);
        let trade_row = app
            .database
            .create_trade_with_reward(opts)
            .await
            .map_err(|e| {
                error!("Database Error: {:?}", e);
                ApiError::Internal
            })?;

        Ok((
            StatusCode::CREATED,
            Json(TradeResponse {
                id: trade_row.id.to_string(),
                amount: trade_row.amount,
                created_at: trade_row.created_at,
                tradable_item: TradableItem {
                    item_type: "Reward".to_string(),
                    id: trade_row.reward_id.to_string(),
                    name: trade_row.reward_name,
                    description: trade_row.reward_description,
                    created_at: trade_row.reward_created_at,
                    updated_at: trade_row.reward_updated_at,
                    deleted_at: trade_row.reward_deleted_at,
                    min_daily_frequency: None,
                    difficulty_rank: None,
                    max_daily_frequency: trade_row.reward_max_daily_frequency,
                },
            }),
        ))
    }
}
