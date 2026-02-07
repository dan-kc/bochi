use axum::{extract::State, response::IntoResponse, Extension, Json};
use serde::Serialize;
use tracing::error;

use crate::router::{App, AuthenticatedUser};

use super::ApiError;

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BalanceResponse {
    pub soy_balance: f64,
    pub tofu_balance: f64,
}

pub async fn get_balance(
    State(app): State<App>,
    Extension(user): Extension<AuthenticatedUser>,
) -> Result<impl IntoResponse, ApiError> {
    let balance_row = app
        .database
        .get_user_balance(user.user_id)
        .await
        .map_err(|e| {
            error!("Database Error: {:?}", e);
            ApiError::Internal
        })?;

    Ok(Json(BalanceResponse {
        soy_balance: balance_row.soy_balance,
        tofu_balance: balance_row.tofu_balance,
    }))
}
