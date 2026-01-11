use std::fmt::Display;
use std::sync::OnceLock;

use crate::{
    graphql::{mutations::MutationRoot, queries::QueryRoot},
    router::{App, AuthenticatedUser},
    security::{self, jwt::create_random_string, parse_refresh_token},
};
use async_graphql::{EmptySubscription, Schema};
use async_graphql_axum::{GraphQLRequest, GraphQLResponse};
use axum::{
    debug_handler,
    extract::State,
    http::{header::SET_COOKIE, HeaderMap, HeaderValue, StatusCode},
    response::{IntoResponse, Response},
    Extension, Json,
};
use convert_case::Casing;
use regex::Regex;
use tracing::info;

/// Create a secure HttpOnly cookie for auth tokens
fn create_auth_cookie(name: &str, value: &str, max_age_seconds: i64) -> HeaderValue {
    let cookie = format!(
        "{}={}; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age={}",
        name, value, max_age_seconds
    );
    HeaderValue::from_str(&cookie).unwrap()
}

/// Create a cookie that clears an existing cookie
fn create_clear_cookie(name: &str) -> HeaderValue {
    let cookie = format!(
        "{}=; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=0",
        name
    );
    HeaderValue::from_str(&cookie).unwrap()
}

/// Build headers with auth cookies set
fn auth_cookie_headers(access_token: &str, refresh_token: &str) -> HeaderMap {
    let mut headers = HeaderMap::new();
    // Access token expires in 15 minutes (900 seconds)
    headers.append(SET_COOKIE, create_auth_cookie("access_token", access_token, 900));
    // Refresh token expires in 7 days (604800 seconds)
    headers.append(SET_COOKIE, create_auth_cookie("refresh_token", refresh_token, 604800));
    headers
}

/// Build headers that clear auth cookies
fn clear_auth_cookie_headers() -> HeaderMap {
    let mut headers = HeaderMap::new();
    headers.append(SET_COOKIE, create_clear_cookie("access_token"));
    headers.append(SET_COOKIE, create_clear_cookie("refresh_token"));
    headers
}

/// Extract refresh_token from Cookie header
fn extract_refresh_token_from_cookies(headers: &HeaderMap) -> Option<String> {
    headers
        .get(axum::http::header::COOKIE)
        .and_then(|v| v.to_str().ok())
        .and_then(|cookie_header| {
            cookie_header
                .split(';')
                .map(|s| s.trim())
                .find(|s| s.starts_with("refresh_token="))
                .and_then(|s| s.strip_prefix("refresh_token="))
                .map(|s| s.to_string())
        })
}

fn email_regex() -> &'static Regex {
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| Regex::new(r"^[\w\.-]+@[a-zA-Z\d\.-]+\.[a-zA-Z]{2,}$").unwrap())
}

#[derive(Debug, serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct AuthResponse {
    refresh_token: String,
    access_token: String,
}

#[derive(Debug, serde::Serialize)]
pub enum Error {
    ValidationErrorList(Vec<ValidationError>),
    FailedToRegister,
    FailedToLogin,
    FailedToCreateRefreshToken,
    FailedToCreateUser,
    InvalidRefreshToken,
    InvalidLoginCredentials,
    InvalidDeviceId,
    FailedToCreateAnonymousUser,
    FailedToClaim,
    AccountAlreadyClaimed,
    Unauthorized,
}
impl Error {
    fn status_code(&self) -> StatusCode {
        match self {
            Self::ValidationErrorList(_) => StatusCode::BAD_REQUEST, // The outer match arm dissalows this
            Self::FailedToRegister => StatusCode::BAD_REQUEST,
            Self::InvalidDeviceId => StatusCode::BAD_REQUEST,
            Self::FailedToClaim => StatusCode::BAD_REQUEST,
            Self::AccountAlreadyClaimed => StatusCode::BAD_REQUEST,

            Self::FailedToCreateUser => StatusCode::INTERNAL_SERVER_ERROR,
            Self::FailedToLogin => StatusCode::INTERNAL_SERVER_ERROR,
            Self::FailedToCreateRefreshToken => StatusCode::INTERNAL_SERVER_ERROR,
            Self::FailedToCreateAnonymousUser => StatusCode::INTERNAL_SERVER_ERROR,

            Self::InvalidRefreshToken => StatusCode::UNAUTHORIZED,
            Self::InvalidLoginCredentials => StatusCode::UNAUTHORIZED,
            Self::Unauthorized => StatusCode::UNAUTHORIZED,
        }
    }
}
impl Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::ValidationErrorList(_) => panic!(), // The outer match arm dissalows this
            Self::FailedToRegister => write!(f, "Registration failed. Please try again."),

            Self::FailedToCreateUser => write!(f, "Failed to create user."),
            Self::FailedToLogin => write!(f, "Failed to login user."),
            Self::FailedToCreateRefreshToken => {
                write!(f, "Failed to create refresh token.")
            }

            Self::InvalidRefreshToken => write!(f, "Invalid refresh token."),
            Self::InvalidLoginCredentials => {
                write!(f, "Incorrect email or password.")
            }

            Self::InvalidDeviceId => write!(f, "Invalid device ID. Must be a valid UUID."),
            Self::FailedToCreateAnonymousUser => write!(f, "Failed to create anonymous user."),
            Self::FailedToClaim => write!(f, "Failed to claim account. Please try again."),
            Self::AccountAlreadyClaimed => {
                write!(f, "Account has already been claimed.")
            }
            Self::Unauthorized => write!(f, "Unauthorized."),
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
}
impl Display for ValidationError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::InvalidEmailAddress => write!(f, "Invalid email address."),
            Self::PasswordNotAscii => write!(f,
                 "Password must contain only standard English letters, numbers, and common punctuation."
            ),
            Self::EmailTooLong => write!(f,
                "Email too long. The maximum email length is 254."
            ),
            Self::PasswordTooLong => write!(f,
                 "Password too long. The maximum password length is 64."
            ),
            Self::PasswordTooShort => write!(f,
                 "Password too short. The min password length is 8."
            ),
        }
    }
}

