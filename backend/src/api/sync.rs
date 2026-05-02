use axum::{
    extract::{Query, State},
    response::IntoResponse,
    Extension, Json,
};
use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine as _};
use chrono::{NaiveDateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::{Postgres, Transaction};
use std::collections::BTreeSet;
use tracing::error;
use uuid::Uuid;

use crate::{
    database::{self, Database, HabitDifficultyTier, RewardDamageTier},
    router::{App, AuthenticatedUser},
};

use super::habits::validate_habit_fields;
use super::rewards::validate_reward_fields;
use super::tasks::validate_task_fields;
use super::ApiError;

// ============================================================================
// Request/Response Types
// ============================================================================

#[derive(Deserialize)]
pub struct SyncQueryParams {
    pub since: Option<NaiveDateTime>,
    pub cursor: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct SyncCursor {
    upper_bound_tx_id: i64,
    in_progress_tx_ids: Vec<i64>,
}

#[derive(Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct SyncPushRequest {
    pub tasks: Option<Vec<SyncTaskInput>>,
    pub habits: Option<Vec<SyncHabitInput>>,
    pub trades: Option<Vec<SyncTradeInput>>,
    pub tags: Option<Vec<SyncTagInput>>,
    pub task_tags: Option<Vec<SyncTaskTagInput>>,
    pub task_task_dependencies: Option<Vec<SyncTaskTaskDependencyInput>>,
    pub task_habit_dependencies: Option<Vec<SyncTaskHabitDependencyInput>>,
    pub habit_tags: Option<Vec<SyncHabitTagInput>>,
    pub rewards: Option<Vec<SyncRewardInput>>,
    pub reward_tags: Option<Vec<SyncRewardTagInput>>,
    pub general_difficulty: Option<f64>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncTaskInput {
    pub id: String,
    pub name: String,
    pub description: String,
    pub created_at: NaiveDateTime,
    #[allow(dead_code)]
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub completed_at: Option<NaiveDateTime>,
    pub difficulty_tier: Option<HabitDifficultyTier>,
    pub duration_seconds: Option<i32>,
    pub skip_consequence: Option<i16>,
    pub due_date: Option<NaiveDateTime>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncHabitInput {
    pub id: String,
    pub name: String,
    pub description: String,
    pub created_at: NaiveDateTime,
    #[allow(dead_code)]
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub min_daily_frequency: Option<f64>,
    pub difficulty_tier: Option<HabitDifficultyTier>,
    pub duration_seconds: Option<i32>,
    pub lockout_duration_seconds: Option<i32>,
    pub skip_consequence: Option<i16>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncTradeInput {
    pub id: String,
    pub task_id: Option<String>,
    pub habit_id: Option<String>,
    pub reward_id: Option<String>,
    pub source_name: Option<String>,
    pub amount: i32,
    pub created_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub refunds_trade_id: Option<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncTagInput {
    pub id: String,
    pub name: String,
    pub color_hex: String,
    pub created_at: NaiveDateTime,
    #[allow(dead_code)]
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncTaskTagInput {
    pub task_id: String,
    pub tag_id: String,
    pub created_at: NaiveDateTime,
    #[allow(dead_code)]
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncTaskTaskDependencyInput {
    pub task_id: String,
    pub depends_on_task_id: String,
    pub created_at: NaiveDateTime,
    #[allow(dead_code)]
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncTaskHabitDependencyInput {
    pub task_id: String,
    pub habit_id: String,
    pub required_completions: i32,
    pub baseline_completion_count: i32,
    pub created_at: NaiveDateTime,
    #[allow(dead_code)]
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncHabitTagInput {
    pub habit_id: String,
    pub tag_id: String,
    pub created_at: NaiveDateTime,
    #[allow(dead_code)]
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
    #[allow(dead_code)]
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub max_daily_frequency: Option<f64>,
    pub damage_tier: Option<RewardDamageTier>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncRewardTagInput {
    pub reward_id: String,
    pub tag_id: String,
    pub created_at: NaiveDateTime,
    #[allow(dead_code)]
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncResponse {
    pub tasks: Vec<TaskOutput>,
    pub habits: Vec<HabitOutput>,
    pub trades: Vec<TradeOutput>,
    pub tags: Vec<TagOutput>,
    pub task_tags: Vec<TaskTagOutput>,
    pub task_task_dependencies: Vec<TaskTaskDependencyOutput>,
    pub task_habit_dependencies: Vec<TaskHabitDependencyOutput>,
    pub habit_tags: Vec<HabitTagOutput>,
    pub rewards: Vec<RewardOutput>,
    pub reward_tags: Vec<RewardTagOutput>,
    pub balance: BalanceOutput,
    pub server_cursor: String,
    pub server_time: NaiveDateTime,
    pub email: Option<String>,
    pub is_premium: bool,
    pub general_difficulty: f64,
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
    pub difficulty_tier: Option<HabitDifficultyTier>,
    pub duration_seconds: Option<i32>,
    pub lockout_duration_seconds: Option<i32>,
    pub skip_consequence: Option<i16>,
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
    pub completed_at: Option<NaiveDateTime>,
    pub difficulty_tier: Option<HabitDifficultyTier>,
    pub duration_seconds: Option<i32>,
    pub skip_consequence: Option<i16>,
    pub due_date: Option<NaiveDateTime>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TradeOutput {
    pub id: String,
    pub task_id: Option<String>,
    pub habit_id: Option<String>,
    pub reward_id: Option<String>,
    pub source_name: Option<String>,
    pub amount: i32,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub refunds_trade_id: Option<String>,
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
pub struct TaskTagOutput {
    pub task_id: String,
    pub tag_id: String,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TaskTaskDependencyOutput {
    pub task_id: String,
    pub depends_on_task_id: String,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TaskHabitDependencyOutput {
    pub task_id: String,
    pub habit_id: String,
    pub required_completions: i32,
    pub baseline_completion_count: i32,
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
    pub damage_tier: Option<RewardDamageTier>,
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

fn task_output_from_row(row: database::TaskRow) -> TaskOutput {
    TaskOutput {
        id: row.id.to_string(),
        name: row.name,
        description: row.description,
        created_at: row.created_at,
        updated_at: row.updated_at,
        deleted_at: row.deleted_at,
        completed_at: row.completed_at,
        difficulty_tier: row.difficulty_tier,
        duration_seconds: row.duration_seconds,
        skip_consequence: row.skip_consequence,
        due_date: row.due_date,
    }
}

fn trade_output_from_row(row: database::TradeRow) -> TradeOutput {
    TradeOutput {
        id: row.id.to_string(),
        task_id: row.task_id.map(|id| id.to_string()),
        habit_id: row.habit_id.map(|id| id.to_string()),
        reward_id: row.reward_id.map(|id| id.to_string()),
        source_name: row.source_name,
        amount: row.amount,
        created_at: row.created_at,
        updated_at: row.updated_at,
        deleted_at: row.deleted_at,
        refunds_trade_id: row.refunds_trade_id.map(|id| id.to_string()),
    }
}

fn upsert_task_task_dependency_output(
    outputs: &mut Vec<TaskTaskDependencyOutput>,
    row: database::TaskTaskDependencyRow,
) {
    outputs.retain(|existing| {
        existing.task_id != row.task_id.to_string()
            || existing.depends_on_task_id != row.depends_on_task_id.to_string()
    });
    outputs.push(TaskTaskDependencyOutput {
        task_id: row.task_id.to_string(),
        depends_on_task_id: row.depends_on_task_id.to_string(),
        created_at: row.created_at,
        updated_at: row.updated_at,
        deleted_at: row.deleted_at,
    });
}

fn upsert_task_habit_dependency_output(
    outputs: &mut Vec<TaskHabitDependencyOutput>,
    row: database::TaskHabitDependencyRow,
) {
    outputs.retain(|existing| {
        existing.task_id != row.task_id.to_string() || existing.habit_id != row.habit_id.to_string()
    });
    outputs.push(TaskHabitDependencyOutput {
        task_id: row.task_id.to_string(),
        habit_id: row.habit_id.to_string(),
        required_completions: row.required_completions,
        baseline_completion_count: row.baseline_completion_count,
        created_at: row.created_at,
        updated_at: row.updated_at,
        deleted_at: row.deleted_at,
    });
}

fn map_trade_upsert_error(error: sqlx::Error, refunds_trade_id: Option<Uuid>) -> ApiError {
    match error {
        sqlx::Error::RowNotFound => {
            if refunds_trade_id.is_some() {
                ApiError::Validation(
                    "Refund trades must reference an existing trade owned by the current user."
                        .to_string(),
                )
            } else {
                ApiError::Validation(
                    "Trade references an invalid task, habit, or reward.".to_string(),
                )
            }
        }
        sqlx::Error::Protocol(message) => ApiError::Validation(message),
        other => {
            error!("Database Error upserting trade: {:?}", other);
            ApiError::Internal
        }
    }
}

fn profile_is_entitled(profile_row: &database::UserProfileRow) -> bool {
    match profile_row.subscription_status.as_str() {
        "active" | "grace_period" => true,
        "billing_retry" | "expired" | "revoked" | "none" => false,
        _ => false,
    }
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
    let requested_cursor = params
        .cursor
        .as_deref()
        .map(SyncCursor::decode)
        .transpose()
        .map_err(|_| ApiError::Validation("Invalid sync cursor".to_string()))?;

    let mut tx = app.database.begin_transaction().await.map_err(|e| {
        error!("Failed to begin snapshot transaction: {:?}", e);
        ApiError::Internal
    })?;

    sqlx::query("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY")
        .execute(&mut *tx)
        .await
        .map_err(|e| {
            error!("Failed to configure snapshot transaction: {:?}", e);
            ApiError::Internal
        })?;

    let response_cursor = load_snapshot_cursor(&mut tx).await.map_err(|e| {
        error!("Failed to capture sync snapshot cursor: {:?}", e);
        ApiError::Internal
    })?;

    let habit_rows = load_habits_for_sync(
        &mut tx,
        user.user_id,
        params.since,
        requested_cursor.as_ref(),
    )
    .await
    .map_err(|e| {
        error!("Database Error: {:?}", e);
        ApiError::Internal
    })?;

    let task_rows = load_tasks_for_sync(
        &mut tx,
        user.user_id,
        params.since,
        requested_cursor.as_ref(),
    )
    .await
    .map_err(|e| {
        error!("Database Error: {:?}", e);
        ApiError::Internal
    })?;

    let trade_rows = load_trades_for_sync(
        &mut tx,
        user.user_id,
        params.since,
        requested_cursor.as_ref(),
    )
    .await
    .map_err(|e| {
        error!("Database Error: {:?}", e);
        ApiError::Internal
    })?;

    let trade_balance = load_balance_for_sync(&mut tx, user.user_id)
        .await
        .map_err(|e| {
            error!("Database Error: {:?}", e);
            ApiError::Internal
        })?;

    let profile_row = load_profile_for_sync(&mut tx, user.user_id)
        .await
        .map_err(|e| {
            error!("Database Error: {:?}", e);
            ApiError::Internal
        })?;

    let tag_rows = load_tags_for_sync(
        &mut tx,
        user.user_id,
        params.since,
        requested_cursor.as_ref(),
    )
    .await
    .map_err(|e| {
        error!("Database Error: {:?}", e);
        ApiError::Internal
    })?;

    let task_tag_rows = load_task_tags_for_sync(
        &mut tx,
        user.user_id,
        params.since,
        requested_cursor.as_ref(),
    )
    .await
    .map_err(|e| {
        error!("Database Error: {:?}", e);
        ApiError::Internal
    })?;

    let task_task_dependency_rows = load_task_task_dependencies_for_sync(
        &mut tx,
        user.user_id,
        params.since,
        requested_cursor.as_ref(),
    )
    .await
    .map_err(|e| {
        error!("Database Error: {:?}", e);
        ApiError::Internal
    })?;

    let task_habit_dependency_rows = load_task_habit_dependencies_for_sync(
        &mut tx,
        user.user_id,
        params.since,
        requested_cursor.as_ref(),
    )
    .await
    .map_err(|e| {
        error!("Database Error: {:?}", e);
        ApiError::Internal
    })?;

    let habit_tag_rows = load_habit_tags_for_sync(
        &mut tx,
        user.user_id,
        params.since,
        requested_cursor.as_ref(),
    )
    .await
    .map_err(|e| {
        error!("Database Error: {:?}", e);
        ApiError::Internal
    })?;

    let reward_rows = load_rewards_for_sync(
        &mut tx,
        user.user_id,
        params.since,
        requested_cursor.as_ref(),
    )
    .await
    .map_err(|e| {
        error!("Database Error: {:?}", e);
        ApiError::Internal
    })?;

    let reward_tag_rows = load_reward_tags_for_sync(
        &mut tx,
        user.user_id,
        params.since,
        requested_cursor.as_ref(),
    )
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
            difficulty_tier: row.difficulty_tier,
            duration_seconds: row.duration_seconds,
            lockout_duration_seconds: row.lockout_duration_seconds,
            skip_consequence: row.skip_consequence,
        })
        .collect();

    let tasks: Vec<TaskOutput> = task_rows.into_iter().map(task_output_from_row).collect();

    let trades: Vec<TradeOutput> = trade_rows.into_iter().map(trade_output_from_row).collect();

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

    let task_tags: Vec<TaskTagOutput> = task_tag_rows
        .into_iter()
        .map(|row| TaskTagOutput {
            task_id: row.task_id.to_string(),
            tag_id: row.tag_id.to_string(),
            created_at: row.created_at,
            updated_at: row.updated_at,
            deleted_at: row.deleted_at,
        })
        .collect();

    let task_task_dependencies: Vec<TaskTaskDependencyOutput> = task_task_dependency_rows
        .into_iter()
        .map(|row| TaskTaskDependencyOutput {
            task_id: row.task_id.to_string(),
            depends_on_task_id: row.depends_on_task_id.to_string(),
            created_at: row.created_at,
            updated_at: row.updated_at,
            deleted_at: row.deleted_at,
        })
        .collect();

    let task_habit_dependencies: Vec<TaskHabitDependencyOutput> = task_habit_dependency_rows
        .into_iter()
        .map(|row| TaskHabitDependencyOutput {
            task_id: row.task_id.to_string(),
            habit_id: row.habit_id.to_string(),
            required_completions: row.required_completions,
            baseline_completion_count: row.baseline_completion_count,
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
            max_daily_frequency: row.max_daily_frequency,
            damage_tier: row.damage_tier,
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
    let is_premium = profile_is_entitled(&profile_row);
    let server_cursor = response_cursor.encode().map_err(|e| {
        error!("Failed to encode sync cursor: {:?}", e);
        ApiError::Internal
    })?;

    tx.commit().await.map_err(|e| {
        error!("Failed to commit snapshot transaction: {:?}", e);
        ApiError::Internal
    })?;

    Ok(Json(SyncResponse {
        tasks,
        habits,
        trades,
        tags,
        task_tags,
        task_task_dependencies,
        task_habit_dependencies,
        habit_tags,
        rewards,
        reward_tags,
        balance: BalanceOutput {
            tofu_balance: trade_balance,
        },
        server_cursor,
        server_time,
        email: profile_row.email,
        is_premium,
        general_difficulty: profile_row.general_difficulty,
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
    let mut result_tasks = Vec::new();
    let mut result_trades = Vec::new();
    let mut result_tags = Vec::new();
    let mut result_task_tags = Vec::new();
    let mut result_task_task_dependencies = Vec::new();
    let mut result_task_habit_dependencies = Vec::new();
    let mut result_habit_tags = Vec::new();
    let mut result_rewards = Vec::new();
    let mut result_reward_tags = Vec::new();
    let mut completed_task_ids = Vec::new();
    let mut deleted_tasks = Vec::new();
    let mut deleted_habit_ids = Vec::new();
    let mut touched_task_ids = BTreeSet::new();

    // Process habits first (trades may reference these)
    if let Some(habits) = input.habits {
        for habit_input in habits {
            // Validate habit ID is a valid UUID
            let habit_id = habit_input.id.parse::<Uuid>().map_err(|_| {
                ApiError::Validation(format!("Invalid habit id format: {}", habit_input.id))
            })?;

            validate_habit_fields(
                &habit_input.name,
                &habit_input.description,
                habit_input.min_daily_frequency,
                habit_input.duration_seconds,
                habit_input.lockout_duration_seconds,
                habit_input.skip_consequence,
            )?;

            let upsert_opts = database::UpsertHabitOptions {
                id: habit_id,
                name: habit_input.name,
                description: habit_input.description,
                created_at: habit_input.created_at,
                deleted_at: habit_input.deleted_at,
                min_daily_frequency: habit_input.min_daily_frequency,
                difficulty_tier: habit_input.difficulty_tier,
                duration_seconds: habit_input.duration_seconds,
                lockout_duration_seconds: habit_input.lockout_duration_seconds,
                skip_consequence: habit_input.skip_consequence,
            };

            if habit_input.deleted_at.is_some() {
                deleted_habit_ids.push(habit_id);
            }

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
                difficulty_tier: habit_row.difficulty_tier,
                duration_seconds: habit_row.duration_seconds,
                lockout_duration_seconds: habit_row.lockout_duration_seconds,
                skip_consequence: habit_row.skip_consequence,
            });
        }
    }

    // Process tasks second (trades may reference these)
    if let Some(tasks) = input.tasks {
        for task_input in tasks {
            let task_id = task_input.id.parse::<Uuid>().map_err(|_| {
                ApiError::Validation(format!("Invalid task id format: {}", task_input.id))
            })?;
            touched_task_ids.insert(task_id);

            validate_task_fields(
                &task_input.name,
                &task_input.description,
                task_input.duration_seconds,
                task_input.skip_consequence,
            )?;

            let upsert_opts = database::UpsertTaskOptions {
                id: task_id,
                name: task_input.name,
                description: task_input.description,
                created_at: task_input.created_at,
                deleted_at: task_input.deleted_at,
                difficulty_tier: task_input.difficulty_tier,
                duration_seconds: task_input.duration_seconds,
                skip_consequence: task_input.skip_consequence,
                due_date: task_input.due_date,
            };

            if task_input.completed_at.is_some() && task_input.deleted_at.is_none() {
                completed_task_ids.push(task_id);
            }

            if let Some(deleted_at) = task_input.deleted_at {
                deleted_tasks.push((task_id, deleted_at));
            }

            let task_row = Database::upsert_task_tx(&mut tx, user.user_id, &upsert_opts)
                .await
                .map_err(|e| {
                    error!("Database Error upserting task: {:?}", e);
                    ApiError::Internal
                })?;

            result_tasks.push(task_output_from_row(task_row));
        }
    }

    // Process task dependencies third (they reference tasks and habits created above)
    if let Some(task_task_dependencies) = input.task_task_dependencies {
        for dependency_input in task_task_dependencies {
            let task_id = dependency_input.task_id.parse::<Uuid>().map_err(|_| {
                ApiError::Validation(format!(
                    "Invalid task_id format: {}",
                    dependency_input.task_id
                ))
            })?;

            let depends_on_task_id = dependency_input
                .depends_on_task_id
                .parse::<Uuid>()
                .map_err(|_| {
                    ApiError::Validation(format!(
                        "Invalid depends_on_task_id format: {}",
                        dependency_input.depends_on_task_id
                    ))
                })?;

            let upsert_opts = database::UpsertTaskTaskDependencyOptions {
                task_id,
                depends_on_task_id,
                created_at: dependency_input.created_at,
                deleted_at: dependency_input.deleted_at,
            };

            let dependency_row =
                Database::upsert_task_task_dependency_tx(&mut tx, user.user_id, &upsert_opts)
                    .await
                    .map_err(|e| {
                        error!("Database Error upserting task-task dependency: {:?}", e);
                        ApiError::Validation(format!(
                    "Invalid task dependency reference for task_id: {}, depends_on_task_id: {}",
                    task_id, depends_on_task_id
                ))
                    })?;

            upsert_task_task_dependency_output(&mut result_task_task_dependencies, dependency_row);
        }
    }

    if let Some(task_habit_dependencies) = input.task_habit_dependencies {
        for dependency_input in task_habit_dependencies {
            if dependency_input.required_completions <= 0 {
                return Err(ApiError::Validation(
                    "Habit dependencies must require at least one completion.".to_string(),
                ));
            }

            if dependency_input.baseline_completion_count < 0 {
                return Err(ApiError::Validation(
                    "Habit dependency baseline completion counts cannot be negative.".to_string(),
                ));
            }

            let task_id = dependency_input.task_id.parse::<Uuid>().map_err(|_| {
                ApiError::Validation(format!(
                    "Invalid task_id format: {}",
                    dependency_input.task_id
                ))
            })?;

            let habit_id = dependency_input.habit_id.parse::<Uuid>().map_err(|_| {
                ApiError::Validation(format!(
                    "Invalid habit_id format: {}",
                    dependency_input.habit_id
                ))
            })?;

            let upsert_opts = database::UpsertTaskHabitDependencyOptions {
                task_id,
                habit_id,
                required_completions: dependency_input.required_completions,
                baseline_completion_count: dependency_input.baseline_completion_count,
                created_at: dependency_input.created_at,
                deleted_at: dependency_input.deleted_at,
            };

            let dependency_row =
                Database::upsert_task_habit_dependency_tx(&mut tx, user.user_id, &upsert_opts)
                    .await
                    .map_err(|e| {
                        error!("Database Error upserting task-habit dependency: {:?}", e);
                        ApiError::Validation(format!(
                            "Invalid task or habit reference for task_id: {}, habit_id: {}",
                            task_id, habit_id
                        ))
                    })?;

            upsert_task_habit_dependency_output(
                &mut result_task_habit_dependencies,
                dependency_row,
            );
        }
    }

    // Process rewards fourth (trades may reference these)
    if let Some(rewards) = input.rewards {
        for reward_input in rewards {
            // Validate reward ID is a valid UUID
            let reward_id = reward_input.id.parse::<Uuid>().map_err(|_| {
                ApiError::Validation(format!("Invalid reward id format: {}", reward_input.id))
            })?;

            validate_reward_fields(
                &reward_input.name,
                &reward_input.description,
                reward_input.max_daily_frequency,
            )?;

            let upsert_opts = database::UpsertRewardOptions {
                id: reward_id,
                name: reward_input.name,
                description: reward_input.description,
                created_at: reward_input.created_at,
                deleted_at: reward_input.deleted_at,
                max_daily_frequency: reward_input.max_daily_frequency,
                damage_tier: reward_input.damage_tier,
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
                max_daily_frequency: reward_row.max_daily_frequency,
                damage_tier: reward_row.damage_tier,
            });
        }
    }

    // Process trades fifth (they may reference tasks, habits, or rewards created above)
    if let Some(trades) = input.trades {
        for trade_input in trades {
            // Validate trade ID is a valid UUID
            let trade_id = trade_input.id.parse::<Uuid>().map_err(|_| {
                ApiError::Validation(format!("Invalid trade id format: {}", trade_input.id))
            })?;

            let task_id = if let Some(task_id_str) = &trade_input.task_id {
                let parsed = task_id_str.parse::<Uuid>().map_err(|_| {
                    ApiError::Validation(format!("Invalid task_id format: {}", task_id_str))
                })?;
                touched_task_ids.insert(parsed);
                Some(parsed)
            } else {
                None
            };

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

            let source_count = usize::from(task_id.is_some())
                + usize::from(habit_id.is_some())
                + usize::from(reward_id.is_some());
            if source_count != 1 {
                let msg =
                    "Trade must have exactly one of task_id, habit_id, or reward_id".to_string();
                return Err(ApiError::Validation(msg));
            }

            let upsert_opts = database::UpsertTradeOptions {
                id: trade_id,
                task_id,
                habit_id,
                reward_id,
                source_name: trade_input.source_name,
                amount: trade_input.amount,
                created_at: trade_input.created_at,
                deleted_at: trade_input.deleted_at,
                refunds_trade_id: trade_input
                    .refunds_trade_id
                    .as_ref()
                    .map(|id| {
                        id.parse::<Uuid>().map_err(|_| {
                            ApiError::Validation(format!("Invalid refunds_trade_id format: {}", id))
                        })
                    })
                    .transpose()?,
            };

            if let Some(task_id) = upsert_opts.task_id {
                if upsert_opts.refunds_trade_id.is_none() && upsert_opts.deleted_at.is_none() {
                    completed_task_ids.push(task_id);
                }
            }

            let trade_row = Database::upsert_trade_tx(&mut tx, user.user_id, &upsert_opts)
                .await
                .map_err(|e| map_trade_upsert_error(e, upsert_opts.refunds_trade_id))?;

            result_trades.push(trade_output_from_row(trade_row));
        }
    }

    // Process tags sixth (entity-tag links may reference these)
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

    // Process task_tags seventh (they reference tasks and tags)
    if let Some(task_tags) = input.task_tags {
        for task_tag_input in task_tags {
            let task_id = task_tag_input.task_id.parse::<Uuid>().map_err(|_| {
                ApiError::Validation(format!(
                    "Invalid task_id format: {}",
                    task_tag_input.task_id
                ))
            })?;

            let tag_id = task_tag_input.tag_id.parse::<Uuid>().map_err(|_| {
                ApiError::Validation(format!("Invalid tag_id format: {}", task_tag_input.tag_id))
            })?;

            let upsert_opts = database::UpsertTaskTagOptions {
                task_id,
                tag_id,
                created_at: task_tag_input.created_at,
                deleted_at: task_tag_input.deleted_at,
            };

            let task_tag_row = Database::upsert_task_tag_tx(&mut tx, user.user_id, &upsert_opts)
                .await
                .map_err(|e| {
                    error!("Database Error upserting task_tag: {:?}", e);
                    ApiError::Validation(format!(
                        "Invalid task or tag reference for task_id: {}, tag_id: {}",
                        task_id, tag_id
                    ))
                })?;

            result_task_tags.push(TaskTagOutput {
                task_id: task_tag_row.task_id.to_string(),
                tag_id: task_tag_row.tag_id.to_string(),
                created_at: task_tag_row.created_at,
                updated_at: task_tag_row.updated_at,
                deleted_at: task_tag_row.deleted_at,
            });
        }
    }

    // Process habit_tags eighth (they reference habits and tags)
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
                ApiError::Validation(format!("Invalid tag_id format: {}", habit_tag_input.tag_id))
            })?;

            let upsert_opts = database::UpsertHabitTagOptions {
                habit_id,
                tag_id,
                created_at: habit_tag_input.created_at,
                deleted_at: habit_tag_input.deleted_at,
            };

            let habit_tag_row = Database::upsert_habit_tag_tx(&mut tx, user.user_id, &upsert_opts)
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

    // Process reward_tags ninth (they reference rewards and tags)
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

    // Update general_difficulty if provided
    if let Some(gd) = input.general_difficulty {
        if gd <= 0.0 || gd >= 1000.0 {
            return Err(ApiError::Validation(
                "general_difficulty must be greater than 0 and less than 1000".to_string(),
            ));
        }
        Database::update_general_difficulty_tx(&mut tx, user.user_id, gd)
            .await
            .map_err(|e| {
                error!("Database Error updating general_difficulty: {:?}", e);
                ApiError::Internal
            })?;
    }

    let has_cycles = Database::user_has_task_dependency_cycles_tx(&mut tx, user.user_id)
        .await
        .map_err(|e| {
            error!("Database Error validating task dependency cycles: {:?}", e);
            ApiError::Internal
        })?;
    if has_cycles {
        return Err(ApiError::Validation(
            "Task dependencies cannot contain cycles.".to_string(),
        ));
    }

    for (task_id, deleted_at) in deleted_tasks {
        let deleted_task_dependencies = Database::soft_delete_task_task_dependencies_for_task_tx(
            &mut tx,
            user.user_id,
            task_id,
            deleted_at,
        )
        .await
        .map_err(|e| {
            error!(
                "Database Error deleting task-task dependencies for deleted task: {:?}",
                e
            );
            ApiError::Internal
        })?;

        for dependency_row in deleted_task_dependencies {
            upsert_task_task_dependency_output(&mut result_task_task_dependencies, dependency_row);
        }

        let deleted_habit_dependencies = Database::soft_delete_task_habit_dependencies_for_task_tx(
            &mut tx,
            user.user_id,
            task_id,
            deleted_at,
        )
        .await
        .map_err(|e| {
            error!(
                "Database Error deleting task-habit dependencies for deleted task: {:?}",
                e
            );
            ApiError::Internal
        })?;

        for dependency_row in deleted_habit_dependencies {
            upsert_task_habit_dependency_output(
                &mut result_task_habit_dependencies,
                dependency_row,
            );
        }
    }

    for habit_id in deleted_habit_ids {
        let has_dependents =
            Database::habit_has_active_dependents_tx(&mut tx, user.user_id, habit_id)
                .await
                .map_err(|e| {
                    error!("Database Error validating habit dependents: {:?}", e);
                    ApiError::Internal
                })?;

        if has_dependents {
            return Err(ApiError::Validation(
                "This item cannot be deleted while active tasks still depend on it.".to_string(),
            ));
        }
    }

    for task_id in completed_task_ids {
        let has_incomplete_dependencies =
            Database::task_has_incomplete_dependencies_tx(&mut tx, user.user_id, task_id)
                .await
                .map_err(|e| {
                    error!(
                        "Database Error validating task completion dependencies: {:?}",
                        e
                    );
                    ApiError::Internal
                })?;

        if has_incomplete_dependencies {
            return Err(ApiError::Validation(
                "Task dependencies must be complete before this task can be completed.".to_string(),
            ));
        }
    }

    if !touched_task_ids.is_empty() {
        result_tasks = load_tasks_by_ids_for_sync(
            &mut tx,
            user.user_id,
            touched_task_ids.into_iter().collect(),
        )
        .await
        .map_err(|e| {
            error!(
                "Database Error loading affected tasks for push response: {:?}",
                e
            );
            ApiError::Internal
        })?
        .into_iter()
        .map(task_output_from_row)
        .collect();
    }

    // Return a balance derived from the just-written trade history instead of
    // relying on a separate cached column.
    let new_balance = Database::calculate_balance_from_trades_tx(&mut tx, user.user_id)
        .await
        .map_err(|e| {
            error!("Database Error calculating balance from trades: {:?}", e);
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

    let mut snapshot_tx = app.database.begin_transaction().await.map_err(|e| {
        error!("Failed to begin push snapshot transaction: {:?}", e);
        ApiError::Internal
    })?;

    sqlx::query("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY")
        .execute(&mut *snapshot_tx)
        .await
        .map_err(|e| {
            error!("Failed to configure push snapshot transaction: {:?}", e);
            ApiError::Internal
        })?;

    let server_cursor = load_snapshot_cursor(&mut snapshot_tx)
        .await
        .and_then(|cursor| {
            cursor
                .encode()
                .map_err(|e| sqlx::Error::Protocol(e.to_string()))
        })
        .map_err(|e| {
            error!("Failed to capture push sync cursor: {:?}", e);
            ApiError::Internal
        })?;

    snapshot_tx.commit().await.map_err(|e| {
        error!("Failed to commit push snapshot transaction: {:?}", e);
        ApiError::Internal
    })?;

    let server_time = Utc::now().naive_utc();
    let is_premium = profile_is_entitled(&profile_row);

    Ok(Json(SyncResponse {
        tasks: result_tasks,
        habits: result_habits,
        trades: result_trades,
        tags: result_tags,
        task_tags: result_task_tags,
        task_task_dependencies: result_task_task_dependencies,
        task_habit_dependencies: result_task_habit_dependencies,
        habit_tags: result_habit_tags,
        rewards: result_rewards,
        reward_tags: result_reward_tags,
        balance: BalanceOutput {
            tofu_balance: new_balance,
        },
        server_cursor,
        server_time,
        email: profile_row.email,
        is_premium,
        general_difficulty: profile_row.general_difficulty,
    }))
}

impl SyncCursor {
    fn decode(raw: &str) -> Result<Self, String> {
        let bytes = URL_SAFE_NO_PAD
            .decode(raw)
            .map_err(|error| error.to_string())?;
        serde_json::from_slice(&bytes).map_err(|error| error.to_string())
    }

    fn encode(&self) -> Result<String, String> {
        let json = serde_json::to_vec(self).map_err(|error| error.to_string())?;
        Ok(URL_SAFE_NO_PAD.encode(json))
    }
}

async fn load_snapshot_cursor(
    tx: &mut Transaction<'_, Postgres>,
) -> Result<SyncCursor, sqlx::Error> {
    let (snapshot,): (String,) = sqlx::query_as("SELECT txid_current_snapshot()::text")
        .fetch_one(&mut **tx)
        .await?;

    let parts: Vec<&str> = snapshot.split(':').collect();
    if parts.len() != 3 {
        return Err(sqlx::Error::Protocol(
            format!("Unexpected txid snapshot format: {snapshot}").into(),
        ));
    }

    let upper_bound_tx_id = parts[1]
        .parse::<i64>()
        .map_err(|error| sqlx::Error::Protocol(error.to_string().into()))?;
    let in_progress_tx_ids = if parts[2].is_empty() {
        Vec::new()
    } else {
        parts[2]
            .split(',')
            .map(|part| part.parse::<i64>())
            .collect::<Result<Vec<_>, _>>()
            .map_err(|error| sqlx::Error::Protocol(error.to_string().into()))?
    };

    Ok(SyncCursor {
        upper_bound_tx_id,
        in_progress_tx_ids,
    })
}

async fn load_tasks_for_sync(
    tx: &mut Transaction<'_, Postgres>,
    user_id: Uuid,
    since: Option<NaiveDateTime>,
    cursor: Option<&SyncCursor>,
) -> Result<Vec<database::TaskRow>, sqlx::Error> {
    let select_columns = database::task_select_columns("tasks", "tasks.user_id");
    match cursor {
        Some(cursor) => {
            let query = format!(
                "SELECT {}
                 FROM tasks
                 WHERE user_id = $1
                   AND ((xmin::text)::bigint >= $2 OR (xmin::text)::bigint = ANY($3))
                 ORDER BY updated_at ASC",
                select_columns
            );
            sqlx::query_as(&query)
                .bind(user_id)
                .bind(cursor.upper_bound_tx_id)
                .bind(&cursor.in_progress_tx_ids)
                .fetch_all(&mut **tx)
                .await
        }
        None => match since {
            Some(since_time) => {
                let query = format!(
                    "SELECT {}
                     FROM tasks
                     WHERE user_id = $1 AND updated_at > $2
                     ORDER BY updated_at ASC",
                    select_columns
                );
                sqlx::query_as(&query)
                    .bind(user_id)
                    .bind(since_time)
                    .fetch_all(&mut **tx)
                    .await
            }
            None => {
                let query = format!(
                    "SELECT {}
                     FROM tasks
                     WHERE user_id = $1
                     ORDER BY updated_at ASC",
                    select_columns
                );
                sqlx::query_as(&query)
                    .bind(user_id)
                    .fetch_all(&mut **tx)
                    .await
            }
        },
    }
}

async fn load_tasks_by_ids_for_sync(
    tx: &mut Transaction<'_, Postgres>,
    user_id: Uuid,
    task_ids: Vec<Uuid>,
) -> Result<Vec<database::TaskRow>, sqlx::Error> {
    let query = format!(
        "SELECT {}
         FROM tasks
         WHERE user_id = $1 AND id = ANY($2)
         ORDER BY updated_at ASC",
        database::task_select_columns("tasks", "tasks.user_id")
    );
    sqlx::query_as(&query)
        .bind(user_id)
        .bind(task_ids)
        .fetch_all(&mut **tx)
        .await
}

async fn load_habits_for_sync(
    tx: &mut Transaction<'_, Postgres>,
    user_id: Uuid,
    since: Option<NaiveDateTime>,
    cursor: Option<&SyncCursor>,
) -> Result<Vec<database::HabitRow>, sqlx::Error> {
    match cursor {
        Some(cursor) => {
            sqlx::query_as(
                "SELECT id, name, created_at, updated_at, deleted_at, description, min_daily_frequency, difficulty_tier, duration_seconds, lockout_duration_seconds, skip_consequence
                 FROM habits
                 WHERE user_id = $1
                   AND ((xmin::text)::bigint >= $2 OR (xmin::text)::bigint = ANY($3))
                 ORDER BY updated_at ASC",
            )
            .bind(user_id)
            .bind(cursor.upper_bound_tx_id)
            .bind(&cursor.in_progress_tx_ids)
            .fetch_all(&mut **tx)
            .await
        }
        None => match since {
            Some(since_time) => {
                sqlx::query_as(
                    "SELECT id, name, created_at, updated_at, deleted_at, description, min_daily_frequency, difficulty_tier, duration_seconds, lockout_duration_seconds, skip_consequence
                     FROM habits
                     WHERE user_id = $1 AND updated_at > $2
                     ORDER BY updated_at ASC",
                )
                .bind(user_id)
                .bind(since_time)
                .fetch_all(&mut **tx)
                .await
            }
            None => {
                sqlx::query_as(
                    "SELECT id, name, created_at, updated_at, deleted_at, description, min_daily_frequency, difficulty_tier, duration_seconds, lockout_duration_seconds, skip_consequence
                     FROM habits
                     WHERE user_id = $1
                     ORDER BY updated_at ASC",
                )
                .bind(user_id)
                .fetch_all(&mut **tx)
                .await
            }
        },
    }
}

async fn load_trades_for_sync(
    tx: &mut Transaction<'_, Postgres>,
    user_id: Uuid,
    since: Option<NaiveDateTime>,
    cursor: Option<&SyncCursor>,
) -> Result<Vec<database::TradeRow>, sqlx::Error> {
    match cursor {
        Some(cursor) => {
            sqlx::query_as(
                "SELECT id, task_id, habit_id, reward_id, source_name, amount, created_at, updated_at, deleted_at, refunds_trade_id
                 FROM trades
                 WHERE user_id = $1
                   AND ((xmin::text)::bigint >= $2 OR (xmin::text)::bigint = ANY($3))
                 ORDER BY updated_at ASC",
            )
            .bind(user_id)
            .bind(cursor.upper_bound_tx_id)
            .bind(&cursor.in_progress_tx_ids)
            .fetch_all(&mut **tx)
            .await
        }
        None => match since {
            Some(since_time) => {
                sqlx::query_as(
                    "SELECT id, task_id, habit_id, reward_id, source_name, amount, created_at, updated_at, deleted_at, refunds_trade_id
                     FROM trades
                     WHERE user_id = $1 AND updated_at > $2
                     ORDER BY updated_at ASC",
                )
                .bind(user_id)
                .bind(since_time)
                .fetch_all(&mut **tx)
                .await
            }
            None => {
                sqlx::query_as(
                    "SELECT id, task_id, habit_id, reward_id, source_name, amount, created_at, updated_at, deleted_at, refunds_trade_id
                     FROM trades
                     WHERE user_id = $1
                     ORDER BY updated_at ASC",
                )
                .bind(user_id)
                .fetch_all(&mut **tx)
                .await
            }
        },
    }
}

async fn load_tags_for_sync(
    tx: &mut Transaction<'_, Postgres>,
    user_id: Uuid,
    since: Option<NaiveDateTime>,
    cursor: Option<&SyncCursor>,
) -> Result<Vec<database::TagRow>, sqlx::Error> {
    match cursor {
        Some(cursor) => {
            sqlx::query_as(
                "SELECT id, name, color_hex, created_at, updated_at, deleted_at
                 FROM tags
                 WHERE user_id = $1
                   AND ((xmin::text)::bigint >= $2 OR (xmin::text)::bigint = ANY($3))
                 ORDER BY updated_at ASC",
            )
            .bind(user_id)
            .bind(cursor.upper_bound_tx_id)
            .bind(&cursor.in_progress_tx_ids)
            .fetch_all(&mut **tx)
            .await
        }
        None => match since {
            Some(since_time) => {
                sqlx::query_as(
                    "SELECT id, name, color_hex, created_at, updated_at, deleted_at
                     FROM tags
                     WHERE user_id = $1 AND updated_at > $2
                     ORDER BY updated_at ASC",
                )
                .bind(user_id)
                .bind(since_time)
                .fetch_all(&mut **tx)
                .await
            }
            None => {
                sqlx::query_as(
                    "SELECT id, name, color_hex, created_at, updated_at, deleted_at
                     FROM tags
                     WHERE user_id = $1
                     ORDER BY updated_at ASC",
                )
                .bind(user_id)
                .fetch_all(&mut **tx)
                .await
            }
        },
    }
}

async fn load_task_tags_for_sync(
    tx: &mut Transaction<'_, Postgres>,
    user_id: Uuid,
    since: Option<NaiveDateTime>,
    cursor: Option<&SyncCursor>,
) -> Result<Vec<database::TaskTagRow>, sqlx::Error> {
    match cursor {
        Some(cursor) => {
            sqlx::query_as(
                "SELECT tt.task_id, tt.tag_id, tt.created_at, tt.updated_at, tt.deleted_at
                 FROM task_tags tt
                 JOIN tasks t ON tt.task_id = t.id
                 WHERE t.user_id = $1
                   AND (((tt.xmin)::text)::bigint >= $2 OR ((tt.xmin)::text)::bigint = ANY($3))
                 ORDER BY tt.updated_at ASC",
            )
            .bind(user_id)
            .bind(cursor.upper_bound_tx_id)
            .bind(&cursor.in_progress_tx_ids)
            .fetch_all(&mut **tx)
            .await
        }
        None => match since {
            Some(since_time) => {
                sqlx::query_as(
                    "SELECT tt.task_id, tt.tag_id, tt.created_at, tt.updated_at, tt.deleted_at
                     FROM task_tags tt
                     JOIN tasks t ON tt.task_id = t.id
                     WHERE t.user_id = $1 AND tt.updated_at > $2
                     ORDER BY tt.updated_at ASC",
                )
                .bind(user_id)
                .bind(since_time)
                .fetch_all(&mut **tx)
                .await
            }
            None => {
                sqlx::query_as(
                    "SELECT tt.task_id, tt.tag_id, tt.created_at, tt.updated_at, tt.deleted_at
                     FROM task_tags tt
                     JOIN tasks t ON tt.task_id = t.id
                     WHERE t.user_id = $1
                     ORDER BY tt.updated_at ASC",
                )
                .bind(user_id)
                .fetch_all(&mut **tx)
                .await
            }
        },
    }
}

async fn load_task_task_dependencies_for_sync(
    tx: &mut Transaction<'_, Postgres>,
    user_id: Uuid,
    since: Option<NaiveDateTime>,
    cursor: Option<&SyncCursor>,
) -> Result<Vec<database::TaskTaskDependencyRow>, sqlx::Error> {
    match cursor {
        Some(cursor) => {
            sqlx::query_as(
                "SELECT ttd.task_id, ttd.depends_on_task_id, ttd.created_at, ttd.updated_at, ttd.deleted_at
                 FROM task_task_dependencies ttd
                 JOIN tasks t ON ttd.task_id = t.id
                 WHERE t.user_id = $1
                   AND (((ttd.xmin)::text)::bigint >= $2 OR ((ttd.xmin)::text)::bigint = ANY($3))
                 ORDER BY ttd.updated_at ASC",
            )
            .bind(user_id)
            .bind(cursor.upper_bound_tx_id)
            .bind(&cursor.in_progress_tx_ids)
            .fetch_all(&mut **tx)
            .await
        }
        None => match since {
            Some(since_time) => {
                sqlx::query_as(
                    "SELECT ttd.task_id, ttd.depends_on_task_id, ttd.created_at, ttd.updated_at, ttd.deleted_at
                     FROM task_task_dependencies ttd
                     JOIN tasks t ON ttd.task_id = t.id
                     WHERE t.user_id = $1 AND ttd.updated_at > $2
                     ORDER BY ttd.updated_at ASC",
                )
                .bind(user_id)
                .bind(since_time)
                .fetch_all(&mut **tx)
                .await
            }
            None => {
                sqlx::query_as(
                    "SELECT ttd.task_id, ttd.depends_on_task_id, ttd.created_at, ttd.updated_at, ttd.deleted_at
                     FROM task_task_dependencies ttd
                     JOIN tasks t ON ttd.task_id = t.id
                     WHERE t.user_id = $1
                     ORDER BY ttd.updated_at ASC",
                )
                .bind(user_id)
                .fetch_all(&mut **tx)
                .await
            }
        },
    }
}

async fn load_task_habit_dependencies_for_sync(
    tx: &mut Transaction<'_, Postgres>,
    user_id: Uuid,
    since: Option<NaiveDateTime>,
    cursor: Option<&SyncCursor>,
) -> Result<Vec<database::TaskHabitDependencyRow>, sqlx::Error> {
    match cursor {
        Some(cursor) => {
            sqlx::query_as(
                "SELECT thd.task_id, thd.habit_id, thd.required_completions, thd.baseline_completion_count, thd.created_at, thd.updated_at, thd.deleted_at
                 FROM task_habit_dependencies thd
                 JOIN tasks t ON thd.task_id = t.id
                 WHERE t.user_id = $1
                   AND (((thd.xmin)::text)::bigint >= $2 OR ((thd.xmin)::text)::bigint = ANY($3))
                 ORDER BY thd.updated_at ASC",
            )
            .bind(user_id)
            .bind(cursor.upper_bound_tx_id)
            .bind(&cursor.in_progress_tx_ids)
            .fetch_all(&mut **tx)
            .await
        }
        None => match since {
            Some(since_time) => {
                sqlx::query_as(
                    "SELECT thd.task_id, thd.habit_id, thd.required_completions, thd.baseline_completion_count, thd.created_at, thd.updated_at, thd.deleted_at
                     FROM task_habit_dependencies thd
                     JOIN tasks t ON thd.task_id = t.id
                     WHERE t.user_id = $1 AND thd.updated_at > $2
                     ORDER BY thd.updated_at ASC",
                )
                .bind(user_id)
                .bind(since_time)
                .fetch_all(&mut **tx)
                .await
            }
            None => {
                sqlx::query_as(
                    "SELECT thd.task_id, thd.habit_id, thd.required_completions, thd.baseline_completion_count, thd.created_at, thd.updated_at, thd.deleted_at
                     FROM task_habit_dependencies thd
                     JOIN tasks t ON thd.task_id = t.id
                     WHERE t.user_id = $1
                     ORDER BY thd.updated_at ASC",
                )
                .bind(user_id)
                .fetch_all(&mut **tx)
                .await
            }
        },
    }
}

async fn load_habit_tags_for_sync(
    tx: &mut Transaction<'_, Postgres>,
    user_id: Uuid,
    since: Option<NaiveDateTime>,
    cursor: Option<&SyncCursor>,
) -> Result<Vec<database::HabitTagRow>, sqlx::Error> {
    match cursor {
        Some(cursor) => {
            sqlx::query_as(
                "SELECT ht.habit_id, ht.tag_id, ht.created_at, ht.updated_at, ht.deleted_at
                 FROM habit_tags ht
                 JOIN habits h ON ht.habit_id = h.id
                 WHERE h.user_id = $1
                   AND (((ht.xmin)::text)::bigint >= $2 OR ((ht.xmin)::text)::bigint = ANY($3))
                 ORDER BY ht.updated_at ASC",
            )
            .bind(user_id)
            .bind(cursor.upper_bound_tx_id)
            .bind(&cursor.in_progress_tx_ids)
            .fetch_all(&mut **tx)
            .await
        }
        None => match since {
            Some(since_time) => {
                sqlx::query_as(
                    "SELECT ht.habit_id, ht.tag_id, ht.created_at, ht.updated_at, ht.deleted_at
                     FROM habit_tags ht
                     JOIN habits h ON ht.habit_id = h.id
                     WHERE h.user_id = $1 AND ht.updated_at > $2
                     ORDER BY ht.updated_at ASC",
                )
                .bind(user_id)
                .bind(since_time)
                .fetch_all(&mut **tx)
                .await
            }
            None => {
                sqlx::query_as(
                    "SELECT ht.habit_id, ht.tag_id, ht.created_at, ht.updated_at, ht.deleted_at
                     FROM habit_tags ht
                     JOIN habits h ON ht.habit_id = h.id
                     WHERE h.user_id = $1
                     ORDER BY ht.updated_at ASC",
                )
                .bind(user_id)
                .fetch_all(&mut **tx)
                .await
            }
        },
    }
}

async fn load_rewards_for_sync(
    tx: &mut Transaction<'_, Postgres>,
    user_id: Uuid,
    since: Option<NaiveDateTime>,
    cursor: Option<&SyncCursor>,
) -> Result<Vec<database::RewardRow>, sqlx::Error> {
    match cursor {
        Some(cursor) => {
            sqlx::query_as(
                "SELECT id, name, description, created_at, updated_at, deleted_at, max_daily_frequency, damage_tier
                 FROM rewards
                 WHERE user_id = $1
                   AND ((xmin::text)::bigint >= $2 OR (xmin::text)::bigint = ANY($3))
                 ORDER BY updated_at ASC",
            )
            .bind(user_id)
            .bind(cursor.upper_bound_tx_id)
            .bind(&cursor.in_progress_tx_ids)
            .fetch_all(&mut **tx)
            .await
        }
        None => match since {
            Some(since_time) => {
                sqlx::query_as(
                    "SELECT id, name, description, created_at, updated_at, deleted_at, max_daily_frequency, damage_tier
                     FROM rewards
                     WHERE user_id = $1 AND updated_at > $2
                     ORDER BY updated_at ASC",
                )
                .bind(user_id)
                .bind(since_time)
                .fetch_all(&mut **tx)
                .await
            }
            None => {
                sqlx::query_as(
                    "SELECT id, name, description, created_at, updated_at, deleted_at, max_daily_frequency, damage_tier
                     FROM rewards
                     WHERE user_id = $1
                     ORDER BY updated_at ASC",
                )
                .bind(user_id)
                .fetch_all(&mut **tx)
                .await
            }
        },
    }
}

async fn load_reward_tags_for_sync(
    tx: &mut Transaction<'_, Postgres>,
    user_id: Uuid,
    since: Option<NaiveDateTime>,
    cursor: Option<&SyncCursor>,
) -> Result<Vec<database::RewardTagRow>, sqlx::Error> {
    match cursor {
        Some(cursor) => {
            sqlx::query_as(
                "SELECT rt.reward_id, rt.tag_id, rt.created_at, rt.updated_at, rt.deleted_at
                 FROM reward_tags rt
                 JOIN rewards r ON rt.reward_id = r.id
                 WHERE r.user_id = $1
                   AND (((rt.xmin)::text)::bigint >= $2 OR ((rt.xmin)::text)::bigint = ANY($3))
                 ORDER BY rt.updated_at ASC",
            )
            .bind(user_id)
            .bind(cursor.upper_bound_tx_id)
            .bind(&cursor.in_progress_tx_ids)
            .fetch_all(&mut **tx)
            .await
        }
        None => {
            match since {
                Some(since_time) => sqlx::query_as(
                    "SELECT rt.reward_id, rt.tag_id, rt.created_at, rt.updated_at, rt.deleted_at
                     FROM reward_tags rt
                     JOIN rewards r ON rt.reward_id = r.id
                     WHERE r.user_id = $1 AND rt.updated_at > $2
                     ORDER BY rt.updated_at ASC",
                )
                .bind(user_id)
                .bind(since_time)
                .fetch_all(&mut **tx)
                .await,
                None => sqlx::query_as(
                    "SELECT rt.reward_id, rt.tag_id, rt.created_at, rt.updated_at, rt.deleted_at
                     FROM reward_tags rt
                     JOIN rewards r ON rt.reward_id = r.id
                     WHERE r.user_id = $1
                     ORDER BY rt.updated_at ASC",
                )
                .bind(user_id)
                .fetch_all(&mut **tx)
                .await,
            }
        }
    }
}

async fn load_balance_for_sync(
    tx: &mut Transaction<'_, Postgres>,
    user_id: Uuid,
) -> Result<f64, sqlx::Error> {
    let (total,): (Option<i64>,) = sqlx::query_as(
        "SELECT COALESCE(SUM(amount), 0)
         FROM trades
         WHERE user_id = $1 AND deleted_at IS NULL",
    )
    .bind(user_id)
    .fetch_one(&mut **tx)
    .await?;

    Ok(total.unwrap_or(0) as f64)
}

async fn load_profile_for_sync(
    tx: &mut Transaction<'_, Postgres>,
    user_id: Uuid,
) -> Result<database::UserProfileRow, sqlx::Error> {
    sqlx::query_as(
        "SELECT
            email,
            general_difficulty,
            subscription_status
         FROM users
         WHERE id = $1",
    )
    .bind(user_id)
    .fetch_one(&mut **tx)
    .await
}
