use axum::{extract::State, http::StatusCode, response::IntoResponse, Extension, Json};
use chrono::NaiveDateTime;
use serde::{Deserialize, Serialize};
use tracing::error;

use crate::{
    database::CreateHabitOptions,
    router::{App, AuthenticatedUser},
};

use super::ApiError;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CreateHabitRequest {
    pub name: String,
    pub description: String,
    pub min_daily_frequency: Option<f64>,
    pub difficulty_rank: Option<String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HabitResponse {
    pub id: String,
    pub name: String,
    pub description: String,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub min_daily_frequency: Option<f64>,
    pub difficulty_rank: Option<String>,
}

pub async fn create_habit(
    State(app): State<App>,
    Extension(user): Extension<AuthenticatedUser>,
    Json(input): Json<CreateHabitRequest>,
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

    // Validate min_daily_frequency range
    if let Some(freq) = input.min_daily_frequency {
        if freq < 0.0 || freq > 100.0 {
            let msg = format!(
                "The 'min_daily_frequency must be between 0 and 100. You sent {}.",
                freq as i32
            );
            return Err(ApiError::Validation(msg));
        }
    }

    let opts = CreateHabitOptions {
        user_id: user.user_id,
        name: input.name,
        description: input.description,
        min_daily_frequency: input.min_daily_frequency,
        difficulty_rank: input.difficulty_rank,
    };

    let habit_row = app.database.create_habit(opts).await.map_err(|e| {
        error!("Database Error: {:?}", e);
        ApiError::Internal
    })?;

    Ok((
        StatusCode::CREATED,
        Json(HabitResponse {
            id: habit_row.id.to_string(),
            name: habit_row.name,
            description: habit_row.description,
            created_at: habit_row.created_at,
            updated_at: habit_row.updated_at,
            deleted_at: habit_row.deleted_at,
            min_daily_frequency: habit_row.min_daily_frequency,
            difficulty_rank: habit_row.difficulty_rank,
        }),
    ))
}
