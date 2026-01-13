use axum::{extract::State, http::StatusCode, response::IntoResponse, Extension, Json};
use chrono::{NaiveDateTime, Utc};
use serde::{Deserialize, Serialize};
use tracing::error;

use crate::{
    database::CreateTaskOptions,
    router::{App, AuthenticatedUser},
};

use super::ApiError;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CreateTaskRequest {
    pub name: String,
    pub description: String,
    pub hidden_until: Option<NaiveDateTime>,
    pub due_by: Option<NaiveDateTime>,
    pub min_daily_frequency: Option<f64>,
    pub difficulty_rank: Option<String>,
    pub habit: bool,
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
    pub hidden_until: Option<NaiveDateTime>,
    pub due_by: Option<NaiveDateTime>,
    pub min_daily_frequency: Option<f64>,
    pub difficulty_rank: Option<String>,
    pub completed_at: Option<NaiveDateTime>,
    pub habit: bool,
}

pub async fn create_task(
    State(app): State<App>,
    Extension(user): Extension<AuthenticatedUser>,
    Json(input): Json<CreateTaskRequest>,
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

    // Validate due_by is in the future
    if let Some(due_at) = input.due_by {
        if due_at <= now {
            let msg = format!(
                "The 'due_by' date ({}) has already passed or is the current moment. Please select a future date.",
                due_at
            );
            return Err(ApiError::Validation(msg));
        }
    }

    // Habit validation: non-habits cannot have min_daily_frequency
    if !input.habit && input.min_daily_frequency.is_some() {
        let msg = "Non-habit tasks cannot have 'min_daily_frequency'. Either set 'habit' to true or remove 'min_daily_frequency'.".to_string();
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

    let opts = CreateTaskOptions {
        user_id: user.user_id,
        name: input.name,
        description: input.description,
        hidden_until: input.hidden_until,
        due_by: input.due_by,
        min_daily_frequency: input.min_daily_frequency,
        difficulty_rank: input.difficulty_rank,
        habit: input.habit,
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
            hidden_until: task_row.hidden_until,
            due_by: task_row.due_by,
            min_daily_frequency: task_row.min_daily_frequency,
            difficulty_rank: task_row.difficulty_rank,
            completed_at: task_row.completed_at,
            habit: task_row.habit,
        }),
    ))
}
