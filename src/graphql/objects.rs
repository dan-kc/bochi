use crate::database::{RewardRow, TaskRow, UserRow};
use async_graphql::{SimpleObject, Union};
use chrono::NaiveDateTime;

#[derive(SimpleObject)]
struct User {
    id: i32,
    email: String,
}
impl From<UserRow> for User {
    fn from(value: UserRow) -> Self {
        Self {
            id: value.id,
            email: value.email,
        }
    }
}

#[derive(SimpleObject)]
pub struct TaskObject {
    id: i32,
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
            id: task_row.id,
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
    id: i32,
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
            id: reward_row.id,
            name: reward_row.name,
            created_at: reward_row.created_at,
            deleted_at: reward_row.deleted_at,
            hidden_until: reward_row.hidden_until,
            description: reward_row.description,
            max_daily_frequency: reward_row.max_daily_frequency, 
        }
    }
}

#[derive(Union)]
pub enum TradableItem {
    Reward(RewardObject),
    Task(TaskObject),
}

#[derive(SimpleObject)]
pub struct TradeObject {
    id: i32,
    amount: i32,
    created_at: NaiveDateTime,
    tradable_item: TradableItem,
}