#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RegisterInput {
    email: String,
    password: String,
}
#[debug_handler]
pub async fn register(
    State(app): State<App>,
    Json(input): Json<RegisterInput>,
) -> Result<Response, Error> {
    let mut errors = vec![];
    let is_valid_email = email_regex().is_match(input.email.as_str());
    if !is_valid_email {
        errors.push(ValidationError::InvalidEmailAddress);
    }
    if input.email.len() > 254 {
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
    if !errors.is_empty() {
        return Err(Error::ValidationErrorList(errors));
    }

    // Return generic error to prevent email enumeration
    if app
        .database
        .get_user_from_email(input.email.as_str())
        .await
        .is_ok()
    {
        return Err(Error::FailedToRegister);
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

    let cookie_headers = auth_cookie_headers(&access_token, &refresh_token);
    Ok((
        cookie_headers,
        Json(AuthResponse {
            refresh_token,
            access_token,
        }),
    )
        .into_response())
}

#[derive(serde::Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct RefreshTokenInput {
    refresh_token: Option<String>,
}

#[debug_handler]
pub async fn refresh_tokens(
    State(app): State<App>,
    headers: HeaderMap,
    Json(input): Json<RefreshTokenInput>,
) -> Result<Response, Error> {
    // Try body first, fall back to cookie
    let token = input
        .refresh_token
        .or_else(|| extract_refresh_token_from_cookies(&headers))
        .ok_or(Error::InvalidRefreshToken)?;

    let (user_id, name, refresh_token) = parse_refresh_token(token.as_str())
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

        let cookie_headers = auth_cookie_headers(&new_access_token, &new_refresh_token);
        Ok((
            cookie_headers,
            Json(AuthResponse {
                access_token: new_access_token,
                refresh_token: new_refresh_token,
            }),
        )
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

pub type ServiceSchema = Schema<QueryRoot, MutationRoot, EmptySubscription>;

#[debug_handler]
pub async fn graphql(
    Extension(schema): Extension<ServiceSchema>,
    Extension(auth_status): Extension<AuthenticatedUser>,
    req: GraphQLRequest,
) -> GraphQLResponse {
    let inner_req = req.into_inner();
    let operation_name = inner_req
        .operation_name
        .as_deref()
        .unwrap_or("unnamed_operation");

    info!(graphql.operation_name = operation_name, "GraphQL operation",);

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
    let valid_email = email_regex().is_match(input.email.as_str());
    let email_too_long = input.email.len() > 254;
    let password_ascii = input.password.is_ascii();
    let password_in_bounds = input.password.len() <= 64 && input.password.len() >= 8;
    if !valid_email || email_too_long || !password_ascii || !password_in_bounds {
        return Err(Error::InvalidLoginCredentials);
    };

    if let Ok(user) = app.database.get_user_from_email(input.email.as_str()).await {
        // Anonymous users don't have a password, so they can't login with password
        let stored_password = user.password.as_deref().ok_or(Error::InvalidLoginCredentials)?;
        if !security::check_password(stored_password, input.password.as_str()) {
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

        let cookie_headers = auth_cookie_headers(&access_token, &refresh_token);
        Ok((
            cookie_headers,
            Json(AuthResponse {
                refresh_token,
                access_token,
            }),
        )
            .into_response())
    } else {
        Err(Error::InvalidLoginCredentials)
    }
}

#[derive(serde::Serialize)]
struct LogoutResponse {
    success: bool,
}

#[derive(serde::Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct LogoutInput {
    refresh_token: Option<String>,
}
#[debug_handler]
pub async fn logout(
    State(app): State<App>,
    headers: HeaderMap,
    Json(input): Json<LogoutInput>,
) -> Result<Response, Error> {
    // Try body first, fall back to cookie
    let token = input
        .refresh_token
        .or_else(|| extract_refresh_token_from_cookies(&headers))
        .ok_or(Error::InvalidRefreshToken)?;

    // Parse refresh token to get user_id, name, and uuid part
    let (user_id, name, refresh_token) = parse_refresh_token(token.as_str())
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

    let clear_headers = clear_auth_cookie_headers();
    Ok((clear_headers, Json(LogoutResponse { success: true })).into_response())
}

#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AnonymousInput {
    device_id: String,
}
#[debug_handler]
pub async fn anonymous(
    State(app): State<App>,
    Json(input): Json<AnonymousInput>,
) -> Result<Response, Error> {
    // Validate device_id is a valid UUID
    let device_id = uuid::Uuid::parse_str(&input.device_id).map_err(|_| Error::InvalidDeviceId)?;

    // Check if user with this device_id already exists
    let user_id = if let Ok(user) = app.database.get_user_from_device_id(device_id).await {
        // User already exists, return their tokens
        user.id
    } else {
        // Create new anonymous user
        app.database
            .create_anonymous_user(device_id)
            .await
            .map_err(|_| Error::FailedToCreateAnonymousUser)?
    };

    // Create tokens for the user
    let name = create_random_string();
    let (access_token, refresh_token, hashed_uuid_part) =
        app.jwt_manager.create(user_id, name.as_str());

    app.database
        .create_or_overwrite_refresh_token(hashed_uuid_part.as_str(), user_id, name.as_str(), false)
        .await
        .map_err(|_| Error::FailedToCreateRefreshToken)?;

    let cookie_headers = auth_cookie_headers(&access_token, &refresh_token);
    Ok((
        cookie_headers,
        Json(AuthResponse {
            refresh_token,
            access_token,
        }),
    )
        .into_response())
}

#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ClaimInput {
    email: String,
    password: String,
}
#[debug_handler]
pub async fn claim(
    State(app): State<App>,
    headers: HeaderMap,
    Json(input): Json<ClaimInput>,
) -> Result<Response, Error> {
    // Extract user_id from access token (from header or cookie)
    let jwt_from_header = headers
        .get(axum::http::header::AUTHORIZATION)
        .and_then(|header_value| header_value.to_str().ok())
        .and_then(|header| header.strip_prefix("Bearer "));

    let jwt_from_cookie = headers
        .get(axum::http::header::COOKIE)
        .and_then(|header_value| header_value.to_str().ok())
        .and_then(|cookie_header| {
            cookie_header
                .split(';')
                .map(|s| s.trim())
                .find(|s| s.starts_with("access_token="))
                .and_then(|s| s.strip_prefix("access_token="))
        });

    let jwt = jwt_from_header.or(jwt_from_cookie).ok_or(Error::Unauthorized)?;
    let user_id = app.jwt_manager.validate(jwt).ok_or(Error::Unauthorized)?;

    // Validate email and password
    let mut errors = vec![];
    let is_valid_email = email_regex().is_match(input.email.as_str());
    if !is_valid_email {
        errors.push(ValidationError::InvalidEmailAddress);
    }
    if input.email.len() > 254 {
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
    if !errors.is_empty() {
        return Err(Error::ValidationErrorList(errors));
    }

    // Check if user is anonymous
    let is_anonymous = app
        .database
        .is_user_anonymous(user_id)
        .await
        .map_err(|_| Error::Unauthorized)?;

    if !is_anonymous {
        return Err(Error::AccountAlreadyClaimed);
    }

    // Check if email already exists (return generic error to prevent enumeration)
    if app.database.get_user_from_email(&input.email).await.is_ok() {
        return Err(Error::FailedToClaim);
    }

    // Claim the account
    let hashed_password = security::hash_password(input.password.as_str());
    app.database
        .claim_account(user_id, &input.email, &hashed_password)
        .await
        .map_err(|_| Error::FailedToClaim)?;

    // Create new tokens for the claimed account
    let name = create_random_string();
    let (access_token, refresh_token, hashed_uuid_part) =
        app.jwt_manager.create(user_id, name.as_str());

    app.database
        .create_or_overwrite_refresh_token(hashed_uuid_part.as_str(), user_id, name.as_str(), false)
        .await
        .map_err(|_| Error::FailedToCreateRefreshToken)?;

    let cookie_headers = auth_cookie_headers(&access_token, &refresh_token);
    Ok((
        cookie_headers,
        Json(AuthResponse {
            refresh_token,
            access_token,
        }),
    )
        .into_response())
}
