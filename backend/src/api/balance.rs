use axum::{extract::State, response::IntoResponse, Extension, Json};
use serde::Serialize;
use tracing::error;

use crate::router::{App, AuthenticatedUser};

use super::ApiError;

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BalanceResponse {
    pub tofu_balance: f64,
}

pub async fn get_balance(
    State(app): State<App>,
    Extension(user): Extension<AuthenticatedUser>,
) -> Result<impl IntoResponse, ApiError> {
    let trade_balance = app
        .database
        .calculate_balance_from_trades(user.user_id)
        .await
        .map_err(|e| {
            error!("Database Error: {:?}", e);
            ApiError::Internal
        })?;

    Ok(Json(BalanceResponse {
        tofu_balance: trade_balance,
    }))
}
