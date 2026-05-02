use std::fmt::Display;
use std::sync::OnceLock;

use crate::{
    router::App,
    security::{
        self, jwt::create_random_string, parse_refresh_token, ACCESS_TOKEN_LIFETIME_SECONDS,
        REFRESH_TOKEN_LIFETIME_SECONDS,
    },
};
use axum::{
    debug_handler,
    extract::State,
    http::{header::SET_COOKIE, HeaderMap, HeaderValue, StatusCode},
    response::{IntoResponse, Response},
    Json,
};
use convert_case::Casing;
use regex::Regex;

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
    // Keep cookie expiry aligned with the backend JWT lifetime.
    headers.append(
        SET_COOKIE,
        create_auth_cookie("access_token", access_token, ACCESS_TOKEN_LIFETIME_SECONDS),
    );
    // Keep cookie expiry aligned with the database-backed refresh token lifetime.
    headers.append(
        SET_COOKIE,
        create_auth_cookie("refresh_token", refresh_token, REFRESH_TOKEN_LIFETIME_SECONDS),
    );
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

fn extract_access_token_from_headers(headers: &HeaderMap) -> Option<&str> {
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

    jwt_from_header.or(jwt_from_cookie)
}

fn authenticated_user_id_from_headers(app: &App, headers: &HeaderMap) -> Result<uuid::Uuid, Error> {
    let jwt = extract_access_token_from_headers(headers).ok_or(Error::Unauthorized)?;
    app.jwt_manager.validate(jwt).ok_or(Error::Unauthorized)
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
    Unauthorized,
    IncorrectPassword,
    FailedToChangePassword,
    FailedToChangeEmail,
    FailedToLinkAppleSubscription,
    SubscriptionAlreadyLinked,
}
impl Error {
    fn status_code(&self) -> StatusCode {
        match self {
            Self::ValidationErrorList(_) => StatusCode::BAD_REQUEST, // The outer match arm dissalows this
            Self::FailedToRegister => StatusCode::BAD_REQUEST,
            Self::FailedToChangePassword => StatusCode::BAD_REQUEST,
            Self::FailedToChangeEmail => StatusCode::BAD_REQUEST,
            Self::SubscriptionAlreadyLinked => StatusCode::CONFLICT,

            Self::FailedToCreateUser => StatusCode::INTERNAL_SERVER_ERROR,
            Self::FailedToLogin => StatusCode::INTERNAL_SERVER_ERROR,
            Self::FailedToCreateRefreshToken => StatusCode::INTERNAL_SERVER_ERROR,
            Self::FailedToLinkAppleSubscription => StatusCode::INTERNAL_SERVER_ERROR,

            Self::InvalidRefreshToken => StatusCode::UNAUTHORIZED,
            Self::InvalidLoginCredentials => StatusCode::UNAUTHORIZED,
            Self::Unauthorized => StatusCode::UNAUTHORIZED,
            Self::IncorrectPassword => StatusCode::UNAUTHORIZED,
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

            Self::Unauthorized => write!(f, "Unauthorized."),
            Self::IncorrectPassword => write!(f, "Incorrect password."),
            Self::FailedToChangePassword => {
                write!(f, "Failed to change password. Please try again.")
            }
            Self::FailedToChangeEmail => {
                write!(f, "Failed to change email. Please try again.")
            }
            Self::FailedToLinkAppleSubscription => {
                write!(f, "Failed to link Apple subscription. Please try again.")
            }
            Self::SubscriptionAlreadyLinked => {
                write!(
                    f,
                    "This Apple subscription is already linked to another account."
                )
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
    NewPasswordSameAsOld,
    NewEmailSameAsOld,
    OriginalTransactionIdMissing,
    OriginalTransactionIdTooLong,
    InvalidSubscriptionExpiresAt,
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
            Self::NewPasswordSameAsOld => write!(f,
                 "New password must be different from current password."
            ),
            Self::NewEmailSameAsOld => write!(f,
                 "New email must be different from current email."
            ),
            Self::OriginalTransactionIdMissing => write!(f,
                 "Original transaction ID is required."
            ),
            Self::OriginalTransactionIdTooLong => write!(f,
                 "Original transaction ID too long."
            ),
            Self::InvalidSubscriptionExpiresAt => write!(f,
                 "Subscription expiry timestamp is invalid."
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

    let (user_id, name, refresh_token) =
        parse_refresh_token(token.as_str()).map_err(|_| Error::InvalidRefreshToken)?;
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

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct MeResponse {
    email: Option<String>,
    subscription_source: Option<String>,
    subscription_status: String,
    is_entitled: bool,
    subscription_expires_at: Option<chrono::NaiveDateTime>,
}

fn me_response_from_account_state(
    account_state: crate::database::UserAccountStateRow,
) -> MeResponse {
    MeResponse {
        email: account_state.email,
        subscription_source: account_state.subscription_source,
        subscription_status: account_state.subscription_status.clone(),
        is_entitled: subscription_is_entitled(
            account_state.subscription_status.as_str(),
            account_state.subscription_expires_at,
        ),
        subscription_expires_at: account_state.subscription_expires_at,
    }
}

fn parse_client_subscription_timestamp(value: &str) -> Option<chrono::NaiveDateTime> {
    chrono::DateTime::parse_from_rfc3339(value)
        .map(|date_time| date_time.naive_utc())
        .ok()
        .or_else(|| chrono::NaiveDateTime::parse_from_str(value, "%Y-%m-%dT%H:%M:%S%.f").ok())
        .or_else(|| chrono::NaiveDateTime::parse_from_str(value, "%Y-%m-%dT%H:%M:%S").ok())
}

fn subscription_is_entitled(
    subscription_status: &str,
    subscription_expires_at: Option<chrono::NaiveDateTime>,
) -> bool {
    matches!(subscription_status, "active" | "grace_period")
        || matches!(
            (subscription_status, subscription_expires_at),
            ("active", Some(_)) | ("grace_period", Some(_))
        )
}

#[debug_handler]
pub async fn me(State(app): State<App>, headers: HeaderMap) -> Result<Response, Error> {
    let user_id = authenticated_user_id_from_headers(&app, &headers)?;

    let account_state = app
        .database
        .get_user_account_state(user_id)
        .await
        .map_err(|_| Error::Unauthorized)?;

    Ok(Json(me_response_from_account_state(account_state)).into_response())
}

#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LinkAppleSubscriptionInput {
    original_transaction_id: String,
    subscription_expires_at: Option<String>,
}

#[debug_handler]
pub async fn link_apple_subscription(
    State(app): State<App>,
    headers: HeaderMap,
    Json(input): Json<LinkAppleSubscriptionInput>,
) -> Result<Response, Error> {
    let user_id = authenticated_user_id_from_headers(&app, &headers)?;

    let mut errors = vec![];
    if input.original_transaction_id.trim().is_empty() {
        errors.push(ValidationError::OriginalTransactionIdMissing);
    }
    if input.original_transaction_id.len() > 255 {
        errors.push(ValidationError::OriginalTransactionIdTooLong);
    }
    let subscription_expires_at = match input.subscription_expires_at.as_deref() {
        Some(value) => match parse_client_subscription_timestamp(value) {
            Some(parsed) => Some(parsed),
            None => {
                errors.push(ValidationError::InvalidSubscriptionExpiresAt);
                None
            }
        },
        None => None,
    };

    if !errors.is_empty() {
        return Err(Error::ValidationErrorList(errors));
    }

    if let Some(existing_user_id) = app
        .database
        .get_user_id_from_app_store_original_transaction_id(input.original_transaction_id.as_str())
        .await
        .map_err(|_| Error::FailedToLinkAppleSubscription)?
    {
        if existing_user_id != user_id {
            return Err(Error::SubscriptionAlreadyLinked);
        }
    }

    let subscription_status = if subscription_expires_at
        .map(|expires_at| expires_at > chrono::Utc::now().naive_utc())
        .unwrap_or(true)
    {
        "active"
    } else {
        "expired"
    };

    let account_state = app
        .database
        .link_apple_subscription(
            user_id,
            input.original_transaction_id.as_str(),
            subscription_status,
            subscription_expires_at,
        )
        .await
        .map_err(|_| Error::FailedToLinkAppleSubscription)?;

    Ok(Json(me_response_from_account_state(account_state)).into_response())
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
        let stored_password = user
            .password
            .as_deref()
            .ok_or(Error::InvalidLoginCredentials)?;
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
    let (user_id, name, refresh_token) =
        parse_refresh_token(token.as_str()).map_err(|_| Error::InvalidRefreshToken)?;

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
pub struct ChangePasswordInput {
    current_password: String,
    new_password: String,
}

#[derive(serde::Serialize)]
struct ChangePasswordResponse {
    success: bool,
}

#[debug_handler]
pub async fn change_password(
    State(app): State<App>,
    headers: HeaderMap,
    Json(input): Json<ChangePasswordInput>,
) -> Result<Response, Error> {
    let user_id = authenticated_user_id_from_headers(&app, &headers)?;

    // Validate new password
    let mut errors = vec![];
    if !input.new_password.is_ascii() {
        errors.push(ValidationError::PasswordNotAscii);
    }
    if input.new_password.len() > 64 {
        errors.push(ValidationError::PasswordTooLong);
    }
    if input.new_password.len() < 8 {
        errors.push(ValidationError::PasswordTooShort);
    }
    if input.current_password == input.new_password {
        errors.push(ValidationError::NewPasswordSameAsOld);
    }
    if !errors.is_empty() {
        return Err(Error::ValidationErrorList(errors));
    }

    // Get user from database
    let user = app
        .database
        .get_user_by_id(user_id)
        .await
        .map_err(|_| Error::Unauthorized)?;

    // Verify current password
    let stored_password = user.password.ok_or(Error::FailedToChangePassword)?;
    if !security::check_password(&stored_password, &input.current_password) {
        return Err(Error::IncorrectPassword);
    }

    // Hash and update password
    let hashed_password = security::hash_password(&input.new_password);
    app.database
        .update_user_password(user_id, &hashed_password)
        .await
        .map_err(|_| Error::FailedToChangePassword)?;

    Ok(Json(ChangePasswordResponse { success: true }).into_response())
}

#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ChangeEmailInput {
    new_email: String,
    password: String,
}

#[derive(serde::Serialize)]
struct ChangeEmailResponse {
    success: bool,
}

#[debug_handler]
pub async fn change_email(
    State(app): State<App>,
    headers: HeaderMap,
    Json(input): Json<ChangeEmailInput>,
) -> Result<Response, Error> {
    let user_id = authenticated_user_id_from_headers(&app, &headers)?;

    // Validate new email
    let mut errors = vec![];
    let is_valid_email = email_regex().is_match(input.new_email.as_str());
    if !is_valid_email {
        errors.push(ValidationError::InvalidEmailAddress);
    }
    if input.new_email.len() > 254 {
        errors.push(ValidationError::EmailTooLong);
    }
    if !errors.is_empty() {
        return Err(Error::ValidationErrorList(errors));
    }

    // Get user from database
    let user = app
        .database
        .get_user_by_id(user_id)
        .await
        .map_err(|_| Error::Unauthorized)?;

    // Check if new email is same as current
    if user.email.as_deref() == Some(input.new_email.as_str()) {
        return Err(Error::ValidationErrorList(vec![
            ValidationError::NewEmailSameAsOld,
        ]));
    }

    // Verify password
    let stored_password = user.password.ok_or(Error::FailedToChangeEmail)?;
    if !security::check_password(&stored_password, &input.password) {
        return Err(Error::IncorrectPassword);
    }

    // Check if email already exists (return generic error to prevent enumeration)
    if app
        .database
        .get_user_from_email(&input.new_email)
        .await
        .is_ok()
    {
        return Err(Error::FailedToChangeEmail);
    }

    // Update email
    app.database
        .update_user_email(user_id, &input.new_email)
        .await
        .map_err(|_| Error::FailedToChangeEmail)?;

    Ok(Json(ChangeEmailResponse { success: true }).into_response())
}
