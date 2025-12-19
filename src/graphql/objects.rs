use crate::database::{RewardRow, TaskRow, TradeWithRewardRow, TradeWithTaskRow};
use async_graphql::{Interface, SimpleObject};
use chrono::NaiveDateTime;

#[derive(SimpleObject)]
pub struct TaskObject {
    id: String,
    name: String, // Max 100 utf-8 chars
    created_at: NaiveDateTime,
    deleted_at: Option<NaiveDateTime>,
    hidden_until: Option<NaiveDateTime>,
    due_by: Option<NaiveDateTime>,
    description: String,
}
impl From<TaskRow> for TaskObject {
    fn from(task_row: TaskRow) -> Self {
        Self {
            id: task_row.id.to_string(),
            name: task_row.name,
            created_at: task_row.created_at,
            deleted_at: task_row.deleted_at,
            hidden_until: task_row.hidden_until,
            due_by: task_row.due_by,
            description: task_row.description,
        }
    }
}

#[derive(SimpleObject)]
pub struct RewardObject {
    id: String,
    name: String, // Max 100 utf-8 chars
    created_at: NaiveDateTime,
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
            deleted_at: trade_row.task_deleted_at,
            hidden_until: trade_row.task_hidden_until,
            due_by: trade_row.task_due_by,
            description: trade_row.task_description,
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
