use axum::{extract::State, http::StatusCode, response::IntoResponse, Extension, Json};
use chrono::{NaiveDateTime, Utc};
use serde::{Deserialize, Serialize};
use tracing::error;

use crate::{
    database::CreateRewardOptions,
    router::{App, AuthenticatedUser},
};

use super::ApiError;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CreateRewardRequest {
    pub name: String,
    pub description: String,
    pub hidden_until: Option<NaiveDateTime>,
    pub max_daily_frequency: Option<f32>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RewardResponse {
    pub id: String,
    pub name: String,
    pub description: String,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub hidden_until: Option<NaiveDateTime>,
    pub max_daily_frequency: Option<f32>,
}

pub async fn create_reward(
    State(app): State<App>,
    Extension(user): Extension<AuthenticatedUser>,
    Json(input): Json<CreateRewardRequest>,
) -> Result<impl IntoResponse, ApiError> {
    // Validate name length
    let name_len = input.name.chars().count();
    if name_len > 100 || name_len < 1 {
        let msg = format!(
            "Please provide a name between 1 and 100 characters long. Your current name is {} characters.",
            input.name.len()
        );
        return Err(ApiError::Validation(msg));
    }

    // Validate description length
    let desc_len = input.description.chars().count();
    if desc_len > 10000 {
        let msg = format!(
            "Description is too long ({} characters), max 10,000.",
            desc_len
        );
        return Err(ApiError::Validation(msg));
    }

    // Validate hidden_until is in the future
    let now = Utc::now().naive_utc();
    if let Some(hidden_at) = input.hidden_until {
        if hidden_at <= now {
            let msg = format!(
                "The 'hidden until' date ({}) has already passed or is the current moment. Please select a future date.",
                hidden_at
            );
            return Err(ApiError::Validation(msg));
        }
    }

    // Validate max_daily_frequency range
    if let Some(freq) = input.max_daily_frequency {
        if freq < 0.0 || freq > 100.0 {
            let msg = format!(
                "The 'max_daily_frequency must be between 0 and 100. You sent {}.",
                freq as i32
            );
            return Err(ApiError::Validation(msg));
        }
    }

    let opts = CreateRewardOptions {
        user_id: user.user_id,
        name: input.name,
        description: input.description,
        hidden_until: input.hidden_until,
        max_daily_frequency: input.max_daily_frequency,
    };

    let reward_row = app.database.create_reward(opts).await.map_err(|e| {
        error!("Database Error: {:?}", e);
        ApiError::Internal
    })?;

    Ok((
        StatusCode::CREATED,
        Json(RewardResponse {
            id: reward_row.id.to_string(),
            name: reward_row.name,
            description: reward_row.description,
            created_at: reward_row.created_at,
            updated_at: reward_row.updated_at,
            deleted_at: reward_row.deleted_at,
            hidden_until: reward_row.hidden_until,
            max_daily_frequency: reward_row.max_daily_frequency,
        }),
    ))
}
