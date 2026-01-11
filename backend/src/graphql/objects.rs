use crate::database::{RewardRow, TaskRow, TradeRow, TradeWithRewardRow, TradeWithTaskRow};
use async_graphql::{InputObject, Interface, SimpleObject};
use chrono::NaiveDateTime;

#[derive(SimpleObject, Clone)]
pub struct TaskObject {
    pub id: String,
    pub name: String, // Max 100 utf-8 chars
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub hidden_until: Option<NaiveDateTime>,
    pub due_by: Option<NaiveDateTime>,
    pub description: String,
    pub min_daily_frequency: Option<f64>,
    pub difficulty_rank: Option<String>,
    pub completed_at: Option<NaiveDateTime>,
}
impl From<TaskRow> for TaskObject {
    fn from(task_row: TaskRow) -> Self {
        Self {
            id: task_row.id.to_string(),
            name: task_row.name,
            created_at: task_row.created_at,
            updated_at: task_row.updated_at,
            deleted_at: task_row.deleted_at,
            hidden_until: task_row.hidden_until,
            due_by: task_row.due_by,
            description: task_row.description,
            min_daily_frequency: task_row.min_daily_frequency,
            difficulty_rank: task_row.difficulty_rank,
            completed_at: task_row.completed_at,
        }
    }
}

#[derive(SimpleObject)]
pub struct RewardObject {
    id: String,
    name: String, // Max 100 utf-8 chars
    created_at: NaiveDateTime,
    updated_at: NaiveDateTime,
    deleted_at: Option<NaiveDateTime>,
    hidden_until: Option<NaiveDateTime>,
    description: String,
    max_daily_frequency: Option<f32>, // Max 100 / day
}
impl From<RewardRow> for RewardObject {
    fn from(reward_row: RewardRow) -> Self {
        Self {
            id: reward_row.id.to_string(),
            name: reward_row.name,
            created_at: reward_row.created_at,
            updated_at: reward_row.updated_at,
            deleted_at: reward_row.deleted_at,
            hidden_until: reward_row.hidden_until,
            description: reward_row.description,
            max_daily_frequency: reward_row.max_daily_frequency,
        }
    }
}
#[derive(Interface)]
#[graphql(
    field(name = "id", ty = "&String"),
    field(name = "name", ty = "String"),
    field(name = "created_at", ty = "&NaiveDateTime"),
    field(name = "updated_at", ty = "&NaiveDateTime"),
    field(name = "deleted_at", ty = "&Option<NaiveDateTime>"),
    field(name = "hidden_until", ty = "&Option<NaiveDateTime>"),
    field(name = "description", ty = "String")
)]
pub enum TradableItem {
    Reward(RewardObject),
    Task(TaskObject),
}

#[derive(SimpleObject)]
pub struct TradeObject {
    id: String,
    amount: i32,
    created_at: NaiveDateTime,
    tradable_item: TradableItem,
}
impl From<TradeWithTaskRow> for TradeObject {
    fn from(trade_row: TradeWithTaskRow) -> Self {
        let item = TradableItem::Task(TaskObject {
            id: trade_row.task_id.to_string(),
            name: trade_row.task_name,
            created_at: trade_row.task_created_at,
            updated_at: trade_row.task_updated_at,
            deleted_at: trade_row.task_deleted_at,
            hidden_until: trade_row.task_hidden_until,
            due_by: trade_row.task_due_by,
            description: trade_row.task_description,
            min_daily_frequency: trade_row.task_min_daily_frequency,
            difficulty_rank: trade_row.task_difficulty_rank,
            completed_at: None, // TradeWithTaskRow doesn't have this field
        });

        return TradeObject {
            id: trade_row.id.to_string(),
            amount: trade_row.amount,
            created_at: trade_row.created_at,
            tradable_item: item,
        };
    }
}
impl From<TradeWithRewardRow> for TradeObject {
    fn from(trade_row: TradeWithRewardRow) -> Self {
        let item = TradableItem::Reward(RewardObject {
            id: trade_row.reward_id.to_string(),
            name: trade_row.reward_name,
            created_at: trade_row.reward_created_at,
            updated_at: trade_row.reward_updated_at,
            deleted_at: trade_row.reward_deleted_at,
            hidden_until: trade_row.reward_hidden_until,
            description: trade_row.reward_description,
            max_daily_frequency: trade_row.reward_max_daily_frequency,
        });

        return TradeObject {
            id: trade_row.id.to_string(),
            amount: trade_row.amount,
            created_at: trade_row.created_at,
            tradable_item: item,
        };
    }
}

// ============================================================================
// Sync Types
// ============================================================================

#[derive(InputObject)]
pub struct SyncTaskInput {
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
}

#[derive(SimpleObject)]
pub struct SyncPullResponse {
    pub tasks: Vec<TaskObject>,
    pub server_time: NaiveDateTime,
}

#[derive(SimpleObject)]
pub struct SyncPushResponse {
    pub tasks: Vec<TaskObject>,
    pub server_time: NaiveDateTime,
}

// ============================================================================
// Trade Sync Types
// ============================================================================

#[derive(InputObject)]
pub struct SyncTradeInput {
    pub id: String,
    pub task_id: Option<String>,
    pub reward_id: Option<String>,
    pub amount: i32,
    pub created_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
}

#[derive(SimpleObject)]
pub struct SyncTradeObject {
    pub id: String,
    pub task_id: Option<String>,
    pub reward_id: Option<String>,
    pub amount: i32,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
}

impl From<TradeRow> for SyncTradeObject {
    fn from(trade_row: TradeRow) -> Self {
        Self {
            id: trade_row.id.to_string(),
            task_id: trade_row.task_id.map(|id| id.to_string()),
            reward_id: trade_row.reward_id.map(|id| id.to_string()),
            amount: trade_row.amount,
            created_at: trade_row.created_at,
            updated_at: trade_row.updated_at,
            deleted_at: trade_row.deleted_at,
        }
    }
}

#[derive(SimpleObject)]
pub struct SyncPullTradesResponse {
    pub trades: Vec<SyncTradeObject>,
    pub server_time: NaiveDateTime,
}

#[derive(SimpleObject)]
pub struct SyncPushTradesResponse {
    pub trades: Vec<SyncTradeObject>,
    pub server_time: NaiveDateTime,
    pub new_balance: f64,
}

#[derive(SimpleObject)]
pub struct UserBalanceResponse {
    pub soy_balance: f64,
    pub tofu_balance: f64,
}
