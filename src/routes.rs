use std::fmt::Display;

use crate::{
    graphql::ServiceSchema,
    router::{App, AuthenticatedUser},
    security::{self, jwt::create_random_string, parse_refresh_token},
};
use async_graphql_axum::{GraphQLRequest, GraphQLResponse};
use axum::{
    debug_handler,
    extract::State,
    http::StatusCode,
    response::{IntoResponse, Response},
    Extension, Json,
};
use convert_case::Casing;
use regex::Regex;

#[derive(Debug, serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct AuthResponse {
    refresh_token: String,
    access_token: String,
}

#[derive(Debug, serde::Serialize)]
pub enum Error {
    ValidationErrorList(Vec<ValidationError>),
    UserAlreadyExists,
    FailedToLogin,
    FailedToCreateRefreshToken,
    FailedToCreateUser,
    InvalidRefreshToken,
    InvalidLoginCredentials,
}
impl Error {
    fn status_code(&self) -> StatusCode {
        match self {
            Self::ValidationErrorList(_) => StatusCode::BAD_REQUEST, // The outer match arm dissalows this
            Self::UserAlreadyExists => StatusCode::CONFLICT,

            Self::FailedToCreateUser => StatusCode::INTERNAL_SERVER_ERROR,
            Self::FailedToLogin => StatusCode::INTERNAL_SERVER_ERROR,
            Self::FailedToCreateRefreshToken => StatusCode::INTERNAL_SERVER_ERROR,

            Self::InvalidRefreshToken => StatusCode::UNAUTHORIZED,
            Self::InvalidLoginCredentials => StatusCode::UNAUTHORIZED,
        }
    }
}
impl Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::ValidationErrorList(_) => panic!(), // The outer match arm dissalows this
            Self::UserAlreadyExists => write!(f, "User already exists."),

            Self::FailedToCreateUser => write!(f, "Failed to create user."),
            Self::FailedToLogin => write!(f, "Failed to login user."),
            Self::FailedToCreateRefreshToken => {
                write!(f, "Failed to create refresh token.")
            }

            Self::InvalidRefreshToken => write!(f, "Invalid refresh token."),
            Self::InvalidLoginCredentials => {
                write!(f, "Incorrect email or password.")
            }
        }
    }
}

#[derive(serde::Serialize)]
struct ErrorDetail {
    code: String,
    message: String,
}
impl From<Error> for ErrorDetail {
    fn from(value: Error) -> Self {
        match value {
            Error::ValidationErrorList(_) => panic!(),
            _ => ErrorDetail {
                code: format!("{:?}", value).to_case(convert_case::Case::ScreamingSnake),
                message: value.to_string(),
            },
        }
    }
}
impl From<ValidationError> for ErrorDetail {
    fn from(value: ValidationError) -> Self {
        ErrorDetail {
            code: format!("{:?}", value).to_case(convert_case::Case::ScreamingSnake),
            message: value.to_string(),
        }
    }
}

#[derive(serde::Serialize)]
struct ErrorBody {
    errors: Vec<ErrorDetail>,
}
impl IntoResponse for Error {
    fn into_response(self) -> Response {
        match self {
            Self::ValidationErrorList(error_list) => {
                let mut error_details = Vec::new();
                for validation_error in error_list.into_iter() {
                    error_details.push(validation_error.into());
                }
                let error_response = ErrorBody {
                    errors: error_details,
                };

                (StatusCode::BAD_REQUEST, Json(error_response)).into_response()
            }
            _ => {
                let code = self.status_code();
                let error_resp = ErrorBody {
                    errors: vec![self.into()],
                };

                (code, Json(error_resp)).into_response()
            }
        }
    }
}

#[derive(Debug, serde::Serialize)]
pub enum ValidationError {
    InvalidEmailAddress,
    PasswordNotAscii,
    EmailTooLong,
    PasswordTooLong,
    PasswordTooShort,
    PasswordMismatch,
}
impl Display for ValidationError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::InvalidEmailAddress => write!(f, "Invalid email address."),
            Self::PasswordNotAscii => write!(f,
                 "Password must contain only standard English letters, numbers, and common punctuation."
            ),
            Self::EmailTooLong => write!(f,
                "Email too long. The maximum email length is 40."
            ),
            Self::PasswordTooLong => write!(f,
                 "Password too long. The maximum password length is 64."
            ),
            Self::PasswordTooShort => write!(f,
                 "Password too short. The min password length is 8."
            ),
            Self::PasswordMismatch => write!(f,
                 "Passwords do not match."
            ),
        }
    }
}

#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RegisterInput {
    email: String,
    password: String,
    confirm_password: String,
}
#[debug_handler]
pub async fn register(
    State(app): State<App>,
    Json(input): Json<RegisterInput>,
) -> Result<Response, Error> {
    let mut errors = vec![];
    let is_valid_email = Regex::new(r"^[\w\.-]+@[a-zA-Z\d\.-]+\.[a-zA-Z]{2,}$")
        .unwrap()
        .is_match(input.email.as_str());
    if !is_valid_email {
        errors.push(ValidationError::InvalidEmailAddress);
    }
    if input.email.len() > 40 {
        errors.push(ValidationError::EmailTooLong);
    }
    if !input.password.is_ascii() {
        errors.push(ValidationError::PasswordNotAscii);
    }
    if input.password.len() > 64 {
        errors.push(ValidationError::PasswordTooLong);
    }
    if input.password.len() < 8 {
        errors.push(ValidationError::PasswordTooShort);
    }
    if input.password != input.confirm_password {
        errors.push(ValidationError::PasswordMismatch);
    }
    if !errors.is_empty() {
        return Err(Error::ValidationErrorList(errors));
    }

    if app
        .database
        .get_user_from_email(input.email.as_str())
        .await
        .is_ok()
    {
        return Err(Error::UserAlreadyExists);
    }

    let hashed_password = security::hash_password(input.password.as_str());
    let user_id = app
        .database
        .create_user(input.email.as_str(), hashed_password.as_str())
        .await
        .map_err(|_| Error::FailedToCreateUser)?;

    let name = create_random_string();
    let (access_token, refresh_token, hashed_uuid_part) =
        app.jwt_manager.create(user_id, name.as_str());

    app.database
        .create_or_overwrite_refresh_token(hashed_uuid_part.as_str(), user_id, name.as_str(), false)
        .await
        .map_err(|_| Error::FailedToLogin)?;

    Ok(Json(AuthResponse {
        refresh_token,
        access_token,
    })
    .into_response())
}

