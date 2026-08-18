use axum::{
    extract::{Query, State},
    response::{IntoResponse, Response},
    Extension, Json,
};
use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine as _};
use chrono::{NaiveDateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sqlx::{Postgres, Transaction};
use std::{collections::BTreeSet, fmt};
use tracing::{error, warn};
use uuid::Uuid;

use crate::{
    database::{self, Database},
    router::{App, AuthenticatedUser},
};

use super::{error::internal_error, ApiError};

const MIN_DAILY_FREQUENCY: f64 = 1.0 / 30.0;
const MAX_DAILY_FREQUENCY: f64 = 100.0;
const MIN_LOCKOUT_DURATION_SECONDS: i32 = 60;
const MAX_LOCKOUT_DURATION_SECONDS: i32 = 2_592_000;
const MIN_ADJUSTMENT_MULTIPLIER: f64 = 0.0;
const MAX_ADJUSTMENT_MULTIPLIER: f64 = 1000.0;
const TIMER_MODE_NAMED: &str = "named";
const TIMER_MODE_DURATION: &str = "duration";

fn validate_entity_text_fields(name: &str, description: &str) -> Result<(), ApiError> {
    let name_len = name.chars().count();
    if !(1..=100).contains(&name_len) {
        return Err(ApiError::Validation(format!(
            "Please provide a name between 1 and 100 characters long. Your current name is {} characters.",
            name_len
        )));
    }

    let desc_len = description.chars().count();
    if desc_len > 10000 {
        return Err(ApiError::Validation(format!(
            "Description is too long ({} characters), max 10,000.",
            desc_len
        )));
    }

    Ok(())
}

fn validate_daily_frequency(field_name: &str, frequency: Option<f64>) -> Result<(), ApiError> {
    if let Some(frequency) = frequency {
        if !(MIN_DAILY_FREQUENCY..=MAX_DAILY_FREQUENCY).contains(&frequency) {
            return Err(ApiError::Validation(format!(
                "The '{}' must be between {} and {}. You sent {}.",
                field_name, MIN_DAILY_FREQUENCY, MAX_DAILY_FREQUENCY, frequency
            )));
        }
    }

    Ok(())
}

fn validate_adjustment_multiplier(
    field_name: &str,
    multiplier: Option<f64>,
) -> Result<(), ApiError> {
    if let Some(multiplier) = multiplier {
        if !(MIN_ADJUSTMENT_MULTIPLIER..=MAX_ADJUSTMENT_MULTIPLIER).contains(&multiplier) {
            return Err(ApiError::Validation(format!(
                "The '{}' must be between {} and {}. You sent {}.",
                field_name, MIN_ADJUSTMENT_MULTIPLIER, MAX_ADJUSTMENT_MULTIPLIER, multiplier
            )));
        }
    }

    Ok(())
}

fn validate_base_price(base_price: i32) -> Result<(), ApiError> {
    if base_price < 0 {
        return Err(ApiError::Validation(format!(
            "The 'base_price' must be greater than or equal to 0. You sent {}.",
            base_price
        )));
    }

    Ok(())
}

fn validate_recurring_task_fields(
    name: &str,
    description: &str,
    min_daily_frequency: Option<f64>,
    lockout_duration_seconds: Option<i32>,
    base_price: i32,
) -> Result<(), ApiError> {
    validate_entity_text_fields(name, description)?;
    validate_daily_frequency("min_daily_frequency", min_daily_frequency)?;
    validate_base_price(base_price)?;

    if let Some(lockout_duration_seconds) = lockout_duration_seconds {
        if !(MIN_LOCKOUT_DURATION_SECONDS..=MAX_LOCKOUT_DURATION_SECONDS)
            .contains(&lockout_duration_seconds)
        {
            return Err(ApiError::Validation(format!(
                "The 'lockout_duration_seconds' must be between {} and {}. You sent {}.",
                MIN_LOCKOUT_DURATION_SECONDS,
                MAX_LOCKOUT_DURATION_SECONDS,
                lockout_duration_seconds
            )));
        }
    }

    Ok(())
}

fn validate_task_fields(name: &str, description: &str, base_price: i32) -> Result<(), ApiError> {
    validate_entity_text_fields(name, description)?;
    validate_base_price(base_price)?;

    Ok(())
}

fn validate_reward_fields(
    name: &str,
    description: &str,
    recurring: bool,
    max_daily_frequency: Option<f64>,
    lockout_duration_seconds: Option<i32>,
    base_price: i32,
) -> Result<(), ApiError> {
    validate_entity_text_fields(name, description)?;
    validate_base_price(base_price)?;
    if !recurring && max_daily_frequency.is_some() {
        return Err(ApiError::Validation(
            "One-off rewards cannot include max_daily_frequency.".to_string(),
        ));
    }
    validate_daily_frequency("max_daily_frequency", max_daily_frequency)?;

    if let Some(lockout_duration_seconds) = lockout_duration_seconds {
        if !(MIN_LOCKOUT_DURATION_SECONDS..=MAX_LOCKOUT_DURATION_SECONDS)
            .contains(&lockout_duration_seconds)
        {
            return Err(ApiError::Validation(format!(
                "The 'lockout_duration_seconds' must be between {} and {}. You sent {}.",
                MIN_LOCKOUT_DURATION_SECONDS,
                MAX_LOCKOUT_DURATION_SECONDS,
                lockout_duration_seconds
            )));
        }
    }

    Ok(())
}

fn validate_timer_intervals(name: &str, intervals: &[TimerInterval]) -> Result<(), ApiError> {
    let name_len = name.chars().count();
    if !(1..=50).contains(&name_len) {
        return Err(ApiError::Validation(format!(
            "Timer names must be between 1 and 50 characters long. Your current name is {} characters.",
            name_len
        )));
    }

    if intervals.is_empty() {
        return Err(ApiError::Validation(
            "Timers must include at least one interval.".to_string(),
        ));
    }

    for interval in intervals {
        let interval_name_len = interval.name.chars().count();
        if !(1..=50).contains(&interval_name_len) {
            return Err(ApiError::Validation(format!(
                "Timer interval names must be between 1 and 50 characters long. Your current interval name is {} characters.",
                interval_name_len
            )));
        }

        if !(1..=43_200).contains(&interval.duration_seconds) {
            return Err(ApiError::Validation(format!(
                "Timer interval durationSeconds must be between 1 and 43200. You sent {}.",
                interval.duration_seconds
            )));
        }
    }

    Ok(())
}

fn validate_timer_assignment(
    entity_kind: &str,
    timer_mode: Option<&str>,
    timer_id: Option<&str>,
) -> Result<(), ApiError> {
    match timer_mode {
        None => {
            if timer_id.is_some() {
                return Err(ApiError::Validation(format!(
                    "{} timerId must be null when timerMode is not set.",
                    entity_kind
                )));
            }
        }
        Some(TIMER_MODE_NAMED) => {
            if timer_id.is_none() {
                return Err(ApiError::Validation(format!(
                    "{} named timers require timerId.",
                    entity_kind
                )));
            }
        }
        Some(TIMER_MODE_DURATION) => {
            if entity_kind == "Reward" {
                return Err(ApiError::Validation(
                    "Rewards cannot use duration timers.".to_string(),
                ));
            }
            if timer_id.is_some() {
                return Err(ApiError::Validation(format!(
                    "{} duration timers must not include timerId.",
                    entity_kind
                )));
            }
        }
        Some(other) => {
            return Err(ApiError::Validation(format!(
                "{} timerMode must be 'named', 'duration', or null. You sent '{}'.",
                entity_kind, other
            )));
        }
    }

    Ok(())
}

async fn parse_and_validate_timer_id(
    tx: &mut Transaction<'_, Postgres>,
    user_id: Uuid,
    timer_mode: Option<&str>,
    timer_id: Option<&str>,
) -> Result<Option<Uuid>, ApiError> {
    if timer_mode != Some(TIMER_MODE_NAMED) {
        return Ok(None);
    }

    let raw_timer_id = timer_id.expect("validate_timer_assignment ensures named timerId exists");
    let parsed_timer_id = raw_timer_id
        .parse::<Uuid>()
        .map_err(|_| ApiError::Validation(format!("Invalid timer id format: {}", raw_timer_id)))?;

    let owned_timer: Option<(Uuid,)> =
        sqlx::query_as("SELECT id FROM timers WHERE id = $1 AND user_id = $2")
            .bind(parsed_timer_id)
            .bind(user_id)
            .fetch_optional(&mut **tx)
            .await
            .map_err(|e| internal_error("sync.validate_timer_assignment", e))?;

    if owned_timer.is_none() {
        return Err(ApiError::Validation(format!(
            "Invalid timer reference: {}",
            raw_timer_id
        )));
    }

    Ok(Some(parsed_timer_id))
}

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
    revision: i64,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SyncPushRequest {
    pub base_cursor: Option<String>,
    pub operations: Vec<SyncOperationInput>,
}

impl SyncPushRequest {
    fn remove_processed_operations(&mut self, processed_operation_ids: &BTreeSet<Uuid>) {
        if processed_operation_ids.is_empty() {
            return;
        }

        self.operations
            .retain(|operation| !processed_operation_ids.contains(&operation.operation_id));
    }
}

#[derive(Default)]
struct ExpandedSyncInput {
    timers: Option<Vec<SyncTimerInput>>,
    tasks: Option<Vec<SyncTaskInput>>,
    recurring_tasks: Option<Vec<SyncRecurringTaskInput>>,
    trades: Option<Vec<SyncTradeInput>>,
    tags: Option<Vec<SyncTagInput>>,
    task_tags: Option<Vec<SyncTaskTagInput>>,
    task_task_dependencies: Option<Vec<SyncTaskTaskDependencyInput>>,
    task_recurring_task_dependencies: Option<Vec<SyncTaskRecurringTaskDependencyInput>>,
    recurring_task_tags: Option<Vec<SyncRecurringTaskTagInput>>,
    rewards: Option<Vec<SyncRewardInput>>,
    reward_task_dependencies: Option<Vec<SyncRewardTaskDependencyInput>>,
    reward_recurring_task_dependencies: Option<Vec<SyncRewardRecurringTaskDependencyInput>>,
    reward_tags: Option<Vec<SyncRewardTagInput>>,
    theme_palettes: Option<ThemePalettes>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SyncOperationInput {
    pub operation_id: Uuid,
    pub kind: String,
    pub base_record_revision: Option<i64>,
    pub payload: Value,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ThemePalettes {
    pub main: String,
    pub accent: String,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TimerInterval {
    pub name: String,
    pub duration_seconds: i32,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SyncTimerInput {
    pub id: String,
    pub name: String,
    pub intervals: Vec<TimerInterval>,
    pub created_at: NaiveDateTime,
    #[allow(dead_code)]
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SyncTaskInput {
    pub id: String,
    pub name: String,
    pub description: String,
    pub created_at: NaiveDateTime,
    #[allow(dead_code)]
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub base_price: i32,
    pub due_date: Option<NaiveDateTime>,
    pub pinned: bool,
    pub hidden: bool,
    pub timer_mode: Option<String>,
    pub timer_id: Option<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SyncRecurringTaskInput {
    pub id: String,
    pub name: String,
    pub description: String,
    pub created_at: NaiveDateTime,
    #[allow(dead_code)]
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub min_daily_frequency: Option<f64>,
    pub base_price: i32,
    pub lockout_duration_seconds: Option<i32>,
    pub pinned: bool,
    pub hidden: bool,
    pub timer_mode: Option<String>,
    pub timer_id: Option<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SyncTradeInput {
    pub id: String,
    pub task_id: Option<String>,
    pub recurring_task_id: Option<String>,
    pub reward_id: Option<String>,
    pub source_name: Option<String>,
    pub amount: i32,
    pub vault_amount_micro: Option<i64>,
    pub adjustment_base_amount: Option<i32>,
    pub one_time_adjustment_multiplier: Option<f64>,
    pub trade_kind: String,
    pub vault_interest_hour: Option<NaiveDateTime>,
    pub created_at: NaiveDateTime,
    #[allow(dead_code)]
    pub updated_at: NaiveDateTime,
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
pub struct SyncTaskRecurringTaskDependencyInput {
    pub task_id: String,
    pub recurring_task_id: String,
    pub required_completions: i32,
    pub baseline_completion_count: i32,
    pub created_at: NaiveDateTime,
    #[allow(dead_code)]
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncRecurringTaskTagInput {
    pub recurring_task_id: String,
    pub tag_id: String,
    pub created_at: NaiveDateTime,
    #[allow(dead_code)]
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SyncRewardInput {
    pub id: String,
    pub recurring: bool,
    pub name: String,
    pub description: String,
    pub created_at: NaiveDateTime,
    #[allow(dead_code)]
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub max_daily_frequency: Option<f64>,
    pub base_price: i32,
    pub lockout_duration_seconds: Option<i32>,
    pub pinned: bool,
    pub hidden: bool,
    pub timer_mode: Option<String>,
    pub timer_id: Option<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncRewardTaskDependencyInput {
    pub reward_id: String,
    pub depends_on_task_id: String,
    pub created_at: NaiveDateTime,
    #[allow(dead_code)]
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncRewardRecurringTaskDependencyInput {
    pub reward_id: String,
    pub recurring_task_id: String,
    pub required_completions: i32,
    pub baseline_completion_count: i32,
    pub created_at: NaiveDateTime,
    #[allow(dead_code)]
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
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

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncResponse {
    pub timers: Vec<TimerOutput>,
    pub tasks: Vec<TaskOutput>,
    pub recurring_tasks: Vec<RecurringTaskOutput>,
    pub trades: Vec<TradeOutput>,
    pub tags: Vec<TagOutput>,
    pub task_tags: Vec<TaskTagOutput>,
    pub task_task_dependencies: Vec<TaskTaskDependencyOutput>,
    pub task_recurring_task_dependencies: Vec<TaskRecurringTaskDependencyOutput>,
    pub recurring_task_tags: Vec<RecurringTaskTagOutput>,
    pub rewards: Vec<RewardOutput>,
    pub reward_task_dependencies: Vec<RewardTaskDependencyOutput>,
    pub reward_recurring_task_dependencies: Vec<RewardRecurringTaskDependencyOutput>,
    pub reward_tags: Vec<RewardTagOutput>,
    pub balance: BalanceOutput,
    pub server_cursor: String,
    pub server_time: NaiveDateTime,
    pub email: Option<String>,
    pub is_premium: bool,
    pub theme_palettes: ThemePalettes,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TimerOutput {
    pub id: String,
    pub name: String,
    pub intervals: Vec<TimerInterval>,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub server_revision: i64,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RecurringTaskOutput {
    pub id: String,
    pub name: String,
    pub description: String,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub server_revision: i64,
    pub min_daily_frequency: Option<f64>,
    pub base_price: i32,
    pub lockout_duration_seconds: Option<i32>,
    pub pinned: bool,
    pub hidden: bool,
    pub timer_mode: Option<String>,
    pub timer_id: Option<String>,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TaskOutput {
    pub id: String,
    pub recurring: bool,
    pub name: String,
    pub description: String,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub server_revision: i64,
    pub base_price: i32,
    pub min_daily_frequency: Option<f64>,
    pub lockout_duration_seconds: Option<i32>,
    pub due_date: Option<NaiveDateTime>,
    pub pinned: bool,
    pub hidden: bool,
    pub timer_mode: Option<String>,
    pub timer_id: Option<String>,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TradeOutput {
    pub id: String,
    pub task_id: Option<String>,
    pub recurring_task_id: Option<String>,
    pub reward_id: Option<String>,
    pub source_name: Option<String>,
    pub amount: i32,
    pub vault_amount_micro: Option<i64>,
    pub adjustment_base_amount: Option<i32>,
    pub one_time_adjustment_multiplier: Option<f64>,
    pub trade_kind: String,
    pub vault_interest_hour: Option<NaiveDateTime>,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub refunds_trade_id: Option<String>,
    pub server_revision: i64,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TagOutput {
    pub id: String,
    pub name: String,
    pub color_hex: String,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub server_revision: i64,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TaskTagOutput {
    pub task_id: String,
    pub tag_id: String,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub server_revision: i64,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TaskTaskDependencyOutput {
    pub task_id: String,
    pub depends_on_task_id: String,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub server_revision: i64,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TaskRecurringTaskDependencyOutput {
    pub task_id: String,
    pub recurring_task_id: String,
    pub required_completions: i32,
    pub baseline_completion_count: i32,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub server_revision: i64,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RecurringTaskTagOutput {
    pub recurring_task_id: String,
    pub tag_id: String,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub server_revision: i64,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RewardOutput {
    pub id: String,
    pub recurring: bool,
    pub name: String,
    pub description: String,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub server_revision: i64,
    pub max_daily_frequency: Option<f64>,
    pub base_price: i32,
    pub lockout_duration_seconds: Option<i32>,
    pub pinned: bool,
    pub hidden: bool,
    pub timer_mode: Option<String>,
    pub timer_id: Option<String>,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RewardTaskDependencyOutput {
    pub reward_id: String,
    pub depends_on_task_id: String,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub server_revision: i64,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RewardRecurringTaskDependencyOutput {
    pub reward_id: String,
    pub recurring_task_id: String,
    pub required_completions: i32,
    pub baseline_completion_count: i32,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub server_revision: i64,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RewardTagOutput {
    pub reward_id: String,
    pub tag_id: String,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub server_revision: i64,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BalanceOutput {
    pub point_balance: i64,
}

fn task_output_from_row(row: database::TaskRow) -> TaskOutput {
    TaskOutput {
        id: row.id.to_string(),
        recurring: row.recurring,
        name: row.name,
        description: row.description,
        created_at: row.created_at,
        updated_at: row.updated_at,
        deleted_at: row.deleted_at,
        base_price: row.base_price,
        min_daily_frequency: row.min_daily_frequency,
        lockout_duration_seconds: row.lockout_duration_seconds,
        due_date: row.due_date,
        pinned: row.pinned,
        hidden: row.hidden,
        timer_mode: row.timer_mode,
        timer_id: row.timer_id.map(|id| id.to_string()),
        server_revision: row.server_revision,
    }
}

fn timer_output_from_row(row: database::TimerRow) -> TimerOutput {
    TimerOutput {
        id: row.id.to_string(),
        name: row.name,
        intervals: serde_json::from_value(row.intervals)
            .expect("timer intervals are written only after sync validation"),
        created_at: row.created_at,
        updated_at: row.updated_at,
        deleted_at: row.deleted_at,
        server_revision: row.server_revision,
    }
}

fn trade_output_from_row(row: database::TradeRow) -> TradeOutput {
    TradeOutput {
        id: row.id.to_string(),
        task_id: row.task_id.map(|id| id.to_string()),
        recurring_task_id: row.recurring_task_id.map(|id| id.to_string()),
        reward_id: row.reward_id.map(|id| id.to_string()),
        source_name: row.source_name,
        amount: row.amount,
        vault_amount_micro: row.vault_amount_micro,
        adjustment_base_amount: row.adjustment_base_amount,
        one_time_adjustment_multiplier: row.one_time_adjustment_multiplier,
        trade_kind: row.trade_kind,
        vault_interest_hour: row.vault_interest_hour,
        created_at: row.created_at,
        updated_at: row.updated_at,
        deleted_at: row.deleted_at,
        refunds_trade_id: row.refunds_trade_id.map(|id| id.to_string()),
        server_revision: row.server_revision,
    }
}

fn recurring_task_output_from_row(row: database::RecurringTaskRow) -> RecurringTaskOutput {
    RecurringTaskOutput {
        id: row.id.to_string(),
        name: row.name,
        description: row.description,
        created_at: row.created_at,
        updated_at: row.updated_at,
        deleted_at: row.deleted_at,
        min_daily_frequency: row.min_daily_frequency,
        base_price: row.base_price,
        lockout_duration_seconds: row.lockout_duration_seconds,
        pinned: row.pinned,
        hidden: row.hidden,
        timer_mode: row.timer_mode,
        timer_id: row.timer_id.map(|id| id.to_string()),
        server_revision: row.server_revision,
    }
}

fn tag_output_from_row(row: database::TagRow) -> TagOutput {
    TagOutput {
        id: row.id.to_string(),
        name: row.name,
        color_hex: row.color_hex.trim().to_string(),
        created_at: row.created_at,
        updated_at: row.updated_at,
        deleted_at: row.deleted_at,
        server_revision: row.server_revision,
    }
}

fn task_tag_output_from_row(row: database::TaskTagRow) -> TaskTagOutput {
    TaskTagOutput {
        task_id: row.task_id.to_string(),
        tag_id: row.tag_id.to_string(),
        created_at: row.created_at,
        updated_at: row.updated_at,
        deleted_at: row.deleted_at,
        server_revision: row.server_revision,
    }
}

fn task_task_dependency_output_from_row(
    row: database::TaskTaskDependencyRow,
) -> TaskTaskDependencyOutput {
    TaskTaskDependencyOutput {
        task_id: row.task_id.to_string(),
        depends_on_task_id: row.depends_on_task_id.to_string(),
        created_at: row.created_at,
        updated_at: row.updated_at,
        deleted_at: row.deleted_at,
        server_revision: row.server_revision,
    }
}

fn task_recurring_task_dependency_output_from_row(
    row: database::TaskRecurringTaskDependencyRow,
) -> TaskRecurringTaskDependencyOutput {
    TaskRecurringTaskDependencyOutput {
        task_id: row.task_id.to_string(),
        recurring_task_id: row.recurring_task_id.to_string(),
        required_completions: row.required_completions,
        baseline_completion_count: row.baseline_completion_count,
        created_at: row.created_at,
        updated_at: row.updated_at,
        deleted_at: row.deleted_at,
        server_revision: row.server_revision,
    }
}

fn recurring_task_tag_output_from_row(
    row: database::RecurringTaskTagRow,
) -> RecurringTaskTagOutput {
    RecurringTaskTagOutput {
        recurring_task_id: row.recurring_task_id.to_string(),
        tag_id: row.tag_id.to_string(),
        created_at: row.created_at,
        updated_at: row.updated_at,
        deleted_at: row.deleted_at,
        server_revision: row.server_revision,
    }
}

fn reward_output_from_row(row: database::RewardRow) -> RewardOutput {
    RewardOutput {
        id: row.id.to_string(),
        recurring: row.recurring,
        name: row.name,
        description: row.description,
        created_at: row.created_at,
        updated_at: row.updated_at,
        deleted_at: row.deleted_at,
        max_daily_frequency: row.max_daily_frequency,
        base_price: row.base_price,
        lockout_duration_seconds: row.lockout_duration_seconds,
        pinned: row.pinned,
        hidden: row.hidden,
        timer_mode: row.timer_mode,
        timer_id: row.timer_id.map(|id| id.to_string()),
        server_revision: row.server_revision,
    }
}

fn reward_task_dependency_output_from_row(
    row: database::RewardTaskDependencyRow,
) -> RewardTaskDependencyOutput {
    RewardTaskDependencyOutput {
        reward_id: row.reward_id.to_string(),
        depends_on_task_id: row.depends_on_task_id.to_string(),
        created_at: row.created_at,
        updated_at: row.updated_at,
        deleted_at: row.deleted_at,
        server_revision: row.server_revision,
    }
}

fn reward_recurring_task_dependency_output_from_row(
    row: database::RewardRecurringTaskDependencyRow,
) -> RewardRecurringTaskDependencyOutput {
    RewardRecurringTaskDependencyOutput {
        reward_id: row.reward_id.to_string(),
        recurring_task_id: row.recurring_task_id.to_string(),
        required_completions: row.required_completions,
        baseline_completion_count: row.baseline_completion_count,
        created_at: row.created_at,
        updated_at: row.updated_at,
        deleted_at: row.deleted_at,
        server_revision: row.server_revision,
    }
}

fn reward_tag_output_from_row(row: database::RewardTagRow) -> RewardTagOutput {
    RewardTagOutput {
        reward_id: row.reward_id.to_string(),
        tag_id: row.tag_id.to_string(),
        created_at: row.created_at,
        updated_at: row.updated_at,
        deleted_at: row.deleted_at,
        server_revision: row.server_revision,
    }
}

fn upsert_output<T, K, F>(outputs: &mut Vec<T>, output: T, key: F)
where
    K: PartialEq,
    F: Fn(&T) -> K,
{
    let output_key = key(&output);
    outputs.retain(|existing| key(existing) != output_key);
    outputs.push(output);
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
        server_revision: row.server_revision,
    });
}

fn upsert_task_recurring_task_dependency_output(
    outputs: &mut Vec<TaskRecurringTaskDependencyOutput>,
    row: database::TaskRecurringTaskDependencyRow,
) {
    outputs.retain(|existing| {
        existing.task_id != row.task_id.to_string()
            || existing.recurring_task_id != row.recurring_task_id.to_string()
    });
    outputs.push(TaskRecurringTaskDependencyOutput {
        task_id: row.task_id.to_string(),
        recurring_task_id: row.recurring_task_id.to_string(),
        required_completions: row.required_completions,
        baseline_completion_count: row.baseline_completion_count,
        created_at: row.created_at,
        updated_at: row.updated_at,
        deleted_at: row.deleted_at,
        server_revision: row.server_revision,
    });
}

fn upsert_reward_task_dependency_output(
    outputs: &mut Vec<RewardTaskDependencyOutput>,
    row: database::RewardTaskDependencyRow,
) {
    outputs.retain(|existing| {
        existing.reward_id != row.reward_id.to_string()
            || existing.depends_on_task_id != row.depends_on_task_id.to_string()
    });
    outputs.push(RewardTaskDependencyOutput {
        reward_id: row.reward_id.to_string(),
        depends_on_task_id: row.depends_on_task_id.to_string(),
        created_at: row.created_at,
        updated_at: row.updated_at,
        deleted_at: row.deleted_at,
        server_revision: row.server_revision,
    });
}

fn upsert_reward_recurring_task_dependency_output(
    outputs: &mut Vec<RewardRecurringTaskDependencyOutput>,
    row: database::RewardRecurringTaskDependencyRow,
) {
    outputs.retain(|existing| {
        existing.reward_id != row.reward_id.to_string()
            || existing.recurring_task_id != row.recurring_task_id.to_string()
    });
    outputs.push(RewardRecurringTaskDependencyOutput {
        reward_id: row.reward_id.to_string(),
        recurring_task_id: row.recurring_task_id.to_string(),
        required_completions: row.required_completions,
        baseline_completion_count: row.baseline_completion_count,
        created_at: row.created_at,
        updated_at: row.updated_at,
        deleted_at: row.deleted_at,
        server_revision: row.server_revision,
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
                    "Trade references an invalid task, recurringTask, or reward.".to_string(),
                )
            }
        }
        sqlx::Error::Protocol(message) => ApiError::Validation(message),
        other => internal_error("sync.upsert_trade", other),
    }
}

fn map_owned_entity_upsert_error(error: sqlx::Error, entity_name: &str) -> ApiError {
    match error {
        sqlx::Error::RowNotFound => ApiError::Validation(format!(
            "{} id belongs to another user or is otherwise unavailable.",
            entity_name
        )),
        other => {
            error!(
                operation = "sync.upsert_owned_entity",
                entity_name,
                error = ?other,
                "internal backend operation failed"
            );
            ApiError::Internal
        }
    }
}

fn profile_is_entitled(profile_row: &database::UserProfileRow) -> bool {
    match profile_row.subscription_status.as_str() {
        "active" | "grace_period" => profile_row
            .subscription_expires_at
            .map(|expires_at| expires_at > Utc::now().naive_utc())
            .unwrap_or(true),
        "billing_retry" | "expired" | "revoked" | "none" => false,
        _ => false,
    }
}

fn is_theme_palette(palette: &str) -> bool {
    matches!(
        palette,
        "paper"
            | "cotton"
            | "porcelain"
            | "ink"
            | "yellow"
            | "amber"
            | "orange"
            | "tomato"
            | "red"
            | "ruby"
            | "crimson"
            | "pink"
            | "plum"
            | "purple"
            | "violet"
            | "iris"
            | "indigo"
            | "blue"
            | "cyan"
            | "teal"
            | "jade"
            | "green"
            | "grass"
            | "lime"
            | "mint"
            | "sky"
    )
}

fn validate_theme_palettes(theme_palettes: &ThemePalettes) -> Result<(), ApiError> {
    if !is_theme_palette(&theme_palettes.main) {
        return Err(ApiError::Validation(format!(
            "themePalettes.main must be one of the theme palettes. You sent {}.",
            theme_palettes.main
        )));
    }

    if theme_palettes.accent != "semantic" && !is_theme_palette(&theme_palettes.accent) {
        return Err(ApiError::Validation(format!(
            "themePalettes.accent must be semantic or one of the theme palettes. You sent {}.",
            theme_palettes.accent
        )));
    }

    Ok(())
}

fn theme_palettes_from_profile(profile_row: &database::UserProfileRow) -> ThemePalettes {
    ThemePalettes {
        main: profile_row.theme_palette_main.clone(),
        accent: profile_row.theme_palette_accent.clone(),
    }
}

fn theme_palettes_to_database_row(
    theme_palettes: &ThemePalettes,
) -> database::UserThemePalettesRow {
    database::UserThemePalettesRow {
        main: theme_palettes.main.clone(),
        accent: theme_palettes.accent.clone(),
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Ord, PartialOrd)]
enum SyncEntityKind {
    Timer,
    Task,
    RecurringTask,
    Trade,
    Tag,
    TaskTag,
    TaskTaskDependency,
    TaskRecurringTaskDependency,
    RecurringTaskTag,
    Reward,
    RewardTaskDependency,
    RewardRecurringTaskDependency,
    RewardTag,
}

impl SyncEntityKind {
    fn label(self) -> &'static str {
        match self {
            Self::Timer => "timer",
            Self::Task => "task",
            Self::RecurringTask => "recurringTask",
            Self::Trade => "trade",
            Self::Tag => "tag",
            Self::TaskTag => "task_tag",
            Self::TaskTaskDependency => "task_task_dependency",
            Self::TaskRecurringTaskDependency => "task_recurring_task_dependency",
            Self::RecurringTaskTag => "recurring_task_tag",
            Self::Reward => "reward",
            Self::RewardTaskDependency => "reward_task_dependency",
            Self::RewardRecurringTaskDependency => "reward_recurring_task_dependency",
            Self::RewardTag => "reward_tag",
        }
    }
}

impl fmt::Display for SyncEntityKind {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.label())
    }
}

#[derive(Clone, Debug, Eq, PartialEq, Ord, PartialOrd)]
enum SyncEntityId {
    Single(String),
    Pair(String, String),
}

impl SyncEntityId {
    fn parse_single(&self, entity_kind: SyncEntityKind) -> Result<Uuid, ApiError> {
        match self {
            Self::Single(id) => parse_entity_uuid(entity_kind.label(), id),
            Self::Pair(_, _) => Err(ApiError::Validation(format!(
                "Invalid {} id format: {}",
                entity_kind, self
            ))),
        }
    }

    fn parse_pair(
        &self,
        entity_kind: SyncEntityKind,
        left_name: &str,
        right_name: &str,
    ) -> Result<(Uuid, Uuid), ApiError> {
        let Self::Pair(left, right) = self else {
            return Err(ApiError::Validation(format!(
                "Invalid {} id format: {}",
                entity_kind, self
            )));
        };
        let left = left
            .parse::<Uuid>()
            .map_err(|_| ApiError::Validation(format!("Invalid {left_name} id format: {left}")))?;
        let right = right.parse::<Uuid>().map_err(|_| {
            ApiError::Validation(format!("Invalid {right_name} id format: {right}"))
        })?;
        Ok((left, right))
    }
}

impl fmt::Display for SyncEntityId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Single(id) => f.write_str(id),
            Self::Pair(left, right) => write!(f, "{left}:{right}"),
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq, Ord, PartialOrd)]
struct SyncEntityRef {
    kind: SyncEntityKind,
    id: SyncEntityId,
}

impl SyncEntityRef {
    fn single(kind: SyncEntityKind, id: String) -> Self {
        Self {
            kind,
            id: SyncEntityId::Single(id),
        }
    }

    fn pair(kind: SyncEntityKind, left: String, right: String) -> Self {
        Self {
            kind,
            id: SyncEntityId::Pair(left, right),
        }
    }
}

impl fmt::Display for SyncEntityRef {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{} {}", self.kind, self.id)
    }
}

struct ExpandedOperation {
    entity: SyncEntityRef,
    base_record_revision: Option<i64>,
}

fn expand_operations(
    operations: Vec<SyncOperationInput>,
) -> Result<(ExpandedSyncInput, Vec<ExpandedOperation>), ApiError> {
    let mut batch = ExpandedSyncInput::default();
    let mut expanded = Vec::new();
    for operation in operations {
        match operation.kind.as_str() {
            "upsertTimer" => {
                let timer: SyncTimerInput =
                    serde_json::from_value(operation.payload).map_err(|error| {
                        ApiError::Validation(format!(
                            "Invalid upsertTimer operation payload: {error}"
                        ))
                    })?;
                let entity = SyncEntityRef::single(SyncEntityKind::Timer, timer.id.clone());
                batch.timers.get_or_insert_with(Vec::new).push(timer);
                expanded.push(ExpandedOperation {
                    entity,
                    base_record_revision: operation.base_record_revision,
                });
            }
            "upsertTask" => {
                let task: SyncTaskInput =
                    serde_json::from_value(operation.payload).map_err(|error| {
                        ApiError::Validation(format!(
                            "Invalid upsertTask operation payload: {error}"
                        ))
                    })?;
                let entity = SyncEntityRef::single(SyncEntityKind::Task, task.id.clone());
                batch.tasks.get_or_insert_with(Vec::new).push(task);
                expanded.push(ExpandedOperation {
                    entity,
                    base_record_revision: operation.base_record_revision,
                });
            }
            "upsertRecurringTask" => {
                let recurring_task: SyncRecurringTaskInput =
                    serde_json::from_value(operation.payload).map_err(|error| {
                        ApiError::Validation(format!(
                            "Invalid upsertRecurringTask operation payload: {error}"
                        ))
                    })?;
                let entity =
                    SyncEntityRef::single(SyncEntityKind::RecurringTask, recurring_task.id.clone());
                batch
                    .recurring_tasks
                    .get_or_insert_with(Vec::new)
                    .push(recurring_task);
                expanded.push(ExpandedOperation {
                    entity,
                    base_record_revision: operation.base_record_revision,
                });
            }
            "upsertTrade" => {
                let trade: SyncTradeInput =
                    serde_json::from_value(operation.payload).map_err(|error| {
                        ApiError::Validation(format!(
                            "Invalid upsertTrade operation payload: {error}"
                        ))
                    })?;
                let entity = SyncEntityRef::single(SyncEntityKind::Trade, trade.id.clone());
                batch.trades.get_or_insert_with(Vec::new).push(trade);
                expanded.push(ExpandedOperation {
                    entity,
                    base_record_revision: operation.base_record_revision,
                });
            }
            "upsertTag" => {
                let tag: SyncTagInput =
                    serde_json::from_value(operation.payload).map_err(|error| {
                        ApiError::Validation(format!(
                            "Invalid upsertTag operation payload: {error}"
                        ))
                    })?;
                let entity = SyncEntityRef::single(SyncEntityKind::Tag, tag.id.clone());
                batch.tags.get_or_insert_with(Vec::new).push(tag);
                expanded.push(ExpandedOperation {
                    entity,
                    base_record_revision: operation.base_record_revision,
                });
            }
            "upsertTaskTag" => {
                let task_tag: SyncTaskTagInput = serde_json::from_value(operation.payload)
                    .map_err(|error| {
                        ApiError::Validation(format!(
                            "Invalid upsertTaskTag operation payload: {error}"
                        ))
                    })?;
                let entity = SyncEntityRef::pair(
                    SyncEntityKind::TaskTag,
                    task_tag.task_id.clone(),
                    task_tag.tag_id.clone(),
                );
                batch.task_tags.get_or_insert_with(Vec::new).push(task_tag);
                expanded.push(ExpandedOperation {
                    entity,
                    base_record_revision: operation.base_record_revision,
                });
            }
            "upsertTaskTaskDependency" => {
                let dependency: SyncTaskTaskDependencyInput =
                    serde_json::from_value(operation.payload).map_err(|error| {
                        ApiError::Validation(format!(
                            "Invalid upsertTaskTaskDependency operation payload: {error}"
                        ))
                    })?;
                let entity = SyncEntityRef::pair(
                    SyncEntityKind::TaskTaskDependency,
                    dependency.task_id.clone(),
                    dependency.depends_on_task_id.clone(),
                );
                batch
                    .task_task_dependencies
                    .get_or_insert_with(Vec::new)
                    .push(dependency);
                expanded.push(ExpandedOperation {
                    entity,
                    base_record_revision: operation.base_record_revision,
                });
            }
            "upsertTaskRecurringTaskDependency" => {
                let dependency: SyncTaskRecurringTaskDependencyInput =
                    serde_json::from_value(operation.payload).map_err(|error| {
                        ApiError::Validation(format!(
                            "Invalid upsertTaskRecurringTaskDependency operation payload: {error}"
                        ))
                    })?;
                let entity = SyncEntityRef::pair(
                    SyncEntityKind::TaskRecurringTaskDependency,
                    dependency.task_id.clone(),
                    dependency.recurring_task_id.clone(),
                );
                batch
                    .task_recurring_task_dependencies
                    .get_or_insert_with(Vec::new)
                    .push(dependency);
                expanded.push(ExpandedOperation {
                    entity,
                    base_record_revision: operation.base_record_revision,
                });
            }
            "upsertRecurringTaskTag" => {
                let recurring_task_tag: SyncRecurringTaskTagInput =
                    serde_json::from_value(operation.payload).map_err(|error| {
                        ApiError::Validation(format!(
                            "Invalid upsertRecurringTaskTag operation payload: {error}"
                        ))
                    })?;
                let entity = SyncEntityRef::pair(
                    SyncEntityKind::RecurringTaskTag,
                    recurring_task_tag.recurring_task_id.clone(),
                    recurring_task_tag.tag_id.clone(),
                );
                batch
                    .recurring_task_tags
                    .get_or_insert_with(Vec::new)
                    .push(recurring_task_tag);
                expanded.push(ExpandedOperation {
                    entity,
                    base_record_revision: operation.base_record_revision,
                });
            }
            "upsertReward" => {
                let reward: SyncRewardInput =
                    serde_json::from_value(operation.payload).map_err(|error| {
                        ApiError::Validation(format!(
                            "Invalid upsertReward operation payload: {error}"
                        ))
                    })?;
                let entity = SyncEntityRef::single(SyncEntityKind::Reward, reward.id.clone());
                batch.rewards.get_or_insert_with(Vec::new).push(reward);
                expanded.push(ExpandedOperation {
                    entity,
                    base_record_revision: operation.base_record_revision,
                });
            }
            "upsertRewardTaskDependency" => {
                let dependency: SyncRewardTaskDependencyInput =
                    serde_json::from_value(operation.payload).map_err(|error| {
                        ApiError::Validation(format!(
                            "Invalid upsertRewardTaskDependency operation payload: {error}"
                        ))
                    })?;
                let entity = SyncEntityRef::pair(
                    SyncEntityKind::RewardTaskDependency,
                    dependency.reward_id.clone(),
                    dependency.depends_on_task_id.clone(),
                );
                batch
                    .reward_task_dependencies
                    .get_or_insert_with(Vec::new)
                    .push(dependency);
                expanded.push(ExpandedOperation {
                    entity,
                    base_record_revision: operation.base_record_revision,
                });
            }
            "upsertRewardRecurringTaskDependency" => {
                let dependency: SyncRewardRecurringTaskDependencyInput =
                    serde_json::from_value(operation.payload).map_err(|error| {
                        ApiError::Validation(format!(
                            "Invalid upsertRewardRecurringTaskDependency operation payload: {error}"
                        ))
                    })?;
                let entity = SyncEntityRef::pair(
                    SyncEntityKind::RewardRecurringTaskDependency,
                    dependency.reward_id.clone(),
                    dependency.recurring_task_id.clone(),
                );
                batch
                    .reward_recurring_task_dependencies
                    .get_or_insert_with(Vec::new)
                    .push(dependency);
                expanded.push(ExpandedOperation {
                    entity,
                    base_record_revision: operation.base_record_revision,
                });
            }
            "upsertRewardTag" => {
                let reward_tag: SyncRewardTagInput = serde_json::from_value(operation.payload)
                    .map_err(|error| {
                        ApiError::Validation(format!(
                            "Invalid upsertRewardTag operation payload: {error}"
                        ))
                    })?;
                let entity = SyncEntityRef::pair(
                    SyncEntityKind::RewardTag,
                    reward_tag.reward_id.clone(),
                    reward_tag.tag_id.clone(),
                );
                batch
                    .reward_tags
                    .get_or_insert_with(Vec::new)
                    .push(reward_tag);
                expanded.push(ExpandedOperation {
                    entity,
                    base_record_revision: operation.base_record_revision,
                });
            }
            "updateThemePalettes" => {
                if operation.base_record_revision.is_some() {
                    return Err(ApiError::Validation(
                        "Theme palette operations do not support baseRecordRevision.".to_string(),
                    ));
                }
                let theme_palettes: ThemePalettes = serde_json::from_value(operation.payload)
                    .map_err(|error| {
                        ApiError::Validation(format!(
                            "Invalid updateThemePalettes operation payload: {error}"
                        ))
                    })?;
                batch.theme_palettes = Some(theme_palettes);
            }
            other => {
                return Err(ApiError::Validation(format!(
                    "Unsupported sync operation kind: {other}"
                )));
            }
        }
    }

    Ok((batch, expanded))
}

#[derive(Default)]
struct AcceptedEntityRevisions {
    revisions: BTreeSet<(SyncEntityRef, i64)>,
}

impl AcceptedEntityRevisions {
    fn insert(&mut self, entity: SyncEntityRef, server_revision: i64) {
        self.revisions.insert((entity, server_revision));
    }

    fn contains(&self, entity: &SyncEntityRef, server_revision: i64) -> bool {
        self.revisions.contains(&(entity.clone(), server_revision))
    }
}

struct ProcessedSyncOperationLookup {
    cached_response: Option<SyncResponse>,
    processed_operation_ids: BTreeSet<Uuid>,
    accepted_entity_revisions: AcceptedEntityRevisions,
}

impl ProcessedSyncOperationLookup {
    fn empty() -> Self {
        Self {
            cached_response: None,
            processed_operation_ids: BTreeSet::new(),
            accepted_entity_revisions: AcceptedEntityRevisions::default(),
        }
    }
}

fn collect_accepted_entity_revisions(
    response: &SyncResponse,
    accepted_revision: i64,
) -> AcceptedEntityRevisions {
    let mut revisions = AcceptedEntityRevisions::default();

    for timer in &response.timers {
        if timer.server_revision == accepted_revision {
            revisions.insert(
                SyncEntityRef::single(SyncEntityKind::Timer, timer.id.clone()),
                timer.server_revision,
            );
        }
    }
    for task in &response.tasks {
        if task.server_revision == accepted_revision {
            revisions.insert(
                SyncEntityRef::single(SyncEntityKind::Task, task.id.clone()),
                task.server_revision,
            );
        }
    }
    for recurring_task in &response.recurring_tasks {
        if recurring_task.server_revision == accepted_revision {
            revisions.insert(
                SyncEntityRef::single(SyncEntityKind::RecurringTask, recurring_task.id.clone()),
                recurring_task.server_revision,
            );
        }
    }
    for trade in &response.trades {
        if trade.server_revision == accepted_revision {
            revisions.insert(
                SyncEntityRef::single(SyncEntityKind::Trade, trade.id.clone()),
                trade.server_revision,
            );
        }
    }
    for tag in &response.tags {
        if tag.server_revision == accepted_revision {
            revisions.insert(
                SyncEntityRef::single(SyncEntityKind::Tag, tag.id.clone()),
                tag.server_revision,
            );
        }
    }
    for task_tag in &response.task_tags {
        if task_tag.server_revision == accepted_revision {
            revisions.insert(
                SyncEntityRef::pair(
                    SyncEntityKind::TaskTag,
                    task_tag.task_id.clone(),
                    task_tag.tag_id.clone(),
                ),
                task_tag.server_revision,
            );
        }
    }
    for dependency in &response.task_task_dependencies {
        if dependency.server_revision == accepted_revision {
            revisions.insert(
                SyncEntityRef::pair(
                    SyncEntityKind::TaskTaskDependency,
                    dependency.task_id.clone(),
                    dependency.depends_on_task_id.clone(),
                ),
                dependency.server_revision,
            );
        }
    }
    for dependency in &response.task_recurring_task_dependencies {
        if dependency.server_revision == accepted_revision {
            revisions.insert(
                SyncEntityRef::pair(
                    SyncEntityKind::TaskRecurringTaskDependency,
                    dependency.task_id.clone(),
                    dependency.recurring_task_id.clone(),
                ),
                dependency.server_revision,
            );
        }
    }
    for recurring_task_tag in &response.recurring_task_tags {
        if recurring_task_tag.server_revision == accepted_revision {
            revisions.insert(
                SyncEntityRef::pair(
                    SyncEntityKind::RecurringTaskTag,
                    recurring_task_tag.recurring_task_id.clone(),
                    recurring_task_tag.tag_id.clone(),
                ),
                recurring_task_tag.server_revision,
            );
        }
    }
    for reward in &response.rewards {
        if reward.server_revision == accepted_revision {
            revisions.insert(
                SyncEntityRef::single(SyncEntityKind::Reward, reward.id.clone()),
                reward.server_revision,
            );
        }
    }
    for dependency in &response.reward_task_dependencies {
        if dependency.server_revision == accepted_revision {
            revisions.insert(
                SyncEntityRef::pair(
                    SyncEntityKind::RewardTaskDependency,
                    dependency.reward_id.clone(),
                    dependency.depends_on_task_id.clone(),
                ),
                dependency.server_revision,
            );
        }
    }
    for dependency in &response.reward_recurring_task_dependencies {
        if dependency.server_revision == accepted_revision {
            revisions.insert(
                SyncEntityRef::pair(
                    SyncEntityKind::RewardRecurringTaskDependency,
                    dependency.reward_id.clone(),
                    dependency.recurring_task_id.clone(),
                ),
                dependency.server_revision,
            );
        }
    }
    for reward_tag in &response.reward_tags {
        if reward_tag.server_revision == accepted_revision {
            revisions.insert(
                SyncEntityRef::pair(
                    SyncEntityKind::RewardTag,
                    reward_tag.reward_id.clone(),
                    reward_tag.tag_id.clone(),
                ),
                reward_tag.server_revision,
            );
        }
    }

    revisions
}

async fn load_processed_sync_operations_tx(
    tx: &mut Transaction<'_, Postgres>,
    user_id: Uuid,
    operation_ids: &[Uuid],
) -> Result<ProcessedSyncOperationLookup, ApiError> {
    if operation_ids.is_empty() {
        return Ok(ProcessedSyncOperationLookup::empty());
    }

    let unique_operation_ids: BTreeSet<Uuid> = operation_ids.iter().copied().collect();
    if unique_operation_ids.len() != operation_ids.len() {
        return Err(ApiError::Validation(
            "Sync operation ids must be unique within a request.".to_string(),
        ));
    }

    let rows: Vec<(Uuid, i64, Value)> = sqlx::query_as(
        "SELECT operation_id, revision, response_json
         FROM processed_sync_operations
         WHERE user_id = $1 AND operation_id = ANY($2)",
    )
    .bind(user_id)
    .bind(operation_ids)
    .fetch_all(&mut **tx)
    .await
    .map_err(ApiError::from)?;

    if rows.is_empty() {
        return Ok(ProcessedSyncOperationLookup::empty());
    }

    let Some((_, _, response_json)) = rows.first() else {
        return Ok(ProcessedSyncOperationLookup::empty());
    };
    let all_requested_operations_were_processed = rows.len() == operation_ids.len();
    let rows_have_same_response = rows
        .iter()
        .all(|(_, _, row_json)| row_json == response_json);

    if all_requested_operations_were_processed {
        let response_json = if rows_have_same_response {
            response_json.clone()
        } else {
            rows.iter()
                .max_by_key(|(_, revision, _)| *revision)
                .map(|(_, _, response_json)| response_json.clone())
                .ok_or(ApiError::Internal)?
        };

        return serde_json::from_value(response_json)
            .map(|response| ProcessedSyncOperationLookup {
                cached_response: Some(response),
                processed_operation_ids: unique_operation_ids,
                accepted_entity_revisions: AcceptedEntityRevisions::default(),
            })
            .map_err(|error| internal_error("sync.decode_cached_operation_response", error));
    }

    // A retry can mix one operation the server already committed with a newer
    // sibling edit after the client lost the response. Only rows written by the
    // cached operation's own revision can prove that the sibling is safe to
    // accept without a baseRecordRevision.
    let mut accepted_entity_revisions = AcceptedEntityRevisions::default();
    for (_, revision, row_json) in &rows {
        let response: SyncResponse = serde_json::from_value(row_json.clone())
            .map_err(|error| internal_error("sync.decode_processed_operation_response", error))?;
        accepted_entity_revisions
            .revisions
            .extend(collect_accepted_entity_revisions(&response, *revision).revisions);
    }

    Ok(ProcessedSyncOperationLookup {
        cached_response: None,
        processed_operation_ids: rows
            .into_iter()
            .map(|(operation_id, _, _)| operation_id)
            .collect(),
        accepted_entity_revisions,
    })
}

async fn store_processed_sync_response_tx(
    tx: &mut Transaction<'_, Postgres>,
    user_id: Uuid,
    operation_id: Uuid,
    revision: i64,
    response: &SyncResponse,
) -> Result<(), sqlx::Error> {
    let response_json =
        serde_json::to_value(response).map_err(|error| sqlx::Error::Protocol(error.to_string()))?;
    sqlx::query(
        "INSERT INTO processed_sync_operations (user_id, operation_id, revision, response_json)
         VALUES ($1, $2, $3, $4)
         ON CONFLICT (user_id, operation_id) DO NOTHING",
    )
    .bind(user_id)
    .bind(operation_id)
    .bind(revision)
    .bind(response_json)
    .execute(&mut **tx)
    .await?;
    Ok(())
}

async fn store_processed_sync_batch_response_tx(
    tx: &mut Transaction<'_, Postgres>,
    user_id: Uuid,
    operation_ids: &[Uuid],
    revision: i64,
    response: &SyncResponse,
) -> Result<(), sqlx::Error> {
    for operation_id in operation_ids {
        store_processed_sync_response_tx(tx, user_id, *operation_id, revision, response).await?;
    }
    Ok(())
}

async fn lock_and_advance_user_revision_tx(
    tx: &mut Transaction<'_, Postgres>,
    user_id: Uuid,
) -> Result<i64, sqlx::Error> {
    sqlx::query(
        "INSERT INTO user_sync_state (user_id, revision)
         VALUES ($1, 0)
         ON CONFLICT (user_id) DO NOTHING",
    )
    .bind(user_id)
    .execute(&mut **tx)
    .await?;

    let (revision,): (i64,) = sqlx::query_as(
        "UPDATE user_sync_state
         SET revision = revision + 1
         WHERE user_id = $1
         RETURNING revision",
    )
    .bind(user_id)
    .fetch_one(&mut **tx)
    .await?;

    Ok(revision)
}

async fn load_user_revision_tx(
    tx: &mut Transaction<'_, Postgres>,
    user_id: Uuid,
) -> Result<i64, sqlx::Error> {
    let revision: Option<(i64,)> =
        sqlx::query_as("SELECT revision FROM user_sync_state WHERE user_id = $1")
            .bind(user_id)
            .fetch_optional(&mut **tx)
            .await?;
    Ok(revision.map(|(revision,)| revision).unwrap_or(0))
}

fn parse_entity_uuid(entity_kind: &str, entity_id: &str) -> Result<Uuid, ApiError> {
    entity_id
        .parse::<Uuid>()
        .map_err(|_| ApiError::Validation(format!("Invalid {entity_kind} id format: {entity_id}")))
}

async fn ensure_base_revision_matches_tx(
    tx: &mut Transaction<'_, Postgres>,
    user_id: Uuid,
    operation: &ExpandedOperation,
    accepted_entity_revisions: &AcceptedEntityRevisions,
) -> Result<(), ApiError> {
    let current_revision: Option<i64> = match operation.entity.kind {
        SyncEntityKind::Task => {
            let id = operation.entity.id.parse_single(SyncEntityKind::Task)?;
            sqlx::query_scalar("SELECT server_revision FROM tasks WHERE user_id = $1 AND id = $2")
                .bind(user_id)
                .bind(id)
                .fetch_optional(&mut **tx)
                .await
                .map_err(ApiError::from)?
        }
        SyncEntityKind::RecurringTask => {
            let id = operation
                .entity
                .id
                .parse_single(SyncEntityKind::RecurringTask)?;
            sqlx::query_scalar(
                "SELECT server_revision FROM tasks
                 WHERE user_id = $1 AND id = $2 AND recurring = TRUE",
            )
            .bind(user_id)
            .bind(id)
            .fetch_optional(&mut **tx)
            .await
            .map_err(ApiError::from)?
        }
        SyncEntityKind::Timer => {
            let id = operation.entity.id.parse_single(SyncEntityKind::Timer)?;
            sqlx::query_scalar("SELECT server_revision FROM timers WHERE user_id = $1 AND id = $2")
                .bind(user_id)
                .bind(id)
                .fetch_optional(&mut **tx)
                .await
                .map_err(ApiError::from)?
        }
        SyncEntityKind::Trade => {
            let id = operation.entity.id.parse_single(SyncEntityKind::Trade)?;
            sqlx::query_scalar("SELECT server_revision FROM trades WHERE user_id = $1 AND id = $2")
                .bind(user_id)
                .bind(id)
                .fetch_optional(&mut **tx)
                .await
                .map_err(ApiError::from)?
        }
        SyncEntityKind::Tag => {
            let id = operation.entity.id.parse_single(SyncEntityKind::Tag)?;
            sqlx::query_scalar("SELECT server_revision FROM tags WHERE user_id = $1 AND id = $2")
                .bind(user_id)
                .bind(id)
                .fetch_optional(&mut **tx)
                .await
                .map_err(ApiError::from)?
        }
        SyncEntityKind::TaskTag => {
            let (task_id, tag_id) =
                operation
                    .entity
                    .id
                    .parse_pair(SyncEntityKind::TaskTag, "task", "tag")?;
            sqlx::query_scalar(
                "SELECT tt.server_revision
                 FROM task_tags tt
                 JOIN tasks task ON task.id = tt.task_id
                 JOIN tags tag ON tag.id = tt.tag_id
                 WHERE task.user_id = $1 AND tag.user_id = $1 AND tt.task_id = $2 AND tt.tag_id = $3",
            )
            .bind(user_id)
            .bind(task_id)
            .bind(tag_id)
            .fetch_optional(&mut **tx)
            .await
            .map_err(ApiError::from)?
        }
        SyncEntityKind::RecurringTaskTag => {
            let (recurring_task_id, tag_id) = operation.entity.id.parse_pair(
                SyncEntityKind::RecurringTaskTag,
                "recurringTask",
                "tag",
            )?;
            sqlx::query_scalar(
                "SELECT ht.server_revision
                 FROM recurring_task_tags ht
                 JOIN tasks recurring_task ON recurring_task.id = ht.recurring_task_id
                 JOIN tags tag ON tag.id = ht.tag_id
                 WHERE recurring_task.user_id = $1 AND tag.user_id = $1 AND ht.recurring_task_id = $2 AND ht.tag_id = $3",
            )
            .bind(user_id)
            .bind(recurring_task_id)
            .bind(tag_id)
            .fetch_optional(&mut **tx)
            .await
            .map_err(ApiError::from)?
        }
        SyncEntityKind::RewardTag => {
            let (reward_id, tag_id) =
                operation
                    .entity
                    .id
                    .parse_pair(SyncEntityKind::RewardTag, "reward", "tag")?;
            sqlx::query_scalar(
                "SELECT rt.server_revision
                 FROM reward_tags rt
                 JOIN rewards reward ON reward.id = rt.reward_id
                 JOIN tags tag ON tag.id = rt.tag_id
                 WHERE reward.user_id = $1 AND tag.user_id = $1 AND rt.reward_id = $2 AND rt.tag_id = $3",
            )
            .bind(user_id)
            .bind(reward_id)
            .bind(tag_id)
            .fetch_optional(&mut **tx)
            .await
            .map_err(ApiError::from)?
        }
        SyncEntityKind::TaskTaskDependency => {
            let (task_id, depends_on_task_id) = operation.entity.id.parse_pair(
                SyncEntityKind::TaskTaskDependency,
                "task",
                "dependency task",
            )?;
            sqlx::query_scalar(
                "SELECT ttd.server_revision
                 FROM task_task_dependencies ttd
                 JOIN tasks task ON task.id = ttd.task_id
                 JOIN tasks dependency ON dependency.id = ttd.depends_on_task_id
                 WHERE task.user_id = $1 AND dependency.user_id = $1
                   AND ttd.task_id = $2 AND ttd.depends_on_task_id = $3",
            )
            .bind(user_id)
            .bind(task_id)
            .bind(depends_on_task_id)
            .fetch_optional(&mut **tx)
            .await
            .map_err(ApiError::from)?
        }
        SyncEntityKind::TaskRecurringTaskDependency => {
            let (task_id, recurring_task_id) = operation.entity.id.parse_pair(
                SyncEntityKind::TaskRecurringTaskDependency,
                "task",
                "recurringTask",
            )?;
            sqlx::query_scalar(
                "SELECT thd.server_revision
                 FROM task_recurring_task_dependencies thd
                 JOIN tasks task ON task.id = thd.task_id
                 JOIN tasks recurring_task ON recurring_task.id = thd.recurring_task_id
                 WHERE task.user_id = $1 AND recurring_task.user_id = $1
                   AND thd.task_id = $2 AND thd.recurring_task_id = $3",
            )
            .bind(user_id)
            .bind(task_id)
            .bind(recurring_task_id)
            .fetch_optional(&mut **tx)
            .await
            .map_err(ApiError::from)?
        }
        SyncEntityKind::Reward => {
            let id = operation.entity.id.parse_single(SyncEntityKind::Reward)?;
            sqlx::query_scalar("SELECT server_revision FROM rewards WHERE user_id = $1 AND id = $2")
                .bind(user_id)
                .bind(id)
                .fetch_optional(&mut **tx)
                .await
                .map_err(ApiError::from)?
        }
        SyncEntityKind::RewardTaskDependency => {
            let (reward_id, depends_on_task_id) = operation.entity.id.parse_pair(
                SyncEntityKind::RewardTaskDependency,
                "reward",
                "dependency task",
            )?;
            sqlx::query_scalar(
                "SELECT rtd.server_revision
                 FROM reward_task_dependencies rtd
                 JOIN rewards reward ON reward.id = rtd.reward_id
                 JOIN tasks dependency ON dependency.id = rtd.depends_on_task_id
                 WHERE reward.user_id = $1 AND dependency.user_id = $1
                   AND rtd.reward_id = $2 AND rtd.depends_on_task_id = $3",
            )
            .bind(user_id)
            .bind(reward_id)
            .bind(depends_on_task_id)
            .fetch_optional(&mut **tx)
            .await
            .map_err(ApiError::from)?
        }
        SyncEntityKind::RewardRecurringTaskDependency => {
            let (reward_id, recurring_task_id) = operation.entity.id.parse_pair(
                SyncEntityKind::RewardRecurringTaskDependency,
                "reward",
                "recurringTask",
            )?;
            sqlx::query_scalar(
                "SELECT rhd.server_revision
                 FROM reward_recurring_task_dependencies rhd
                 JOIN rewards reward ON reward.id = rhd.reward_id
                 JOIN tasks recurring_task ON recurring_task.id = rhd.recurring_task_id
                 WHERE reward.user_id = $1 AND recurring_task.user_id = $1
                   AND rhd.reward_id = $2 AND rhd.recurring_task_id = $3",
            )
            .bind(user_id)
            .bind(reward_id)
            .bind(recurring_task_id)
            .fetch_optional(&mut **tx)
            .await
            .map_err(ApiError::from)?
        }
    };

    let server_still_matches_missed_response = current_revision
        .is_some_and(|revision| accepted_entity_revisions.contains(&operation.entity, revision));

    match (operation.base_record_revision, current_revision) {
        (None, None) => Ok(()),
        (Some(base), Some(current)) if base == current => Ok(()),
        (_, Some(_)) if server_still_matches_missed_response => Ok(()),
        (None, Some(_)) => Err(ApiError::Conflict(format!(
            "{} {} already exists; send a baseRecordRevision to update it.",
            operation.entity.kind, operation.entity.id
        ))),
        (Some(_), None) => Err(ApiError::Conflict(format!(
            "{} {} no longer exists on the server.",
            operation.entity.kind, operation.entity.id
        ))),
        (Some(base), Some(current)) => Err(ApiError::Conflict(format!(
            "{} {} has changed since base revision {}. Current revision is {}.",
            operation.entity.kind, operation.entity.id, base, current
        ))),
    }
}

// ============================================================================
// Handlers
// ============================================================================

/// GET /api/v1/sync - Pull changes since timestamp
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

    let mut tx = app
        .database
        .begin_transaction()
        .await
        .map_err(|e| internal_error("sync.begin_snapshot_transaction", e))?;

    sqlx::query("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY")
        .execute(&mut *tx)
        .await
        .map_err(|e| internal_error("sync.configure_snapshot_transaction", e))?;

    let response_cursor = load_snapshot_cursor(&mut tx, user.user_id)
        .await
        .map_err(|e| internal_error("sync.capture_snapshot_cursor", e))?;

    let timer_rows = load_timers_for_sync(
        &mut tx,
        user.user_id,
        params.since,
        requested_cursor.as_ref(),
    )
    .await
    .map_err(|e| internal_error("sync.load_timers", e))?;

    let recurring_task_rows = load_recurring_tasks_for_sync(
        &mut tx,
        user.user_id,
        params.since,
        requested_cursor.as_ref(),
    )
    .await
    .map_err(|e| internal_error("sync.load_recurring_tasks", e))?;

    let task_rows = load_tasks_for_sync(
        &mut tx,
        user.user_id,
        params.since,
        requested_cursor.as_ref(),
    )
    .await
    .map_err(|e| internal_error("sync.load_tasks", e))?;

    let trade_rows = load_trades_for_sync(
        &mut tx,
        user.user_id,
        params.since,
        requested_cursor.as_ref(),
    )
    .await
    .map_err(|e| internal_error("sync.load_trades", e))?;

    let trade_balance = load_balance_for_sync(&mut tx, user.user_id)
        .await
        .map_err(|e| internal_error("sync.load_balance", e))?;

    let profile_row = load_profile_for_sync(&mut tx, user.user_id)
        .await
        .map_err(|e| internal_error("sync.load_profile", e))?;

    let tag_rows = load_tags_for_sync(
        &mut tx,
        user.user_id,
        params.since,
        requested_cursor.as_ref(),
    )
    .await
    .map_err(|e| internal_error("sync.load_tags", e))?;

    let task_tag_rows = load_task_tags_for_sync(
        &mut tx,
        user.user_id,
        params.since,
        requested_cursor.as_ref(),
    )
    .await
    .map_err(|e| internal_error("sync.load_task_tags", e))?;

    let task_task_dependency_rows = load_task_task_dependencies_for_sync(
        &mut tx,
        user.user_id,
        params.since,
        requested_cursor.as_ref(),
    )
    .await
    .map_err(|e| internal_error("sync.load_task_task_dependencies", e))?;

    let task_recurring_task_dependency_rows = load_task_recurring_task_dependencies_for_sync(
        &mut tx,
        user.user_id,
        params.since,
        requested_cursor.as_ref(),
    )
    .await
    .map_err(|e| internal_error("sync.load_task_recurring_task_dependencies", e))?;

    let reward_task_dependency_rows = load_reward_task_dependencies_for_sync(
        &mut tx,
        user.user_id,
        params.since,
        requested_cursor.as_ref(),
    )
    .await
    .map_err(|e| internal_error("sync.load_reward_task_dependencies", e))?;

    let reward_recurring_task_dependency_rows = load_reward_recurring_task_dependencies_for_sync(
        &mut tx,
        user.user_id,
        params.since,
        requested_cursor.as_ref(),
    )
    .await
    .map_err(|e| internal_error("sync.load_reward_recurring_task_dependencies", e))?;

    let recurring_task_tag_rows = load_recurring_task_tags_for_sync(
        &mut tx,
        user.user_id,
        params.since,
        requested_cursor.as_ref(),
    )
    .await
    .map_err(|e| internal_error("sync.load_recurring_task_tags", e))?;

    let reward_rows = load_rewards_for_sync(
        &mut tx,
        user.user_id,
        params.since,
        requested_cursor.as_ref(),
    )
    .await
    .map_err(|e| internal_error("sync.load_rewards", e))?;

    let reward_tag_rows = load_reward_tags_for_sync(
        &mut tx,
        user.user_id,
        params.since,
        requested_cursor.as_ref(),
    )
    .await
    .map_err(|e| internal_error("sync.load_reward_tags", e))?;

    let timers: Vec<TimerOutput> = timer_rows.into_iter().map(timer_output_from_row).collect();

    let recurring_tasks: Vec<RecurringTaskOutput> = recurring_task_rows
        .into_iter()
        .map(recurring_task_output_from_row)
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
            server_revision: row.server_revision,
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
            server_revision: row.server_revision,
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
            server_revision: row.server_revision,
        })
        .collect();

    let task_recurring_task_dependencies: Vec<TaskRecurringTaskDependencyOutput> =
        task_recurring_task_dependency_rows
            .into_iter()
            .map(|row| TaskRecurringTaskDependencyOutput {
                task_id: row.task_id.to_string(),
                recurring_task_id: row.recurring_task_id.to_string(),
                required_completions: row.required_completions,
                baseline_completion_count: row.baseline_completion_count,
                created_at: row.created_at,
                updated_at: row.updated_at,
                deleted_at: row.deleted_at,
                server_revision: row.server_revision,
            })
            .collect();

    let recurring_task_tags: Vec<RecurringTaskTagOutput> = recurring_task_tag_rows
        .into_iter()
        .map(|row| RecurringTaskTagOutput {
            recurring_task_id: row.recurring_task_id.to_string(),
            tag_id: row.tag_id.to_string(),
            created_at: row.created_at,
            updated_at: row.updated_at,
            deleted_at: row.deleted_at,
            server_revision: row.server_revision,
        })
        .collect();

    let rewards: Vec<RewardOutput> = reward_rows
        .into_iter()
        .map(reward_output_from_row)
        .collect();

    let reward_task_dependencies: Vec<RewardTaskDependencyOutput> = reward_task_dependency_rows
        .into_iter()
        .map(|row| RewardTaskDependencyOutput {
            reward_id: row.reward_id.to_string(),
            depends_on_task_id: row.depends_on_task_id.to_string(),
            created_at: row.created_at,
            updated_at: row.updated_at,
            deleted_at: row.deleted_at,
            server_revision: row.server_revision,
        })
        .collect();

    let reward_recurring_task_dependencies: Vec<RewardRecurringTaskDependencyOutput> =
        reward_recurring_task_dependency_rows
            .into_iter()
            .map(|row| RewardRecurringTaskDependencyOutput {
                reward_id: row.reward_id.to_string(),
                recurring_task_id: row.recurring_task_id.to_string(),
                required_completions: row.required_completions,
                baseline_completion_count: row.baseline_completion_count,
                created_at: row.created_at,
                updated_at: row.updated_at,
                deleted_at: row.deleted_at,
                server_revision: row.server_revision,
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
            server_revision: row.server_revision,
        })
        .collect();

    let server_time = Utc::now().naive_utc();
    let is_premium = profile_is_entitled(&profile_row);
    let theme_palettes = theme_palettes_from_profile(&profile_row);
    let server_cursor = response_cursor
        .encode()
        .map_err(|e| internal_error("sync.encode_pull_cursor", e))?;

    tx.commit()
        .await
        .map_err(|e| internal_error("sync.commit_snapshot_transaction", e))?;

    Ok(Json(SyncResponse {
        timers,
        tasks,
        recurring_tasks,
        trades,
        tags,
        task_tags,
        task_task_dependencies,
        task_recurring_task_dependencies,
        recurring_task_tags,
        rewards,
        reward_task_dependencies,
        reward_recurring_task_dependencies,
        reward_tags,
        balance: BalanceOutput {
            point_balance: trade_balance,
        },
        server_cursor,
        server_time,
        email: profile_row.email,
        is_premium,
        theme_palettes,
    }))
}

/// POST /api/v1/sync - Push changes (atomic batch upsert)
pub async fn post_sync(
    State(app): State<App>,
    Extension(user): Extension<AuthenticatedUser>,
    Json(mut input): Json<SyncPushRequest>,
) -> Result<Response, ApiError> {
    let requested_base_cursor = input
        .base_cursor
        .as_deref()
        .map(SyncCursor::decode)
        .transpose()
        .map_err(|_| ApiError::Validation("Invalid sync cursor".to_string()))?;

    if input.operations.is_empty() {
        return Err(ApiError::Validation(
            "Sync push operations must include at least one operation.".to_string(),
        ));
    }

    let operation_ids: Vec<Uuid> = input
        .operations
        .iter()
        .map(|operation| operation.operation_id)
        .collect();

    let mut processed_operation_lookup = ProcessedSyncOperationLookup::empty();
    if !operation_ids.is_empty() {
        let mut lookup_tx = app
            .database
            .begin_transaction()
            .await
            .map_err(|e| internal_error("sync.begin_processed_operation_lookup", e))?;
        processed_operation_lookup =
            load_processed_sync_operations_tx(&mut lookup_tx, user.user_id, &operation_ids).await?;
        if let Some(response) = processed_operation_lookup.cached_response.take() {
            lookup_tx
                .commit()
                .await
                .map_err(|e| internal_error("sync.commit_processed_operation_lookup", e))?;
            return Ok(Json(response).into_response());
        }
        lookup_tx
            .rollback()
            .await
            .map_err(|e| internal_error("sync.rollback_processed_operation_lookup", e))?;
    }

    input.remove_processed_operations(&processed_operation_lookup.processed_operation_ids);

    let (input, expanded_operations) = expand_operations(input.operations)?;

    // Begin transaction for atomicity
    let mut tx = app
        .database
        .begin_transaction()
        .await
        .map_err(|e| internal_error("sync.begin_push_transaction", e))?;

    let server_revision = lock_and_advance_user_revision_tx(&mut tx, user.user_id)
        .await
        .map_err(|e| internal_error("sync.allocate_revision", e))?;

    for operation in &expanded_operations {
        ensure_base_revision_matches_tx(
            &mut tx,
            user.user_id,
            operation,
            &processed_operation_lookup.accepted_entity_revisions,
        )
        .await?;
    }

    let profile_row_for_validation = load_profile_for_sync(&mut tx, user.user_id)
        .await
        .map_err(|e| internal_error("sync.load_profile_for_validation", e))?;
    let has_premium_access = profile_is_entitled(&profile_row_for_validation);

    let mut result_timers = Vec::new();
    let mut result_recurring_tasks = Vec::new();
    let mut result_tasks = Vec::new();
    let mut result_trades = Vec::new();
    let mut result_tags = Vec::new();
    let mut result_task_tags = Vec::new();
    let mut result_task_task_dependencies = Vec::new();
    let mut result_task_recurring_task_dependencies = Vec::new();
    let mut result_recurring_task_tags = Vec::new();
    let mut result_rewards = Vec::new();
    let mut result_reward_task_dependencies = Vec::new();
    let mut result_reward_recurring_task_dependencies = Vec::new();
    let mut result_reward_tags = Vec::new();
    let mut completed_task_ids = Vec::new();
    let mut deleted_tasks = Vec::new();
    let mut deleted_rewards = Vec::new();
    let mut deleted_recurring_task_ids = Vec::new();
    let mut touched_task_ids = BTreeSet::new();

    if let Some(timers) = input.timers {
        for timer_input in timers {
            let timer_id = timer_input.id.parse::<Uuid>().map_err(|_| {
                ApiError::Validation(format!("Invalid timer id format: {}", timer_input.id))
            })?;

            validate_timer_intervals(&timer_input.name, &timer_input.intervals)?;
            let intervals = serde_json::to_value(&timer_input.intervals)
                .map_err(|e| internal_error("sync.encode_timer_intervals", e))?;

            let upsert_opts = database::UpsertTimerOptions {
                id: timer_id,
                name: timer_input.name,
                intervals,
                created_at: timer_input.created_at,
                deleted_at: timer_input.deleted_at,
                server_revision,
            };

            let timer_row = Database::upsert_timer_tx(&mut tx, user.user_id, &upsert_opts)
                .await
                .map_err(|e| map_owned_entity_upsert_error(e, "Timer"))?;

            result_timers.push(timer_output_from_row(timer_row));
        }
    }

    // Process recurring_tasks first (trades may reference these)
    if let Some(recurring_tasks) = input.recurring_tasks {
        for recurring_task_input in recurring_tasks {
            // Validate recurringTask ID is a valid UUID
            let recurring_task_id = recurring_task_input.id.parse::<Uuid>().map_err(|_| {
                ApiError::Validation(format!(
                    "Invalid recurringTask id format: {}",
                    recurring_task_input.id
                ))
            })?;

            validate_recurring_task_fields(
                &recurring_task_input.name,
                &recurring_task_input.description,
                recurring_task_input.min_daily_frequency,
                recurring_task_input.lockout_duration_seconds,
                recurring_task_input.base_price,
            )?;
            validate_timer_assignment(
                "RecurringTask",
                recurring_task_input.timer_mode.as_deref(),
                recurring_task_input.timer_id.as_deref(),
            )?;
            let timer_id = parse_and_validate_timer_id(
                &mut tx,
                user.user_id,
                recurring_task_input.timer_mode.as_deref(),
                recurring_task_input.timer_id.as_deref(),
            )
            .await?;

            let upsert_opts = database::UpsertRecurringTaskOptions {
                id: recurring_task_id,
                name: recurring_task_input.name,
                description: recurring_task_input.description,
                created_at: recurring_task_input.created_at,
                deleted_at: recurring_task_input.deleted_at,
                min_daily_frequency: recurring_task_input.min_daily_frequency,
                lockout_duration_seconds: recurring_task_input.lockout_duration_seconds,
                base_price: recurring_task_input.base_price,
                pinned: recurring_task_input.pinned,
                hidden: recurring_task_input.hidden,
                timer_mode: recurring_task_input.timer_mode,
                timer_id,
                server_revision,
            };

            if recurring_task_input.deleted_at.is_some() {
                deleted_recurring_task_ids.push(recurring_task_id);
            }

            let recurring_task_row =
                Database::upsert_recurring_task_tx(&mut tx, user.user_id, &upsert_opts)
                    .await
                    .map_err(|e| map_owned_entity_upsert_error(e, "RecurringTask"))?;

            result_recurring_tasks.push(recurring_task_output_from_row(recurring_task_row));
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
                task_input.base_price,
            )?;
            validate_timer_assignment(
                "Task",
                task_input.timer_mode.as_deref(),
                task_input.timer_id.as_deref(),
            )?;
            let timer_id = parse_and_validate_timer_id(
                &mut tx,
                user.user_id,
                task_input.timer_mode.as_deref(),
                task_input.timer_id.as_deref(),
            )
            .await?;

            let upsert_opts = database::UpsertTaskOptions {
                id: task_id,
                name: task_input.name,
                description: task_input.description,
                created_at: task_input.created_at,
                deleted_at: task_input.deleted_at,
                base_price: task_input.base_price,
                due_date: task_input.due_date,
                pinned: task_input.pinned,
                hidden: task_input.hidden,
                timer_mode: task_input.timer_mode,
                timer_id,
                server_revision,
            };

            if let Some(deleted_at) = task_input.deleted_at {
                deleted_tasks.push((task_id, deleted_at));
            }

            let task_row = Database::upsert_task_tx(&mut tx, user.user_id, &upsert_opts)
                .await
                .map_err(|e| map_owned_entity_upsert_error(e, "Task"))?;

            result_tasks.push(task_output_from_row(task_row));
        }
    }

    // Process task dependencies third (they reference tasks and recurring_tasks created above)
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
                server_revision,
            };

            let dependency_row =
                Database::upsert_task_task_dependency_tx(&mut tx, user.user_id, &upsert_opts)
                    .await
                    .map_err(|e| {
                        warn!(
                            operation = "sync.upsert_task_task_dependency",
                            task_id = %task_id,
                            depends_on_task_id = %depends_on_task_id,
                            error = ?e,
                            "sync relationship rejected"
                        );
                        ApiError::Validation(format!(
                    "Invalid task dependency reference for task_id: {}, depends_on_task_id: {}",
                    task_id, depends_on_task_id
                ))
                    })?;

            upsert_task_task_dependency_output(&mut result_task_task_dependencies, dependency_row);
        }
    }

    if let Some(task_recurring_task_dependencies) = input.task_recurring_task_dependencies {
        for dependency_input in task_recurring_task_dependencies {
            if dependency_input.required_completions <= 0 {
                return Err(ApiError::Validation(
                    "RecurringTask dependencies must require at least one completion.".to_string(),
                ));
            }

            if dependency_input.baseline_completion_count < 0 {
                return Err(ApiError::Validation(
                    "RecurringTask dependency baseline completion counts cannot be negative."
                        .to_string(),
                ));
            }

            let task_id = dependency_input.task_id.parse::<Uuid>().map_err(|_| {
                ApiError::Validation(format!(
                    "Invalid task_id format: {}",
                    dependency_input.task_id
                ))
            })?;

            let recurring_task_id =
                dependency_input
                    .recurring_task_id
                    .parse::<Uuid>()
                    .map_err(|_| {
                        ApiError::Validation(format!(
                            "Invalid recurring_task_id format: {}",
                            dependency_input.recurring_task_id
                        ))
                    })?;

            let upsert_opts = database::UpsertTaskRecurringTaskDependencyOptions {
                task_id,
                recurring_task_id,
                required_completions: dependency_input.required_completions,
                baseline_completion_count: dependency_input.baseline_completion_count,
                created_at: dependency_input.created_at,
                deleted_at: dependency_input.deleted_at,
                server_revision,
            };

            let dependency_row =
                Database::upsert_task_recurring_task_dependency_tx(&mut tx, user.user_id, &upsert_opts)
                    .await
                    .map_err(|e| {
                        warn!(
                            operation = "sync.upsert_task_recurring_task_dependency",
                            task_id = %task_id,
                            recurring_task_id = %recurring_task_id,
                            error = ?e,
                            "sync relationship rejected"
                        );
                        ApiError::Validation(format!(
                            "Invalid task or recurringTask reference for task_id: {}, recurring_task_id: {}",
                            task_id, recurring_task_id
                        ))
                    })?;

            upsert_task_recurring_task_dependency_output(
                &mut result_task_recurring_task_dependencies,
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
                reward_input.recurring,
                reward_input.max_daily_frequency,
                reward_input.lockout_duration_seconds,
                reward_input.base_price,
            )?;
            validate_timer_assignment(
                "Reward",
                reward_input.timer_mode.as_deref(),
                reward_input.timer_id.as_deref(),
            )?;
            let timer_id = parse_and_validate_timer_id(
                &mut tx,
                user.user_id,
                reward_input.timer_mode.as_deref(),
                reward_input.timer_id.as_deref(),
            )
            .await?;

            let upsert_opts = database::UpsertRewardOptions {
                id: reward_id,
                recurring: reward_input.recurring,
                name: reward_input.name,
                description: reward_input.description,
                created_at: reward_input.created_at,
                deleted_at: reward_input.deleted_at,
                max_daily_frequency: reward_input.max_daily_frequency,
                lockout_duration_seconds: reward_input.lockout_duration_seconds,
                base_price: reward_input.base_price,
                pinned: reward_input.pinned,
                hidden: reward_input.hidden,
                timer_mode: reward_input.timer_mode,
                timer_id,
                server_revision,
            };

            if let Some(deleted_at) = reward_input.deleted_at {
                deleted_rewards.push((reward_id, deleted_at));
            }

            let reward_row = Database::upsert_reward_tx(&mut tx, user.user_id, &upsert_opts)
                .await
                .map_err(|e| map_owned_entity_upsert_error(e, "Reward"))?;

            result_rewards.push(reward_output_from_row(reward_row));
        }
    }

    if let Some(reward_task_dependencies) = input.reward_task_dependencies {
        for dependency_input in reward_task_dependencies {
            let reward_id = dependency_input.reward_id.parse::<Uuid>().map_err(|_| {
                ApiError::Validation(format!(
                    "Invalid reward_id format: {}",
                    dependency_input.reward_id
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

            let upsert_opts = database::UpsertRewardTaskDependencyOptions {
                reward_id,
                depends_on_task_id,
                created_at: dependency_input.created_at,
                deleted_at: dependency_input.deleted_at,
                server_revision,
            };

            let dependency_row =
                Database::upsert_reward_task_dependency_tx(&mut tx, user.user_id, &upsert_opts)
                    .await
                    .map_err(|e| {
                        warn!(
                            operation = "sync.upsert_reward_task_dependency",
                            reward_id = %reward_id,
                            depends_on_task_id = %depends_on_task_id,
                            error = ?e,
                            "sync relationship rejected"
                        );
                        ApiError::Validation(format!(
                    "Invalid reward dependency reference for reward_id: {}, depends_on_task_id: {}",
                    reward_id, depends_on_task_id
                ))
                    })?;

            upsert_reward_task_dependency_output(
                &mut result_reward_task_dependencies,
                dependency_row,
            );
        }
    }

    if let Some(reward_recurring_task_dependencies) = input.reward_recurring_task_dependencies {
        for dependency_input in reward_recurring_task_dependencies {
            if dependency_input.required_completions <= 0 {
                return Err(ApiError::Validation(
                    "RecurringTask dependencies must require at least one completion.".to_string(),
                ));
            }

            if dependency_input.baseline_completion_count < 0 {
                return Err(ApiError::Validation(
                    "RecurringTask dependency baseline completion counts cannot be negative."
                        .to_string(),
                ));
            }

            let reward_id = dependency_input.reward_id.parse::<Uuid>().map_err(|_| {
                ApiError::Validation(format!(
                    "Invalid reward_id format: {}",
                    dependency_input.reward_id
                ))
            })?;

            let recurring_task_id =
                dependency_input
                    .recurring_task_id
                    .parse::<Uuid>()
                    .map_err(|_| {
                        ApiError::Validation(format!(
                            "Invalid recurring_task_id format: {}",
                            dependency_input.recurring_task_id
                        ))
                    })?;

            let upsert_opts = database::UpsertRewardRecurringTaskDependencyOptions {
                reward_id,
                recurring_task_id,
                required_completions: dependency_input.required_completions,
                baseline_completion_count: dependency_input.baseline_completion_count,
                created_at: dependency_input.created_at,
                deleted_at: dependency_input.deleted_at,
                server_revision,
            };

            let dependency_row =
                Database::upsert_reward_recurring_task_dependency_tx(&mut tx, user.user_id, &upsert_opts)
                    .await
                    .map_err(|e| {
                        warn!(
                            operation = "sync.upsert_reward_recurring_task_dependency",
                            reward_id = %reward_id,
                            recurring_task_id = %recurring_task_id,
                            error = ?e,
                            "sync relationship rejected"
                        );
                        ApiError::Validation(format!(
                            "Invalid reward or recurringTask reference for reward_id: {}, recurring_task_id: {}",
                            reward_id, recurring_task_id
                        ))
                    })?;

            upsert_reward_recurring_task_dependency_output(
                &mut result_reward_recurring_task_dependencies,
                dependency_row,
            );
        }
    }

    // Process trades fifth (they may reference tasks, recurring_tasks, or rewards created above)
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

            // Validate recurring_task_id if provided
            let recurring_task_id =
                if let Some(recurring_task_id_str) = &trade_input.recurring_task_id {
                    Some(recurring_task_id_str.parse::<Uuid>().map_err(|_| {
                        ApiError::Validation(format!(
                            "Invalid recurring_task_id format: {}",
                            recurring_task_id_str
                        ))
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

            validate_adjustment_multiplier(
                "one_time_adjustment_multiplier",
                trade_input.one_time_adjustment_multiplier,
            )?;

            let upsert_opts = database::UpsertTradeOptions {
                id: trade_id,
                task_id,
                recurring_task_id,
                reward_id,
                source_name: trade_input.source_name,
                amount: trade_input.amount,
                vault_amount_micro: trade_input.vault_amount_micro,
                adjustment_base_amount: trade_input.adjustment_base_amount,
                one_time_adjustment_multiplier: trade_input.one_time_adjustment_multiplier,
                trade_kind: trade_input.trade_kind,
                vault_interest_hour: trade_input.vault_interest_hour,
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
                server_revision,
            };

            let is_existing_active_reward_purchase = if has_premium_access
                && upsert_opts.reward_id.is_some()
                && upsert_opts.refunds_trade_id.is_none()
                && upsert_opts.deleted_at.is_none()
            {
                Database::active_reward_purchase_trade_exists_tx(
                    &mut tx,
                    user.user_id,
                    upsert_opts.id,
                )
                .await
                .map_err(|e| internal_error("sync.check_existing_reward_purchase_trade", e))?
            } else {
                false
            };

            if let Some(task_id) = upsert_opts.task_id {
                if upsert_opts.refunds_trade_id.is_none() && upsert_opts.deleted_at.is_none() {
                    completed_task_ids.push(task_id);
                }
            }

            if let Some(reward_id) = upsert_opts.reward_id {
                if has_premium_access
                    && upsert_opts.refunds_trade_id.is_none()
                    && upsert_opts.deleted_at.is_none()
                    && !is_existing_active_reward_purchase
                {
                    let has_incomplete_dependencies =
                        Database::reward_has_incomplete_dependencies_tx(
                            &mut tx,
                            user.user_id,
                            reward_id,
                        )
                        .await
                        .map_err(|e| {
                            internal_error("sync.validate_reward_purchase_dependencies", e)
                        })?;

                    if has_incomplete_dependencies {
                        return Err(ApiError::Validation(
                            "Reward dependencies must be complete before this reward can be purchased."
                                .to_string(),
                        ));
                    }
                }
            }

            let trade_row = Database::upsert_trade_tx(&mut tx, user.user_id, &upsert_opts)
                .await
                .map_err(|e| map_trade_upsert_error(e, upsert_opts.refunds_trade_id))?;

            if let Some(reward_id) = upsert_opts.reward_id {
                if has_premium_access
                    && upsert_opts.refunds_trade_id.is_none()
                    && upsert_opts.deleted_at.is_none()
                    && !is_existing_active_reward_purchase
                {
                    let reset_dependencies = Database::reset_reward_recurring_task_dependencies_tx(
                        &mut tx,
                        user.user_id,
                        reward_id,
                        server_revision,
                    )
                    .await
                    .map_err(|e| {
                        internal_error("sync.reset_reward_recurring_task_dependencies", e)
                    })?;

                    for dependency_row in reset_dependencies {
                        upsert_reward_recurring_task_dependency_output(
                            &mut result_reward_recurring_task_dependencies,
                            dependency_row,
                        );
                    }
                }
            }

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
            if !(1..=100).contains(&name_len) {
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
                server_revision,
            };

            let tag_row = Database::upsert_tag_tx(&mut tx, user.user_id, &upsert_opts)
                .await
                .map_err(|e| map_owned_entity_upsert_error(e, "Tag"))?;

            result_tags.push(tag_output_from_row(tag_row));
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
                server_revision,
            };

            let task_tag_row = Database::upsert_task_tag_tx(&mut tx, user.user_id, &upsert_opts)
                .await
                .map_err(|e| {
                    warn!(
                        operation = "sync.upsert_task_tag",
                        task_id = %task_id,
                        tag_id = %tag_id,
                        error = ?e,
                        "sync tag relationship rejected"
                    );
                    ApiError::Validation(format!(
                        "Invalid task or tag reference for task_id: {}, tag_id: {}",
                        task_id, tag_id
                    ))
                })?;

            result_task_tags.push(task_tag_output_from_row(task_tag_row));
        }
    }

    // Process recurring_task_tags eighth (they reference recurring_tasks and tags)
    if let Some(recurring_task_tags) = input.recurring_task_tags {
        for recurring_task_tag_input in recurring_task_tags {
            // Validate recurring_task_id is a valid UUID
            let recurring_task_id = recurring_task_tag_input
                .recurring_task_id
                .parse::<Uuid>()
                .map_err(|_| {
                    ApiError::Validation(format!(
                        "Invalid recurring_task_id format: {}",
                        recurring_task_tag_input.recurring_task_id
                    ))
                })?;

            // Validate tag_id is a valid UUID
            let tag_id = recurring_task_tag_input
                .tag_id
                .parse::<Uuid>()
                .map_err(|_| {
                    ApiError::Validation(format!(
                        "Invalid tag_id format: {}",
                        recurring_task_tag_input.tag_id
                    ))
                })?;

            let upsert_opts = database::UpsertRecurringTaskTagOptions {
                recurring_task_id,
                tag_id,
                created_at: recurring_task_tag_input.created_at,
                deleted_at: recurring_task_tag_input.deleted_at,
                server_revision,
            };

            let recurring_task_tag_row =
                Database::upsert_recurring_task_tag_tx(&mut tx, user.user_id, &upsert_opts)
                    .await
                    .map_err(|e| {
                        warn!(
                            operation = "sync.upsert_recurring_task_tag",
                            recurring_task_id = %recurring_task_id,
                            tag_id = %tag_id,
                            error = ?e,
                            "sync tag relationship rejected"
                        );
                        ApiError::Validation(format!(
                    "Invalid recurringTask or tag reference for recurring_task_id: {}, tag_id: {}",
                    recurring_task_id, tag_id
                ))
                    })?;

            result_recurring_task_tags
                .push(recurring_task_tag_output_from_row(recurring_task_tag_row));
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
                server_revision,
            };

            let reward_tag_row =
                Database::upsert_reward_tag_tx(&mut tx, user.user_id, &upsert_opts)
                    .await
                    .map_err(|e| {
                        warn!(
                            operation = "sync.upsert_reward_tag",
                            reward_id = %reward_id,
                            tag_id = %tag_id,
                            error = ?e,
                            "sync tag relationship rejected"
                        );
                        ApiError::Validation(format!(
                            "Invalid reward or tag reference for reward_id: {}, tag_id: {}",
                            reward_id, tag_id
                        ))
                    })?;

            result_reward_tags.push(reward_tag_output_from_row(reward_tag_row));
        }
    }

    if let Some(theme_palettes) = &input.theme_palettes {
        validate_theme_palettes(theme_palettes)?;
        Database::update_theme_palettes_tx(
            &mut tx,
            user.user_id,
            &theme_palettes_to_database_row(theme_palettes),
        )
        .await
        .map_err(|e| internal_error("sync.update_theme_palettes", e))?;
    }

    let has_cycles = Database::user_has_task_dependency_cycles_tx(&mut tx, user.user_id)
        .await
        .map_err(|e| internal_error("sync.validate_task_dependency_cycles", e))?;
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
            server_revision,
        )
        .await
        .map_err(|e| internal_error("sync.delete_task_task_dependencies_for_deleted_task", e))?;

        for dependency_row in deleted_task_dependencies {
            upsert_task_task_dependency_output(&mut result_task_task_dependencies, dependency_row);
        }

        let deleted_recurring_task_dependencies =
            Database::soft_delete_task_recurring_task_dependencies_for_task_tx(
                &mut tx,
                user.user_id,
                task_id,
                deleted_at,
                server_revision,
            )
            .await
            .map_err(|e| {
                internal_error(
                    "sync.delete_task_recurring_task_dependencies_for_deleted_task",
                    e,
                )
            })?;

        for dependency_row in deleted_recurring_task_dependencies {
            upsert_task_recurring_task_dependency_output(
                &mut result_task_recurring_task_dependencies,
                dependency_row,
            );
        }

        let deleted_reward_task_dependencies =
            Database::soft_delete_reward_task_dependencies_for_task_tx(
                &mut tx,
                user.user_id,
                task_id,
                deleted_at,
                server_revision,
            )
            .await
            .map_err(|e| {
                internal_error("sync.delete_reward_task_dependencies_for_deleted_task", e)
            })?;

        for dependency_row in deleted_reward_task_dependencies {
            upsert_reward_task_dependency_output(
                &mut result_reward_task_dependencies,
                dependency_row,
            );
        }
    }

    for (reward_id, deleted_at) in deleted_rewards {
        let (deleted_task_dependencies, deleted_recurring_task_dependencies) =
            Database::soft_delete_reward_dependencies_for_reward_tx(
                &mut tx,
                user.user_id,
                reward_id,
                deleted_at,
                server_revision,
            )
            .await
            .map_err(|e| internal_error("sync.delete_reward_dependencies_for_deleted_reward", e))?;

        for dependency_row in deleted_task_dependencies {
            upsert_reward_task_dependency_output(
                &mut result_reward_task_dependencies,
                dependency_row,
            );
        }

        for dependency_row in deleted_recurring_task_dependencies {
            upsert_reward_recurring_task_dependency_output(
                &mut result_reward_recurring_task_dependencies,
                dependency_row,
            );
        }
    }

    for recurring_task_id in deleted_recurring_task_ids {
        let has_dependents = Database::recurring_task_has_active_dependents_tx(
            &mut tx,
            user.user_id,
            recurring_task_id,
        )
        .await
        .map_err(|e| internal_error("sync.validate_recurring_task_dependents", e))?;

        if has_dependents {
            return Err(ApiError::Validation(
                "This item cannot be deleted while active tasks still depend on it.".to_string(),
            ));
        }

        let has_reward_dependents = Database::recurring_task_has_active_reward_dependents_tx(
            &mut tx,
            user.user_id,
            recurring_task_id,
        )
        .await
        .map_err(|e| internal_error("sync.validate_recurring_task_reward_dependents", e))?;

        if has_reward_dependents {
            return Err(ApiError::Validation(
                "This item cannot be deleted while active rewards still depend on it.".to_string(),
            ));
        }
    }

    if has_premium_access {
        for task_id in completed_task_ids {
            let has_incomplete_dependencies =
                Database::task_has_incomplete_dependencies_tx(&mut tx, user.user_id, task_id)
                    .await
                    .map_err(|e| internal_error("sync.validate_task_completion_dependencies", e))?;

            if has_incomplete_dependencies {
                return Err(ApiError::Validation(
                    "Task dependencies must be complete before this task can be completed."
                        .to_string(),
                ));
            }
        }
    }

    if !touched_task_ids.is_empty() {
        result_tasks = load_tasks_by_ids_for_sync(
            &mut tx,
            user.user_id,
            touched_task_ids.into_iter().collect(),
        )
        .await
        .map_err(|e| internal_error("sync.load_affected_tasks_for_push_response", e))?
        .into_iter()
        .map(task_output_from_row)
        .collect();
    }

    // Return a balance derived from the just-written trade history instead of
    // relying on a separate cached column.
    let new_balance = Database::calculate_balance_from_trades_tx(&mut tx, user.user_id)
        .await
        .map_err(|e| internal_error("sync.calculate_balance_from_trades", e))?;

    if let Some(base_cursor) = requested_base_cursor.as_ref() {
        merge_cursor_delta_outputs_for_sync(
            &mut tx,
            user.user_id,
            base_cursor,
            &mut result_timers,
            &mut result_tasks,
            &mut result_recurring_tasks,
            &mut result_trades,
            &mut result_tags,
            &mut result_task_tags,
            &mut result_task_task_dependencies,
            &mut result_task_recurring_task_dependencies,
            &mut result_recurring_task_tags,
            &mut result_rewards,
            &mut result_reward_task_dependencies,
            &mut result_reward_recurring_task_dependencies,
            &mut result_reward_tags,
        )
        .await
        .map_err(|e| internal_error("sync.load_base_cursor_delta_for_push_response", e))?;
    }

    let server_time = Utc::now().naive_utc();
    let is_premium = profile_is_entitled(&profile_row_for_validation);
    let theme_palettes = input
        .theme_palettes
        .clone()
        .unwrap_or_else(|| theme_palettes_from_profile(&profile_row_for_validation));
    let server_cursor = SyncCursor {
        revision: server_revision,
    }
    .encode()
    .map_err(|e| internal_error("sync.encode_push_cursor", e))?;

    let response = SyncResponse {
        timers: result_timers,
        tasks: result_tasks,
        recurring_tasks: result_recurring_tasks,
        trades: result_trades,
        tags: result_tags,
        task_tags: result_task_tags,
        task_task_dependencies: result_task_task_dependencies,
        task_recurring_task_dependencies: result_task_recurring_task_dependencies,
        recurring_task_tags: result_recurring_task_tags,
        rewards: result_rewards,
        reward_task_dependencies: result_reward_task_dependencies,
        reward_recurring_task_dependencies: result_reward_recurring_task_dependencies,
        reward_tags: result_reward_tags,
        balance: BalanceOutput {
            point_balance: new_balance,
        },
        server_cursor,
        server_time,
        email: profile_row_for_validation.email,
        is_premium,
        theme_palettes,
    };

    if !operation_ids.is_empty() {
        store_processed_sync_batch_response_tx(
            &mut tx,
            user.user_id,
            &operation_ids,
            server_revision,
            &response,
        )
        .await
        .map_err(|e| internal_error("sync.store_processed_sync_operation", e))?;
    }

    tx.commit()
        .await
        .map_err(|e| internal_error("sync.commit_push_transaction", e))?;

    Ok(Json(response).into_response())
}

impl SyncCursor {
    fn decode(raw: &str) -> Result<Self, String> {
        if let Ok(revision) = raw.parse::<i64>() {
            return Ok(Self { revision });
        }

        let bytes = URL_SAFE_NO_PAD
            .decode(raw)
            .map_err(|error| error.to_string())?;
        let value: serde_json::Value =
            serde_json::from_slice(&bytes).map_err(|error| error.to_string())?;
        let revision = value
            .get("revision")
            .and_then(|value| value.as_i64())
            .ok_or_else(|| "Sync cursor is missing revision".to_string())?;
        Ok(Self { revision })
    }

    fn encode(&self) -> Result<String, String> {
        Ok(self.revision.to_string())
    }
}

#[allow(clippy::too_many_arguments)]
async fn merge_cursor_delta_outputs_for_sync(
    tx: &mut Transaction<'_, Postgres>,
    user_id: Uuid,
    cursor: &SyncCursor,
    timers: &mut Vec<TimerOutput>,
    tasks: &mut Vec<TaskOutput>,
    recurring_tasks: &mut Vec<RecurringTaskOutput>,
    trades: &mut Vec<TradeOutput>,
    tags: &mut Vec<TagOutput>,
    task_tags: &mut Vec<TaskTagOutput>,
    task_task_dependencies: &mut Vec<TaskTaskDependencyOutput>,
    task_recurring_task_dependencies: &mut Vec<TaskRecurringTaskDependencyOutput>,
    recurring_task_tags: &mut Vec<RecurringTaskTagOutput>,
    rewards: &mut Vec<RewardOutput>,
    reward_task_dependencies: &mut Vec<RewardTaskDependencyOutput>,
    reward_recurring_task_dependencies: &mut Vec<RewardRecurringTaskDependencyOutput>,
    reward_tags: &mut Vec<RewardTagOutput>,
) -> Result<(), sqlx::Error> {
    for output in load_timers_for_sync(tx, user_id, None, Some(cursor))
        .await?
        .into_iter()
        .map(timer_output_from_row)
    {
        upsert_output(timers, output, |timer| timer.id.clone());
    }

    for output in load_recurring_tasks_for_sync(tx, user_id, None, Some(cursor))
        .await?
        .into_iter()
        .map(recurring_task_output_from_row)
    {
        upsert_output(recurring_tasks, output, |recurring_task| {
            recurring_task.id.clone()
        });
    }

    for output in load_tasks_for_sync(tx, user_id, None, Some(cursor))
        .await?
        .into_iter()
        .map(task_output_from_row)
    {
        upsert_output(tasks, output, |task| task.id.clone());
    }

    for output in load_trades_for_sync(tx, user_id, None, Some(cursor))
        .await?
        .into_iter()
        .map(trade_output_from_row)
    {
        upsert_output(trades, output, |trade| trade.id.clone());
    }

    for output in load_tags_for_sync(tx, user_id, None, Some(cursor))
        .await?
        .into_iter()
        .map(tag_output_from_row)
    {
        upsert_output(tags, output, |tag| tag.id.clone());
    }

    for output in load_task_tags_for_sync(tx, user_id, None, Some(cursor))
        .await?
        .into_iter()
        .map(task_tag_output_from_row)
    {
        upsert_output(task_tags, output, |tag| {
            (tag.task_id.clone(), tag.tag_id.clone())
        });
    }

    for output in load_task_task_dependencies_for_sync(tx, user_id, None, Some(cursor))
        .await?
        .into_iter()
        .map(task_task_dependency_output_from_row)
    {
        upsert_output(task_task_dependencies, output, |dependency| {
            (
                dependency.task_id.clone(),
                dependency.depends_on_task_id.clone(),
            )
        });
    }

    for output in load_task_recurring_task_dependencies_for_sync(tx, user_id, None, Some(cursor))
        .await?
        .into_iter()
        .map(task_recurring_task_dependency_output_from_row)
    {
        upsert_output(task_recurring_task_dependencies, output, |dependency| {
            (
                dependency.task_id.clone(),
                dependency.recurring_task_id.clone(),
            )
        });
    }

    for output in load_recurring_task_tags_for_sync(tx, user_id, None, Some(cursor))
        .await?
        .into_iter()
        .map(recurring_task_tag_output_from_row)
    {
        upsert_output(recurring_task_tags, output, |tag| {
            (tag.recurring_task_id.clone(), tag.tag_id.clone())
        });
    }

    for output in load_rewards_for_sync(tx, user_id, None, Some(cursor))
        .await?
        .into_iter()
        .map(reward_output_from_row)
    {
        upsert_output(rewards, output, |reward| reward.id.clone());
    }

    for output in load_reward_task_dependencies_for_sync(tx, user_id, None, Some(cursor))
        .await?
        .into_iter()
        .map(reward_task_dependency_output_from_row)
    {
        upsert_output(reward_task_dependencies, output, |dependency| {
            (
                dependency.reward_id.clone(),
                dependency.depends_on_task_id.clone(),
            )
        });
    }

    for output in load_reward_recurring_task_dependencies_for_sync(tx, user_id, None, Some(cursor))
        .await?
        .into_iter()
        .map(reward_recurring_task_dependency_output_from_row)
    {
        upsert_output(reward_recurring_task_dependencies, output, |dependency| {
            (
                dependency.reward_id.clone(),
                dependency.recurring_task_id.clone(),
            )
        });
    }

    for output in load_reward_tags_for_sync(tx, user_id, None, Some(cursor))
        .await?
        .into_iter()
        .map(reward_tag_output_from_row)
    {
        upsert_output(reward_tags, output, |tag| {
            (tag.reward_id.clone(), tag.tag_id.clone())
        });
    }

    Ok(())
}

async fn load_snapshot_cursor(
    tx: &mut Transaction<'_, Postgres>,
    user_id: Uuid,
) -> Result<SyncCursor, sqlx::Error> {
    let revision = load_user_revision_tx(tx, user_id).await?;
    Ok(SyncCursor { revision })
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
                   AND recurring = FALSE
                   AND server_revision > $2
                 ORDER BY updated_at ASC",
                select_columns
            );
            sqlx::query_as(&query)
                .bind(user_id)
                .bind(cursor.revision)
                .fetch_all(&mut **tx)
                .await
        }
        None => match since {
            Some(since_time) => {
                let query = format!(
                    "SELECT {}
                     FROM tasks
                     WHERE user_id = $1 AND recurring = FALSE AND updated_at > $2
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
                     WHERE user_id = $1 AND recurring = FALSE
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

async fn load_timers_for_sync(
    tx: &mut Transaction<'_, Postgres>,
    user_id: Uuid,
    since: Option<NaiveDateTime>,
    cursor: Option<&SyncCursor>,
) -> Result<Vec<database::TimerRow>, sqlx::Error> {
    match cursor {
        Some(cursor) => {
            sqlx::query_as(
                "SELECT id, name, intervals, created_at, updated_at, deleted_at, server_revision
                 FROM timers
                 WHERE user_id = $1
                   AND server_revision > $2
                 ORDER BY updated_at ASC",
            )
            .bind(user_id)
            .bind(cursor.revision)
            .fetch_all(&mut **tx)
            .await
        }
        None => match since {
            Some(since_time) => sqlx::query_as(
                "SELECT id, name, intervals, created_at, updated_at, deleted_at, server_revision
                     FROM timers
                     WHERE user_id = $1 AND updated_at > $2
                     ORDER BY updated_at ASC",
            )
            .bind(user_id)
            .bind(since_time)
            .fetch_all(&mut **tx)
            .await,
            None => sqlx::query_as(
                "SELECT id, name, intervals, created_at, updated_at, deleted_at, server_revision
                     FROM timers
                     WHERE user_id = $1
                     ORDER BY updated_at ASC",
            )
            .bind(user_id)
            .fetch_all(&mut **tx)
            .await,
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
         WHERE user_id = $1 AND recurring = FALSE AND id = ANY($2)
         ORDER BY updated_at ASC",
        database::task_select_columns("tasks", "tasks.user_id")
    );
    sqlx::query_as(&query)
        .bind(user_id)
        .bind(task_ids)
        .fetch_all(&mut **tx)
        .await
}

async fn load_recurring_tasks_for_sync(
    tx: &mut Transaction<'_, Postgres>,
    user_id: Uuid,
    since: Option<NaiveDateTime>,
    cursor: Option<&SyncCursor>,
) -> Result<Vec<database::RecurringTaskRow>, sqlx::Error> {
    match cursor {
        Some(cursor) => {
            sqlx::query_as(
                "SELECT id, name, created_at, updated_at, deleted_at, description, min_daily_frequency, base_price, lockout_duration_seconds, pinned, hidden, timer_mode, timer_id, server_revision
                 FROM tasks
                 WHERE user_id = $1
                   AND recurring = TRUE
                   AND server_revision > $2
                 ORDER BY updated_at ASC",
            )
            .bind(user_id)
            .bind(cursor.revision)
            .fetch_all(&mut **tx)
            .await
        }
        None => match since {
            Some(since_time) => {
                sqlx::query_as(
                    "SELECT id, name, created_at, updated_at, deleted_at, description, min_daily_frequency, base_price, lockout_duration_seconds, pinned, hidden, timer_mode, timer_id, server_revision
                     FROM tasks
                     WHERE user_id = $1 AND recurring = TRUE AND updated_at > $2
                     ORDER BY updated_at ASC",
                )
                .bind(user_id)
                .bind(since_time)
                .fetch_all(&mut **tx)
                .await
            }
            None => {
                sqlx::query_as(
                    "SELECT id, name, created_at, updated_at, deleted_at, description, min_daily_frequency, base_price, lockout_duration_seconds, pinned, hidden, timer_mode, timer_id, server_revision
                     FROM tasks
                     WHERE user_id = $1 AND recurring = TRUE
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
                "SELECT id, task_id, recurring_task_id, reward_id, source_name, amount, vault_amount_micro, adjustment_base_amount, one_time_adjustment_multiplier, trade_kind, vault_interest_hour, created_at, updated_at, deleted_at, refunds_trade_id, server_revision
                 FROM trades
                 WHERE user_id = $1
                   AND server_revision > $2
                 ORDER BY updated_at ASC",
            )
            .bind(user_id)
            .bind(cursor.revision)
            .fetch_all(&mut **tx)
            .await
        }
        None => match since {
            Some(since_time) => {
                sqlx::query_as(
                    "SELECT id, task_id, recurring_task_id, reward_id, source_name, amount, vault_amount_micro, adjustment_base_amount, one_time_adjustment_multiplier, trade_kind, vault_interest_hour, created_at, updated_at, deleted_at, refunds_trade_id, server_revision
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
                    "SELECT id, task_id, recurring_task_id, reward_id, source_name, amount, vault_amount_micro, adjustment_base_amount, one_time_adjustment_multiplier, trade_kind, vault_interest_hour, created_at, updated_at, deleted_at, refunds_trade_id, server_revision
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
                "SELECT id, name, color_hex, created_at, updated_at, deleted_at, server_revision
                 FROM tags
                 WHERE user_id = $1
                   AND server_revision > $2
                 ORDER BY updated_at ASC",
            )
            .bind(user_id)
            .bind(cursor.revision)
            .fetch_all(&mut **tx)
            .await
        }
        None => match since {
            Some(since_time) => sqlx::query_as(
                "SELECT id, name, color_hex, created_at, updated_at, deleted_at, server_revision
                     FROM tags
                     WHERE user_id = $1 AND updated_at > $2
                     ORDER BY updated_at ASC",
            )
            .bind(user_id)
            .bind(since_time)
            .fetch_all(&mut **tx)
            .await,
            None => sqlx::query_as(
                "SELECT id, name, color_hex, created_at, updated_at, deleted_at, server_revision
                     FROM tags
                     WHERE user_id = $1
                     ORDER BY updated_at ASC",
            )
            .bind(user_id)
            .fetch_all(&mut **tx)
            .await,
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
                "SELECT tt.task_id, tt.tag_id, tt.created_at, tt.updated_at, tt.deleted_at, tt.server_revision
                 FROM task_tags tt
                 JOIN tasks t ON tt.task_id = t.id
                 WHERE t.user_id = $1
                   AND t.recurring = FALSE
                   AND tt.server_revision > $2
                 ORDER BY tt.updated_at ASC",
            )
            .bind(user_id)
            .bind(cursor.revision)
            .fetch_all(&mut **tx)
            .await
        }
        None => match since {
            Some(since_time) => {
                sqlx::query_as(
                    "SELECT tt.task_id, tt.tag_id, tt.created_at, tt.updated_at, tt.deleted_at, tt.server_revision
                     FROM task_tags tt
                     JOIN tasks t ON tt.task_id = t.id
                     WHERE t.user_id = $1 AND t.recurring = FALSE AND tt.updated_at > $2
                     ORDER BY tt.updated_at ASC",
                )
                .bind(user_id)
                .bind(since_time)
                .fetch_all(&mut **tx)
                .await
            }
            None => {
                sqlx::query_as(
                    "SELECT tt.task_id, tt.tag_id, tt.created_at, tt.updated_at, tt.deleted_at, tt.server_revision
                     FROM task_tags tt
                     JOIN tasks t ON tt.task_id = t.id
                     WHERE t.user_id = $1 AND t.recurring = FALSE
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
                "SELECT ttd.task_id, ttd.depends_on_task_id, ttd.created_at, ttd.updated_at, ttd.deleted_at, ttd.server_revision
                 FROM task_task_dependencies ttd
                 JOIN tasks t ON ttd.task_id = t.id
                 WHERE t.user_id = $1
                   AND t.recurring = FALSE
                   AND ttd.server_revision > $2
                 ORDER BY ttd.updated_at ASC",
            )
            .bind(user_id)
            .bind(cursor.revision)
            .fetch_all(&mut **tx)
            .await
        }
        None => match since {
            Some(since_time) => {
                sqlx::query_as(
                    "SELECT ttd.task_id, ttd.depends_on_task_id, ttd.created_at, ttd.updated_at, ttd.deleted_at, ttd.server_revision
                     FROM task_task_dependencies ttd
                     JOIN tasks t ON ttd.task_id = t.id
                     WHERE t.user_id = $1 AND t.recurring = FALSE AND ttd.updated_at > $2
                     ORDER BY ttd.updated_at ASC",
                )
                .bind(user_id)
                .bind(since_time)
                .fetch_all(&mut **tx)
                .await
            }
            None => {
                sqlx::query_as(
                    "SELECT ttd.task_id, ttd.depends_on_task_id, ttd.created_at, ttd.updated_at, ttd.deleted_at, ttd.server_revision
                     FROM task_task_dependencies ttd
                     JOIN tasks t ON ttd.task_id = t.id
                     WHERE t.user_id = $1 AND t.recurring = FALSE
                     ORDER BY ttd.updated_at ASC",
                )
                .bind(user_id)
                .fetch_all(&mut **tx)
                .await
            }
        },
    }
}

async fn load_task_recurring_task_dependencies_for_sync(
    tx: &mut Transaction<'_, Postgres>,
    user_id: Uuid,
    since: Option<NaiveDateTime>,
    cursor: Option<&SyncCursor>,
) -> Result<Vec<database::TaskRecurringTaskDependencyRow>, sqlx::Error> {
    match cursor {
        Some(cursor) => {
            sqlx::query_as(
                "SELECT thd.task_id, thd.recurring_task_id, thd.required_completions, thd.baseline_completion_count, thd.created_at, thd.updated_at, thd.deleted_at, thd.server_revision
                 FROM task_recurring_task_dependencies thd
                 JOIN tasks t ON thd.task_id = t.id
                 WHERE t.user_id = $1
                   AND t.recurring = FALSE
                   AND thd.server_revision > $2
                 ORDER BY thd.updated_at ASC",
            )
            .bind(user_id)
            .bind(cursor.revision)
            .fetch_all(&mut **tx)
            .await
        }
        None => match since {
            Some(since_time) => {
                sqlx::query_as(
                    "SELECT thd.task_id, thd.recurring_task_id, thd.required_completions, thd.baseline_completion_count, thd.created_at, thd.updated_at, thd.deleted_at, thd.server_revision
                     FROM task_recurring_task_dependencies thd
                     JOIN tasks t ON thd.task_id = t.id
                     WHERE t.user_id = $1 AND t.recurring = FALSE AND thd.updated_at > $2
                     ORDER BY thd.updated_at ASC",
                )
                .bind(user_id)
                .bind(since_time)
                .fetch_all(&mut **tx)
                .await
            }
            None => {
                sqlx::query_as(
                    "SELECT thd.task_id, thd.recurring_task_id, thd.required_completions, thd.baseline_completion_count, thd.created_at, thd.updated_at, thd.deleted_at, thd.server_revision
                     FROM task_recurring_task_dependencies thd
                     JOIN tasks t ON thd.task_id = t.id
                     WHERE t.user_id = $1 AND t.recurring = FALSE
                     ORDER BY thd.updated_at ASC",
                )
                .bind(user_id)
                .fetch_all(&mut **tx)
                .await
            }
        },
    }
}

async fn load_recurring_task_tags_for_sync(
    tx: &mut Transaction<'_, Postgres>,
    user_id: Uuid,
    since: Option<NaiveDateTime>,
    cursor: Option<&SyncCursor>,
) -> Result<Vec<database::RecurringTaskTagRow>, sqlx::Error> {
    match cursor {
        Some(cursor) => {
            sqlx::query_as(
                "SELECT ht.recurring_task_id, ht.tag_id, ht.created_at, ht.updated_at, ht.deleted_at, ht.server_revision
                 FROM recurring_task_tags ht
                 JOIN tasks h ON ht.recurring_task_id = h.id
                 WHERE h.user_id = $1
                   AND h.recurring = TRUE
                   AND ht.server_revision > $2
                 ORDER BY ht.updated_at ASC",
            )
            .bind(user_id)
            .bind(cursor.revision)
            .fetch_all(&mut **tx)
            .await
        }
        None => match since {
            Some(since_time) => {
                sqlx::query_as(
                    "SELECT ht.recurring_task_id, ht.tag_id, ht.created_at, ht.updated_at, ht.deleted_at, ht.server_revision
                     FROM recurring_task_tags ht
                     JOIN tasks h ON ht.recurring_task_id = h.id
                     WHERE h.user_id = $1 AND h.recurring = TRUE AND ht.updated_at > $2
                     ORDER BY ht.updated_at ASC",
                )
                .bind(user_id)
                .bind(since_time)
                .fetch_all(&mut **tx)
                .await
            }
            None => {
                sqlx::query_as(
                    "SELECT ht.recurring_task_id, ht.tag_id, ht.created_at, ht.updated_at, ht.deleted_at, ht.server_revision
                     FROM recurring_task_tags ht
                     JOIN tasks h ON ht.recurring_task_id = h.id
                     WHERE h.user_id = $1 AND h.recurring = TRUE
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
                "SELECT id, recurring, name, description, created_at, updated_at, deleted_at, max_daily_frequency, base_price, lockout_duration_seconds, pinned, hidden, timer_mode, timer_id, server_revision
                 FROM rewards
                 WHERE user_id = $1
                   AND server_revision > $2
                 ORDER BY updated_at ASC",
            )
            .bind(user_id)
            .bind(cursor.revision)
            .fetch_all(&mut **tx)
            .await
        }
        None => match since {
            Some(since_time) => {
                sqlx::query_as(
                    "SELECT id, recurring, name, description, created_at, updated_at, deleted_at, max_daily_frequency, base_price, lockout_duration_seconds, pinned, hidden, timer_mode, timer_id, server_revision
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
                    "SELECT id, recurring, name, description, created_at, updated_at, deleted_at, max_daily_frequency, base_price, lockout_duration_seconds, pinned, hidden, timer_mode, timer_id, server_revision
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
                "SELECT rt.reward_id, rt.tag_id, rt.created_at, rt.updated_at, rt.deleted_at, rt.server_revision
                 FROM reward_tags rt
                 JOIN rewards r ON rt.reward_id = r.id
                 WHERE r.user_id = $1
                   AND rt.server_revision > $2
                 ORDER BY rt.updated_at ASC",
            )
            .bind(user_id)
            .bind(cursor.revision)
            .fetch_all(&mut **tx)
            .await
        }
        None => {
            match since {
                Some(since_time) => sqlx::query_as(
                    "SELECT rt.reward_id, rt.tag_id, rt.created_at, rt.updated_at, rt.deleted_at, rt.server_revision
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
                    "SELECT rt.reward_id, rt.tag_id, rt.created_at, rt.updated_at, rt.deleted_at, rt.server_revision
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

async fn load_reward_task_dependencies_for_sync(
    tx: &mut Transaction<'_, Postgres>,
    user_id: Uuid,
    since: Option<NaiveDateTime>,
    cursor: Option<&SyncCursor>,
) -> Result<Vec<database::RewardTaskDependencyRow>, sqlx::Error> {
    match cursor {
        Some(cursor) => {
            sqlx::query_as(
                "SELECT rtd.reward_id, rtd.depends_on_task_id, rtd.created_at, rtd.updated_at, rtd.deleted_at, rtd.server_revision
                 FROM reward_task_dependencies rtd
                 JOIN rewards r ON rtd.reward_id = r.id
                 WHERE r.user_id = $1
                   AND rtd.server_revision > $2
                 ORDER BY rtd.updated_at ASC",
            )
            .bind(user_id)
            .bind(cursor.revision)
            .fetch_all(&mut **tx)
            .await
        }
        None => match since {
            Some(since_time) => {
                sqlx::query_as(
                    "SELECT rtd.reward_id, rtd.depends_on_task_id, rtd.created_at, rtd.updated_at, rtd.deleted_at, rtd.server_revision
                     FROM reward_task_dependencies rtd
                     JOIN rewards r ON rtd.reward_id = r.id
                     WHERE r.user_id = $1 AND rtd.updated_at > $2
                     ORDER BY rtd.updated_at ASC",
                )
                .bind(user_id)
                .bind(since_time)
                .fetch_all(&mut **tx)
                .await
            }
            None => {
                sqlx::query_as(
                    "SELECT rtd.reward_id, rtd.depends_on_task_id, rtd.created_at, rtd.updated_at, rtd.deleted_at, rtd.server_revision
                     FROM reward_task_dependencies rtd
                     JOIN rewards r ON rtd.reward_id = r.id
                     WHERE r.user_id = $1
                     ORDER BY rtd.updated_at ASC",
                )
                .bind(user_id)
                .fetch_all(&mut **tx)
                .await
            }
        },
    }
}

async fn load_reward_recurring_task_dependencies_for_sync(
    tx: &mut Transaction<'_, Postgres>,
    user_id: Uuid,
    since: Option<NaiveDateTime>,
    cursor: Option<&SyncCursor>,
) -> Result<Vec<database::RewardRecurringTaskDependencyRow>, sqlx::Error> {
    match cursor {
        Some(cursor) => {
            sqlx::query_as(
                "SELECT rhd.reward_id, rhd.recurring_task_id, rhd.required_completions, rhd.baseline_completion_count, rhd.created_at, rhd.updated_at, rhd.deleted_at, rhd.server_revision
                 FROM reward_recurring_task_dependencies rhd
                 JOIN rewards r ON rhd.reward_id = r.id
                 WHERE r.user_id = $1
                   AND rhd.server_revision > $2
                 ORDER BY rhd.updated_at ASC",
            )
            .bind(user_id)
            .bind(cursor.revision)
            .fetch_all(&mut **tx)
            .await
        }
        None => match since {
            Some(since_time) => {
                sqlx::query_as(
                    "SELECT rhd.reward_id, rhd.recurring_task_id, rhd.required_completions, rhd.baseline_completion_count, rhd.created_at, rhd.updated_at, rhd.deleted_at, rhd.server_revision
                     FROM reward_recurring_task_dependencies rhd
                     JOIN rewards r ON rhd.reward_id = r.id
                     WHERE r.user_id = $1 AND rhd.updated_at > $2
                     ORDER BY rhd.updated_at ASC",
                )
                .bind(user_id)
                .bind(since_time)
                .fetch_all(&mut **tx)
                .await
            }
            None => {
                sqlx::query_as(
                    "SELECT rhd.reward_id, rhd.recurring_task_id, rhd.required_completions, rhd.baseline_completion_count, rhd.created_at, rhd.updated_at, rhd.deleted_at, rhd.server_revision
                     FROM reward_recurring_task_dependencies rhd
                     JOIN rewards r ON rhd.reward_id = r.id
                     WHERE r.user_id = $1
                     ORDER BY rhd.updated_at ASC",
                )
                .bind(user_id)
                .fetch_all(&mut **tx)
                .await
            }
        },
    }
}

async fn load_balance_for_sync(
    tx: &mut Transaction<'_, Postgres>,
    user_id: Uuid,
) -> Result<i64, sqlx::Error> {
    let (total,): (Option<i64>,) = sqlx::query_as(
        "SELECT COALESCE(SUM(amount), 0)
         FROM trades
         WHERE user_id = $1
           AND deleted_at IS NULL
           AND trade_kind IN ('taskCompletion', 'recurringTaskCompletion', 'rewardPurchase', 'vaultDeposit')",
    )
    .bind(user_id)
    .fetch_one(&mut **tx)
    .await?;

    Ok(total.unwrap_or(0))
}

async fn load_profile_for_sync(
    tx: &mut Transaction<'_, Postgres>,
    user_id: Uuid,
) -> Result<database::UserProfileRow, sqlx::Error> {
    sqlx::query_as(
        "SELECT
            users.email,
            COALESCE(entitlement.status, 'none') AS subscription_status,
            entitlement.expires_at AS subscription_expires_at,
            users.theme_palette_main,
            users.theme_palette_accent
         FROM users
         LEFT JOIN LATERAL (
            SELECT
                status,
                expires_at,
                updated_at
            FROM premium_entitlements
            WHERE user_id = users.id
              AND deleted_at IS NULL
            ORDER BY
                CASE
                    WHEN status IN ('active', 'grace_period')
                     AND (expires_at IS NULL OR expires_at > NOW())
                    THEN 0
                    ELSE 1
                END,
                updated_at DESC
            LIMIT 1
         ) entitlement ON TRUE
         WHERE users.id = $1",
    )
    .bind(user_id)
    .fetch_one(&mut **tx)
    .await
}
