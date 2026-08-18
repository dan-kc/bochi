use crate::error_context::log_sqlx_error;
use axum::{
    http::StatusCode,
    response::{IntoResponse, Response},
    Json,
};
use serde::Serialize;
use std::any::{type_name, Any};
use std::fmt;

#[derive(Debug)]
pub enum ApiError {
    Validation(String),
    Conflict(String),
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
            ApiError::Conflict(msg) => (
                StatusCode::CONFLICT,
                "CONFLICT",
                format!("Conflict: {}", msg),
            ),
            ApiError::Internal => (
                StatusCode::INTERNAL_SERVER_ERROR,
                "INTERNAL_SERVER_ERROR",
                "An unexpected internal server error occurred.".to_string(),
            ),
        };

        log_api_error_response(status, code, message.as_str());

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
        internal_error("database_query", e)
    }
}

pub fn internal_error<E>(operation: &'static str, error: E) -> ApiError
where
    E: fmt::Debug + Any,
{
    if let Some(error) = (&error as &dyn Any).downcast_ref::<sqlx::Error>() {
        log_sqlx_error(operation, error, "internal database operation failed");
        return ApiError::Internal;
    }

    tracing::error!(
        operation,
        error = ?error,
        error_type = type_name::<E>(),
        "internal backend operation failed"
    );
    ApiError::Internal
}

fn log_api_error_response(status: StatusCode, code: &str, message: &str) {
    if status.is_server_error() {
        tracing::error!(
            status_code = status.as_u16(),
            error_code = code,
            error_message = message,
            "api request failed"
        );
    } else {
        tracing::warn!(
            status_code = status.as_u16(),
            error_code = code,
            error_message = message,
            "api request rejected"
        );
    }
}