#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RefreshTokenInput {
    refresh_token: String,
}

#[debug_handler]
pub async fn refresh_tokens(
    State(app): State<App>,
    Json(input): Json<RefreshTokenInput>,
) -> Result<Response, Error> {
    let (user_id, name, refresh_token) = parse_refresh_token(input.refresh_token.as_str())
        .map_err(|_| Error::InvalidRefreshToken)?;
    // Check if token is valid
    if let Ok(refresh_token_row) = app
        .database
        .get_refresh_token_from_name_user(name.as_str(), user_id)
        .await
    {
        if !security::check_password(refresh_token_row.key.as_str(), refresh_token.as_str()) {
            return Err(Error::InvalidRefreshToken);
        }

        let (new_name, is_api_key) = match refresh_token_row.expires_at {
            None => (name, true),
            Some(_) => (create_random_string(), false),
        };

        // Create new one depending on if expires_at or not
        let (new_access_token, new_refresh_token, new_hashed_uuid_part) =
            app.jwt_manager.create(user_id, new_name.as_str());
        app.database
            .create_or_overwrite_refresh_token(
                new_hashed_uuid_part.as_str(),
                user_id,
                new_name.as_str(),
                is_api_key,
            )
            .await
            .map_err(|_| Error::FailedToCreateRefreshToken)?;

        Ok(Json(AuthResponse {
            access_token: new_access_token,
            refresh_token: new_refresh_token,
        })
        .into_response())
    } else {
        Err(Error::InvalidRefreshToken)
    }
}

#[derive(serde::Serialize)]
struct Health {
    healthy: bool,
}
#[debug_handler]
pub async fn health() -> Response {
    let health = Health { healthy: true };

    (StatusCode::OK, Json(health)).into_response()
}

#[debug_handler]
pub async fn graphql(
    Extension(schema): Extension<ServiceSchema>,
    Extension(auth_status): Extension<AuthenticatedUser>,
    req: GraphQLRequest,
) -> GraphQLResponse {
    let inner_req = req.into_inner();

    schema.execute(inner_req.data(auth_status)).await.into()
}

#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LoginInput {
    email: String,
    password: String,
}
#[debug_handler]
pub async fn login(
    State(app): State<App>,
    Json(input): Json<LoginInput>,
) -> Result<Response, Error> {
    let valid_email = Regex::new(r"^[\w\.-]+@[a-zA-Z\d\.-]+\.[a-zA-Z]{2,}$")
        .unwrap()
        .is_match(input.email.as_str());
    let email_too_long = input.email.len() > 40;
    let password_ascii = input.password.is_ascii();
    let password_in_bounds = input.password.len() <= 64 && input.password.len() >= 8;
    if !valid_email || email_too_long || !password_ascii || !password_in_bounds {
        return Err(Error::InvalidLoginCredentials);
    };

    if let Ok(user) = app.database.get_user_from_email(input.email.as_str()).await {
        if !security::check_password(user.password.as_str(), input.password.as_str()) {
            return Err(Error::InvalidLoginCredentials);
        }

        let name = create_random_string();
        let (access_token, refresh_token, hashed_uuid_part) =
            app.jwt_manager.create(user.id, name.as_str());

        app.database
            .create_or_overwrite_refresh_token(
                hashed_uuid_part.as_str(),
                user.id,
                name.as_str(),
                false,
            )
            .await
            .map_err(|_| Error::FailedToLogin)?;

        Ok(Json(AuthResponse {
            refresh_token,
            access_token,
        })
        .into_response())
    } else {
        Err(Error::InvalidLoginCredentials)
    }
}

#[derive(serde::Serialize)]
struct LogoutResponse {
    success: bool,
}

#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LogoutInput {
    refresh_token: String,
}
#[debug_handler]
pub async fn logout(
    State(app): State<App>,
    Json(input): Json<LogoutInput>,
) -> Result<Response, Error> {
    // Parse refresh token to get user_id, name, and uuid part
    let (user_id, name, refresh_token) = parse_refresh_token(input.refresh_token.as_str())
        .map_err(|_| Error::InvalidRefreshToken)?;

    // Validate the refresh token exists and matches
    let refresh_token_row = app
        .database
        .get_refresh_token_from_name_user(name.as_str(), user_id)
        .await
        .map_err(|_| Error::InvalidRefreshToken)?;

    if !security::check_password(refresh_token_row.key.as_str(), refresh_token.as_str()) {
        return Err(Error::InvalidRefreshToken);
    }

    // Delete the validated refresh token
    let _ = app
        .database
        .delete_refresh_token_by_user_and_name(user_id, name.as_str())
        .await;

    Ok(Json(LogoutResponse { success: true }).into_response())
}
