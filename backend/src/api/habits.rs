use axum::{extract::State, http::StatusCode, response::IntoResponse, Extension, Json};
use chrono::NaiveDateTime;
use serde::{Deserialize, Serialize};
use tracing::error;

use crate::{
    database::{CreateHabitOptions, HabitDifficultyTier},
    router::{App, AuthenticatedUser},
};

use super::ApiError;

pub(crate) const MIN_DAILY_FREQUENCY: f64 = 1.0 / 30.0;
pub(crate) const MAX_DAILY_FREQUENCY: f64 = 100.0;
pub(crate) const MIN_LOCKOUT_DURATION_SECONDS: i32 = 60;
pub(crate) const MAX_LOCKOUT_DURATION_SECONDS: i32 = 2_592_000;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CreateHabitRequest {
    pub name: String,
    pub description: String,
    pub min_daily_frequency: Option<f64>,
    pub difficulty_tier: Option<HabitDifficultyTier>,
    pub duration_seconds: Option<i32>,
    pub lockout_duration_seconds: Option<i32>,
    pub benefit: Option<i16>,
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
    pub difficulty_tier: Option<HabitDifficultyTier>,
    pub duration_seconds: Option<i32>,
    pub lockout_duration_seconds: Option<i32>,
    pub benefit: Option<i16>,
}

pub(crate) fn validate_habit_fields(
    name: &str,
    description: &str,
    min_daily_frequency: Option<f64>,
    duration_seconds: Option<i32>,
    lockout_duration_seconds: Option<i32>,
    benefit: Option<i16>,
) -> Result<(), ApiError> {
    let name_len = name.chars().count();
    if name_len > 100 || name_len < 1 {
        let msg = format!(
            "Please provide a name between 1 and 100 characters long. Your current name is {} characters.",
            name.len()
        );
        return Err(ApiError::Validation(msg));
    }

    let desc_len = description.chars().count();
    if desc_len > 10000 {
        let msg = format!(
            "Description is too long ({} characters), max 10,000.",
            desc_len
        );
        return Err(ApiError::Validation(msg));
    }

    if let Some(freq) = min_daily_frequency {
        if !(MIN_DAILY_FREQUENCY..=MAX_DAILY_FREQUENCY).contains(&freq) {
            let msg = format!(
                "The 'min_daily_frequency' must be between {} and {}. You sent {}.",
                MIN_DAILY_FREQUENCY, MAX_DAILY_FREQUENCY, freq
            );
            return Err(ApiError::Validation(msg));
        }
    }

    if let Some(duration_seconds) = duration_seconds {
        if !(1..=43_200).contains(&duration_seconds) {
            let msg = format!(
                "The 'duration_seconds' must be between 1 and 43200. You sent {}.",
                duration_seconds
            );
            return Err(ApiError::Validation(msg));
        }
    }

    if let Some(lockout_duration_seconds) = lockout_duration_seconds {
        if !(MIN_LOCKOUT_DURATION_SECONDS..=MAX_LOCKOUT_DURATION_SECONDS)
            .contains(&lockout_duration_seconds)
        {
            let msg = format!(
                "The 'lockout_duration_seconds' must be between {} and {}. You sent {}.",
                MIN_LOCKOUT_DURATION_SECONDS,
                MAX_LOCKOUT_DURATION_SECONDS,
                lockout_duration_seconds
            );
            return Err(ApiError::Validation(msg));
        }
    }

    if let Some(benefit) = benefit {
        if !(1..=5).contains(&benefit) {
            let msg = format!(
                "The 'benefit' must be between 1 and 5. You sent {}.",
                benefit
            );
            return Err(ApiError::Validation(msg));
        }
    }

    Ok(())
}

pub async fn create_habit(
    State(app): State<App>,
    Extension(user): Extension<AuthenticatedUser>,
    Json(input): Json<CreateHabitRequest>,
) -> Result<impl IntoResponse, ApiError> {
    validate_habit_fields(
        &input.name,
        &input.description,
        input.min_daily_frequency,
        input.duration_seconds,
        input.lockout_duration_seconds,
        input.benefit,
    )?;

    let opts = CreateHabitOptions {
        user_id: user.user_id,
        name: input.name,
        description: input.description,
        min_daily_frequency: input.min_daily_frequency,
        difficulty_tier: input.difficulty_tier,
        duration_seconds: input.duration_seconds,
        lockout_duration_seconds: input.lockout_duration_seconds,
        benefit: input.benefit,
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
            difficulty_tier: habit_row.difficulty_tier,
            duration_seconds: habit_row.duration_seconds,
            lockout_duration_seconds: habit_row.lockout_duration_seconds,
            benefit: habit_row.benefit,
        }),
    ))
}
