use axum::{extract::State, http::StatusCode, response::IntoResponse, Extension, Json};
use chrono::NaiveDateTime;
use serde::{Deserialize, Serialize};
use tracing::error;

use crate::{
    database::{CreateTaskOptions, HabitDifficultyTier},
    router::{App, AuthenticatedUser},
};

use super::{habits::validate_habit_fields, ApiError};

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CreateTaskRequest {
    pub name: String,
    pub description: String,
    pub difficulty_tier: Option<HabitDifficultyTier>,
    pub duration_seconds: Option<i32>,
    pub commitment: Option<i16>,
    pub due_date: Option<NaiveDateTime>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TaskResponse {
    pub id: String,
    pub name: String,
    pub description: String,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub completed_at: Option<NaiveDateTime>,
    pub difficulty_tier: Option<HabitDifficultyTier>,
    pub duration_seconds: Option<i32>,
    pub commitment: Option<i16>,
    pub due_date: Option<NaiveDateTime>,
}

pub(crate) fn validate_task_fields(
    name: &str,
    description: &str,
    duration_seconds: Option<i32>,
    commitment: Option<i16>,
) -> Result<(), ApiError> {
    validate_habit_fields(name, description, None, duration_seconds, None, None)?;

    if let Some(commitment) = commitment {
        if !(1..=5).contains(&commitment) {
            return Err(ApiError::Validation(format!(
                "The 'commitment' must be between 1 and 5. You sent {}.",
                commitment
            )));
        }
    }

    Ok(())
}

pub async fn create_task(
    State(app): State<App>,
    Extension(user): Extension<AuthenticatedUser>,
    Json(input): Json<CreateTaskRequest>,
) -> Result<impl IntoResponse, ApiError> {
    validate_task_fields(
        &input.name,
        &input.description,
        input.duration_seconds,
        input.commitment,
    )?;

    let opts = CreateTaskOptions {
        user_id: user.user_id,
        name: input.name,
        description: input.description,
        difficulty_tier: input.difficulty_tier,
        duration_seconds: input.duration_seconds,
        commitment: input.commitment,
        due_date: input.due_date,
    };

    let task_row = app.database.create_task(opts).await.map_err(|e| {
        error!("Database Error: {:?}", e);
        ApiError::Internal
    })?;

    Ok((
        StatusCode::CREATED,
        Json(TaskResponse {
            id: task_row.id.to_string(),
            name: task_row.name,
            description: task_row.description,
            created_at: task_row.created_at,
            updated_at: task_row.updated_at,
            deleted_at: task_row.deleted_at,
            completed_at: task_row.completed_at,
            difficulty_tier: task_row.difficulty_tier,
            duration_seconds: task_row.duration_seconds,
            commitment: task_row.commitment,
            due_date: task_row.due_date,
        }),
    ))
}
