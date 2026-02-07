use axum::{
    http::StatusCode,
    response::{IntoResponse, Response},
    Json,
};
use serde::Serialize;

#[derive(Debug)]
pub enum ApiError {
    Validation(String),
    Internal,
}

#[derive(Serialize)]
struct ErrorResponse {
    errors: Vec<ErrorDetail>,
}

#[derive(Serialize)]
struct ErrorDetail {
    code: String,
    message: String,
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        let (status, code, message) = match &self {
            ApiError::Validation(msg) => (
                StatusCode::BAD_REQUEST,
                "BAD_USER_INPUT",
                format!("Validation Error: {}", msg),
            ),
            ApiError::Internal => (
                StatusCode::INTERNAL_SERVER_ERROR,
                "INTERNAL_SERVER_ERROR",
                "An unexpected internal server error occurred.".to_string(),
            ),
        };

        let body = ErrorResponse {
            errors: vec![ErrorDetail {
                code: code.to_string(),
                message,
            }],
        };

        (status, Json(body)).into_response()
    }
}

impl From<sqlx::Error> for ApiError {
    fn from(e: sqlx::Error) -> Self {
        tracing::error!("Database error: {:?}", e);
        ApiError::Internal
    }
}
