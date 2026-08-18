use std::fmt::{Debug, Display};

use crate::{
    billing,
    error_context::{is_row_not_found, is_unique_violation, log_sqlx_error, warn_sqlx_error},
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
    response::{Html, IntoResponse, Response},
    Json,
};
use convert_case::Casing;
use jsonwebtoken::{
    decode, decode_header, encode, Algorithm, DecodingKey, EncodingKey, Header, Validation,
};
use sha2::{Digest, Sha256};
use tracing::{error, info, warn, Span};

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
        create_auth_cookie(
            "refresh_token",
            refresh_token,
            REFRESH_TOKEN_LIFETIME_SECONDS,
        ),
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

fn extract_access_token_from_headers(headers: &HeaderMap) -> Option<(&str, &'static str)> {
    let jwt_from_header = headers
        .get(axum::http::header::AUTHORIZATION)
        .and_then(|header_value| header_value.to_str().ok())
        .and_then(|header| header.strip_prefix("Bearer "))
        .map(|token| (token, "authorization_header"));

    let jwt_from_cookie = headers
        .get(axum::http::header::COOKIE)
        .and_then(|header_value| header_value.to_str().ok())
        .and_then(|cookie_header| {
            cookie_header
                .split(';')
                .map(|s| s.trim())
                .find(|s| s.starts_with("access_token="))
                .and_then(|s| s.strip_prefix("access_token="))
        })
        .map(|token| (token, "cookie"));

    jwt_from_header.or(jwt_from_cookie)
}

fn authenticated_user_id_from_headers(app: &App, headers: &HeaderMap) -> Result<uuid::Uuid, Error> {
    let (jwt, auth_source) = extract_access_token_from_headers(headers).ok_or_else(|| {
        Span::current().record("auth_failure", "missing_token");
        warn!("auth endpoint rejected request without an access token");
        Error::Unauthorized
    })?;

    app.jwt_manager
        .validate(jwt)
        .inspect(|user_id| {
            let span = Span::current();
            span.record("user_id", tracing::field::display(user_id));
            span.record("auth_source", auth_source);
        })
        .ok_or_else(|| {
            let span = Span::current();
            span.record("auth_source", auth_source);
            span.record("auth_failure", "invalid_token");
            warn!(auth_source, "auth endpoint rejected invalid access token");
            Error::Unauthorized
        })
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
    FailedToLoadAccount,
    FailedToLoadRefreshToken,
    FailedToSignInWithApple,
    FailedToCreateRefreshToken,
    FailedToCreateUser,
    InvalidRefreshToken,
    InvalidAppleIdentityToken,
    InvalidAppleBillingPayload,
    Unauthorized,
    FailedToLinkAppleSubscription,
    SubscriptionAlreadyLinked,
    FailedToProcessAppleNotification,
    FailedToDeleteAccount,
}
impl Error {
    fn status_code(&self) -> StatusCode {
        match self {
            Self::ValidationErrorList(_) => StatusCode::BAD_REQUEST, // The outer match arm dissalows this
            Self::SubscriptionAlreadyLinked => StatusCode::CONFLICT,
            Self::InvalidAppleBillingPayload => StatusCode::BAD_REQUEST,

            Self::FailedToLoadAccount => StatusCode::INTERNAL_SERVER_ERROR,
            Self::FailedToLoadRefreshToken => StatusCode::INTERNAL_SERVER_ERROR,
            Self::FailedToCreateUser => StatusCode::INTERNAL_SERVER_ERROR,
            Self::FailedToSignInWithApple => StatusCode::INTERNAL_SERVER_ERROR,
            Self::FailedToCreateRefreshToken => StatusCode::INTERNAL_SERVER_ERROR,
            Self::FailedToLinkAppleSubscription => StatusCode::INTERNAL_SERVER_ERROR,
            Self::FailedToProcessAppleNotification => StatusCode::INTERNAL_SERVER_ERROR,
            Self::FailedToDeleteAccount => StatusCode::INTERNAL_SERVER_ERROR,

            Self::InvalidRefreshToken => StatusCode::UNAUTHORIZED,
            Self::InvalidAppleIdentityToken => StatusCode::UNAUTHORIZED,
            Self::Unauthorized => StatusCode::UNAUTHORIZED,
        }
    }

    fn code(&self) -> String {
        match self {
            Self::ValidationErrorList(_) => "VALIDATION_ERROR".to_string(),
            _ => error_code_from_debug(self),
        }
    }

    fn log_response(&self, status: StatusCode) {
        let error_code = self.code();
        if status.is_server_error() {
            error!(
                status_code = status.as_u16(),
                error_code,
                error_message = %self,
                "auth request failed"
            );
        } else {
            warn!(
                status_code = status.as_u16(),
                error_code,
                error_message = %self,
                "auth request rejected"
            );
        }
    }
}
impl Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::ValidationErrorList(_) => panic!(), // The outer match arm dissalows this

            Self::FailedToLoadAccount => write!(f, "Failed to load account."),
            Self::FailedToLoadRefreshToken => write!(f, "Failed to load refresh token."),
            Self::FailedToCreateUser => write!(f, "Failed to create user."),
            Self::FailedToSignInWithApple => write!(f, "Failed to sign in with Apple."),
            Self::FailedToCreateRefreshToken => {
                write!(f, "Failed to create refresh token.")
            }

            Self::InvalidRefreshToken => write!(f, "Invalid refresh token."),
            Self::InvalidAppleIdentityToken => {
                write!(f, "Invalid Apple identity token.")
            }
            Self::InvalidAppleBillingPayload => {
                write!(f, "Invalid Apple billing payload.")
            }

            Self::Unauthorized => write!(f, "Unauthorized."),
            Self::FailedToLinkAppleSubscription => {
                write!(f, "Failed to link Apple subscription. Please try again.")
            }
            Self::SubscriptionAlreadyLinked => {
                write!(
                    f,
                    "This Apple subscription is already linked to another account."
                )
            }
            Self::FailedToProcessAppleNotification => {
                write!(f, "Failed to process Apple billing notification.")
            }
            Self::FailedToDeleteAccount => write!(f, "Failed to delete account."),
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
                code: value.code(),
                message: value.to_string(),
            },
        }
    }
}
impl From<ValidationError> for ErrorDetail {
    fn from(value: ValidationError) -> Self {
        ErrorDetail {
            code: value.code(),
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
                let validation_error_codes: Vec<String> =
                    error_list.iter().map(ValidationError::code).collect();
                warn!(
                    status_code = StatusCode::BAD_REQUEST.as_u16(),
                    error_code = "VALIDATION_ERROR",
                    validation_error_codes = ?validation_error_codes,
                    "auth request rejected"
                );

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
                self.log_response(code);
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
    OriginalTransactionIdMissing,
    OriginalTransactionIdTooLong,
    ProductIdTooLong,
    ProductIdMissing,
    InvalidProductId,
    TransactionIdMissing,
    TransactionIdTooLong,
    InvalidAppStoreEnvironment,
    InvalidSubscriptionExpiresAt,
}
impl ValidationError {
    fn code(&self) -> String {
        error_code_from_debug(self)
    }
}

fn error_code_from_debug(value: &impl Debug) -> String {
    format!("{:?}", value).to_case(convert_case::Case::ScreamingSnake)
}
impl Display for ValidationError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::OriginalTransactionIdMissing => write!(f, "Original transaction ID is required."),
            Self::OriginalTransactionIdTooLong => write!(f, "Original transaction ID too long."),
            Self::ProductIdTooLong => write!(f, "Product ID too long."),
            Self::ProductIdMissing => write!(f, "Product ID is required."),
            Self::InvalidProductId => write!(f, "Product ID is not a Bochi premium product."),
            Self::TransactionIdMissing => write!(f, "Transaction ID is required."),
            Self::TransactionIdTooLong => write!(f, "Transaction ID too long."),
            Self::InvalidAppStoreEnvironment => write!(f, "App Store environment is invalid."),
            Self::InvalidSubscriptionExpiresAt => {
                write!(f, "Subscription expiry timestamp is invalid.")
            }
        }
    }
}

#[derive(Debug, serde::Deserialize)]
struct AppleIdentityClaims {
    iss: String,
    aud: String,
    exp: i64,
    sub: String,
    email: Option<String>,
    nonce: Option<String>,
}

#[derive(Debug)]
struct VerifiedAppleIdentity {
    apple_user_id: String,
    email: Option<String>,
}

fn sha256_hex(value: &str) -> String {
    let digest = Sha256::digest(value.as_bytes());
    hex::encode(digest)
}

fn log_value_hash(value: &str) -> String {
    sha256_hex(value).chars().take(16).collect()
}

fn internal_auth_error(operation: &'static str, error: impl Debug, public_error: Error) -> Error {
    error!(
        operation,
        error = ?error,
        "internal auth operation failed"
    );
    public_error
}

fn verify_test_apple_identity_token(token: &str) -> Option<VerifiedAppleIdentity> {
    let test_mode = std::env::var("ALLOW_INSECURE_APPLE_SIGN_IN_TEST_TOKENS").ok()?;
    if test_mode != "true" {
        return None;
    }

    token
        .strip_prefix("test-apple-subject:")
        .filter(|subject| !subject.trim().is_empty())
        .map(|subject| VerifiedAppleIdentity {
            apple_user_id: subject.to_string(),
            email: None,
        })
}

fn apple_sign_in_audience_env() -> Result<String, std::env::VarError> {
    std::env::var("APPLE_SIGN_IN_AUDIENCE")
}

fn apple_sign_in_audience() -> Result<String, Error> {
    apple_sign_in_audience_env().map_err(|error| {
        internal_auth_error(
            "auth.apple_sign_in_audience",
            error,
            Error::InvalidAppleIdentityToken,
        )
    })
}

#[derive(Debug)]
enum AppleSignInTokenError {
    MissingConfig(&'static str),
    InvalidPrivateKey(jsonwebtoken::errors::Error),
    BuildClientSecret(jsonwebtoken::errors::Error),
    Request(ureq::Error),
    ReadResponse(std::io::Error),
    DecodeResponse(serde_json::Error),
}
impl Display for AppleSignInTokenError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::MissingConfig(key) => write!(f, "missing Apple Sign in config: {key}"),
            Self::InvalidPrivateKey(error) => {
                write!(f, "invalid Apple Sign in private key: {error}")
            }
            Self::BuildClientSecret(error) => {
                write!(f, "failed to build Apple Sign in client secret: {error}")
            }
            Self::Request(error) => write!(f, "Apple Sign in request failed: {error}"),
            Self::ReadResponse(error) => {
                write!(f, "failed to read Apple Sign in response: {error}")
            }
            Self::DecodeResponse(error) => {
                write!(f, "failed to decode Apple Sign in response: {error}")
            }
        }
    }
}

#[derive(serde::Serialize)]
struct AppleClientSecretClaims {
    iss: String,
    iat: i64,
    exp: i64,
    aud: &'static str,
    sub: String,
}

#[derive(serde::Deserialize)]
struct AppleTokenResponse {
    refresh_token: Option<String>,
}

fn apple_sign_in_token_request_audience() -> Result<String, AppleSignInTokenError> {
    apple_sign_in_audience_env()
        .map_err(|_| AppleSignInTokenError::MissingConfig("APPLE_SIGN_IN_AUDIENCE"))
}

fn normalized_apple_private_key() -> Result<String, AppleSignInTokenError> {
    std::env::var("APPLE_SIGN_IN_PRIVATE_KEY")
        .map(|value| value.replace("\\n", "\n"))
        .map_err(|_| AppleSignInTokenError::MissingConfig("APPLE_SIGN_IN_PRIVATE_KEY"))
}

fn apple_sign_in_client_secret(audience: &str) -> Result<String, AppleSignInTokenError> {
    let team_id = std::env::var("APPLE_SIGN_IN_TEAM_ID")
        .map_err(|_| AppleSignInTokenError::MissingConfig("APPLE_SIGN_IN_TEAM_ID"))?;
    let key_id = std::env::var("APPLE_SIGN_IN_KEY_ID")
        .map_err(|_| AppleSignInTokenError::MissingConfig("APPLE_SIGN_IN_KEY_ID"))?;
    let private_key = normalized_apple_private_key()?;
    let encoding_key = EncodingKey::from_ec_pem(private_key.as_bytes())
        .map_err(AppleSignInTokenError::InvalidPrivateKey)?;

    let now = chrono::Utc::now().timestamp();
    let claims = AppleClientSecretClaims {
        iss: team_id,
        iat: now,
        exp: now + 60 * 60 * 24 * 180,
        aud: "https://appleid.apple.com",
        sub: audience.to_string(),
    };
    let mut header = Header::new(Algorithm::ES256);
    header.kid = Some(key_id);

    encode(&header, &claims, &encoding_key).map_err(AppleSignInTokenError::BuildClientSecret)
}

fn apple_sign_in_form_body(fields: &[(&str, &str)]) -> String {
    let mut serializer = url::form_urlencoded::Serializer::new(String::new());
    for (key, value) in fields {
        serializer.append_pair(key, value);
    }
    serializer.finish()
}

fn exchange_apple_authorization_code(
    authorization_code: &str,
) -> Result<Option<String>, AppleSignInTokenError> {
    if std::env::var("ALLOW_INSECURE_APPLE_SIGN_IN_TEST_TOKENS")
        .ok()
        .as_deref()
        == Some("true")
    {
        if let Some(suffix) = authorization_code.strip_prefix("test-apple-authorization-code:") {
            return Ok(Some(format!("test-apple-refresh-token:{suffix}")));
        }
    }

    let audience = apple_sign_in_token_request_audience()?;
    let client_secret = apple_sign_in_client_secret(audience.as_str())?;
    let body = apple_sign_in_form_body(&[
        ("client_id", audience.as_str()),
        ("client_secret", client_secret.as_str()),
        ("code", authorization_code),
        ("grant_type", "authorization_code"),
    ]);
    let response = ureq::post("https://appleid.apple.com/auth/token")
        .set("Content-Type", "application/x-www-form-urlencoded")
        .send_string(body.as_str())
        .map_err(AppleSignInTokenError::Request)?;
    let response_body = response
        .into_string()
        .map_err(AppleSignInTokenError::ReadResponse)?;
    let token_response: AppleTokenResponse = serde_json::from_str(response_body.as_str())
        .map_err(AppleSignInTokenError::DecodeResponse)?;

    Ok(token_response.refresh_token)
}

fn maybe_exchange_apple_authorization_code(authorization_code: Option<&str>) -> Option<String> {
    let authorization_code = authorization_code?;
    let authorization_code_hash = log_value_hash(authorization_code);
    match exchange_apple_authorization_code(authorization_code) {
        Ok(refresh_token) => refresh_token,
        Err(error) => {
            warn!(
                operation = "auth.apple.exchange_authorization_code",
                authorization_code_hash = %authorization_code_hash,
                error = %error,
                "failed to exchange Apple authorization code for a revocable refresh token"
            );
            None
        }
    }
}

fn revoke_apple_refresh_token(refresh_token: &str) -> Result<(), AppleSignInTokenError> {
    if std::env::var("ALLOW_INSECURE_APPLE_SIGN_IN_TEST_TOKENS")
        .ok()
        .as_deref()
        == Some("true")
        && refresh_token.starts_with("test-apple-refresh-token:")
    {
        return Ok(());
    }

    let audience = apple_sign_in_token_request_audience()?;
    let client_secret = apple_sign_in_client_secret(audience.as_str())?;
    let body = apple_sign_in_form_body(&[
        ("client_id", audience.as_str()),
        ("client_secret", client_secret.as_str()),
        ("token", refresh_token),
        ("token_type_hint", "refresh_token"),
    ]);
    ureq::post("https://appleid.apple.com/auth/revoke")
        .set("Content-Type", "application/x-www-form-urlencoded")
        .send_string(body.as_str())
        .map_err(AppleSignInTokenError::Request)?;

    Ok(())
}

fn revoke_stored_apple_refresh_token(user_id: uuid::Uuid, refresh_token: Option<&str>) {
    let Some(refresh_token) = refresh_token else {
        return;
    };

    let refresh_token_hash = log_value_hash(refresh_token);
    match revoke_apple_refresh_token(refresh_token) {
        Ok(()) => {
            info!(
                operation = "auth.delete_account.revoke_apple_refresh_token",
                user_id = %user_id,
                apple_refresh_token_hash = %refresh_token_hash,
                "Apple Sign in refresh token revoked during account deletion"
            );
        }
        Err(error) => {
            warn!(
                operation = "auth.delete_account.revoke_apple_refresh_token",
                user_id = %user_id,
                apple_refresh_token_hash = %refresh_token_hash,
                error = %error,
                "failed to revoke Apple Sign in refresh token before account deletion"
            );
        }
    }
}

fn fetch_apple_jwk_set() -> Result<jsonwebtoken::jwk::JwkSet, Error> {
    let body = ureq::get("https://appleid.apple.com/auth/keys")
        .call()
        .map_err(|error| {
            warn!(
                operation = "auth.fetch_apple_jwk_set",
                error = ?error,
                "failed to fetch Apple sign-in keys"
            );
            Error::InvalidAppleIdentityToken
        })?
        .into_string()
        .map_err(|error| {
            warn!(
                operation = "auth.read_apple_jwk_set",
                error = ?error,
                "failed to read Apple sign-in keys response"
            );
            Error::InvalidAppleIdentityToken
        })?;

    serde_json::from_str(body.as_str()).map_err(|error| {
        warn!(
            operation = "auth.decode_apple_jwk_set",
            error = ?error,
            "failed to decode Apple sign-in keys response"
        );
        Error::InvalidAppleIdentityToken
    })
}

fn verify_apple_identity_token(
    identity_token: &str,
    nonce: Option<&str>,
) -> Result<VerifiedAppleIdentity, Error> {
    if let Some(identity) = verify_test_apple_identity_token(identity_token) {
        return Ok(identity);
    }

    let identity_token_hash = log_value_hash(identity_token);
    let header = decode_header(identity_token).map_err(|error| {
        warn!(
            operation = "auth.decode_apple_identity_header",
            identity_token_hash = %identity_token_hash,
            error = ?error,
            "invalid Apple identity token header"
        );
        Error::InvalidAppleIdentityToken
    })?;
    let key_id = header.kid.ok_or_else(|| {
        warn!(
            operation = "auth.decode_apple_identity_header",
            identity_token_hash = %identity_token_hash,
            "Apple identity token missing key id"
        );
        Error::InvalidAppleIdentityToken
    })?;
    let jwk_set = fetch_apple_jwk_set()?;
    let jwk = jwk_set.find(key_id.as_str()).ok_or_else(|| {
        warn!(
            operation = "auth.find_apple_identity_key",
            identity_token_hash = %identity_token_hash,
            apple_key_id = %key_id,
            "Apple identity token key id not found"
        );
        Error::InvalidAppleIdentityToken
    })?;

    let mut validation = Validation::new(Algorithm::RS256);
    let audience = apple_sign_in_audience()?;
    validation.set_audience(&[audience.as_str()]);
    validation.set_issuer(&["https://appleid.apple.com"]);

    let token_data = decode::<AppleIdentityClaims>(
        identity_token,
        &DecodingKey::from_jwk(jwk).map_err(|error| {
            warn!(
                operation = "auth.build_apple_identity_decoding_key",
                identity_token_hash = %identity_token_hash,
                apple_key_id = %key_id,
                error = ?error,
                "failed to build Apple identity decoding key"
            );
            Error::InvalidAppleIdentityToken
        })?,
        &validation,
    )
    .map_err(|error| {
        warn!(
            operation = "auth.verify_apple_identity_token",
            identity_token_hash = %identity_token_hash,
            apple_key_id = %key_id,
            error = ?error,
            "Apple identity token verification failed"
        );
        Error::InvalidAppleIdentityToken
    })?;

    if token_data.claims.iss != "https://appleid.apple.com"
        || token_data.claims.aud != audience
        || token_data.claims.exp <= chrono::Utc::now().timestamp()
    {
        warn!(
            operation = "auth.validate_apple_identity_claims",
            identity_token_hash = %identity_token_hash,
            issuer = %token_data.claims.iss,
            audience = %token_data.claims.aud,
            expires_at = token_data.claims.exp,
            "Apple identity token claims failed validation"
        );
        return Err(Error::InvalidAppleIdentityToken);
    }

    if let Some(raw_nonce) = nonce {
        let expected_nonce = sha256_hex(raw_nonce);
        if token_data.claims.nonce.as_deref() != Some(expected_nonce.as_str()) {
            warn!(
                operation = "auth.validate_apple_identity_nonce",
                identity_token_hash = %identity_token_hash,
                "Apple identity token nonce mismatch"
            );
            return Err(Error::InvalidAppleIdentityToken);
        }
    }

    Ok(VerifiedAppleIdentity {
        apple_user_id: token_data.claims.sub,
        email: token_data.claims.email,
    })
}

async fn issue_auth_tokens_for_user(app: &App, user_id: uuid::Uuid) -> Result<Response, Error> {
    let name = create_random_string();
    let (access_token, refresh_token, hashed_uuid_part) =
        app.jwt_manager.create(user_id, name.as_str());

    app.database
        .create_or_overwrite_refresh_token(hashed_uuid_part.as_str(), user_id, name.as_str(), false)
        .await
        .map_err(|error| {
            log_sqlx_error(
                "auth.create_refresh_token",
                &error,
                "failed to create refresh token",
            );
            Error::FailedToSignInWithApple
        })?;

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
pub struct SignInWithAppleInput {
    identity_token: String,
    email: Option<String>,
    nonce: Option<String>,
    authorization_code: Option<String>,
}

#[debug_handler]
#[tracing::instrument(
    name = "auth.sign_in_with_apple",
    skip(app, input),
    fields(user_id = tracing::field::Empty, apple_user_id_hash = tracing::field::Empty)
)]
pub async fn sign_in_with_apple(
    State(app): State<App>,
    Json(input): Json<SignInWithAppleInput>,
) -> Result<Response, Error> {
    let identity =
        verify_apple_identity_token(input.identity_token.as_str(), input.nonce.as_deref())?;
    let apple_user_id_hash = log_value_hash(identity.apple_user_id.as_str());
    Span::current().record("apple_user_id_hash", apple_user_id_hash.as_str());
    let email = input.email.or(identity.email);
    let apple_refresh_token =
        maybe_exchange_apple_authorization_code(input.authorization_code.as_deref());

    let existing_user = match app
        .database
        .get_user_from_apple_user_id(identity.apple_user_id.as_str())
        .await
    {
        Ok(user) => Some(user),
        Err(error) if is_row_not_found(&error) => None,
        Err(error) => {
            log_sqlx_error(
                "auth.sign_in_with_apple.load_apple_user",
                &error,
                "failed to load Apple user before sign-in",
            );
            return Err(Error::FailedToSignInWithApple);
        }
    };

    let mut account_created = false;
    let user_id = match existing_user.as_ref() {
        Some(user) => user.id,
        None => match app
            .database
            .create_apple_user(
                identity.apple_user_id.as_str(),
                email.as_deref(),
                apple_refresh_token.as_deref(),
            )
            .await
        {
            Ok(user_id) => {
                account_created = true;
                user_id
            }
            Err(create_error) if is_unique_violation(&create_error) => {
                warn_sqlx_error(
                    "auth.create_apple_user",
                    &create_error,
                    "Apple user create hit a unique constraint, checking for concurrent insert",
                );
                match app
                    .database
                    .get_user_from_apple_user_id(identity.apple_user_id.as_str())
                    .await
                {
                    Ok(user) => user.id,
                    Err(error) if is_row_not_found(&error) => {
                        warn_sqlx_error(
                            "auth.get_apple_user_after_unique_violation",
                            &error,
                            "Apple user was still missing after unique create failure",
                        );
                        return Err(Error::FailedToCreateUser);
                    }
                    Err(error) => {
                        log_sqlx_error(
                            "auth.get_apple_user_after_unique_violation",
                            &error,
                            "failed to load Apple user after unique create failure",
                        );
                        return Err(Error::FailedToCreateUser);
                    }
                }
            }
            Err(create_error) => {
                log_sqlx_error(
                    "auth.create_apple_user",
                    &create_error,
                    "failed to create Apple user",
                );
                return Err(Error::FailedToCreateUser);
            }
        },
    };
    if existing_user.is_some() {
        if let Some(apple_refresh_token) = apple_refresh_token.as_deref() {
            app.database
                .update_apple_refresh_token(user_id, apple_refresh_token)
                .await
                .map_err(|error| {
                    log_sqlx_error(
                        "auth.sign_in_with_apple.update_apple_refresh_token",
                        &error,
                        "failed to update Apple refresh token",
                    );
                    Error::FailedToSignInWithApple
                })?;
        }
    }
    Span::current().record("user_id", tracing::field::display(user_id));
    info!(
        user_id = %user_id,
        apple_user_id_hash = %apple_user_id_hash,
        account_created,
        "Apple sign-in succeeded"
    );

    issue_auth_tokens_for_user(&app, user_id).await
}

#[derive(serde::Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct RefreshTokenInput {
    refresh_token: Option<String>,
}

#[debug_handler]
#[tracing::instrument(
    name = "auth.refresh_tokens",
    skip(app, headers, input),
    fields(user_id = tracing::field::Empty, refresh_token_hash = tracing::field::Empty)
)]
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

    let refresh_token_hash = log_value_hash(token.as_str());
    Span::current().record("refresh_token_hash", refresh_token_hash.as_str());
    let (user_id, name, refresh_token) = parse_refresh_token(token.as_str()).map_err(|error| {
        warn!(
            operation = "auth.refresh_tokens.parse_refresh_token",
            refresh_token_hash = %refresh_token_hash,
            error = ?error,
            "invalid refresh token format"
        );
        Error::InvalidRefreshToken
    })?;
    Span::current().record("user_id", tracing::field::display(user_id));
    let refresh_token_row = match app
        .database
        .get_refresh_token_from_name_user(name.as_str(), user_id)
        .await
    {
        Ok(refresh_token_row) => refresh_token_row,
        Err(error) if is_row_not_found(&error) => {
            warn!(
                operation = "auth.refresh_tokens.load_refresh_token",
                user_id = %user_id,
                refresh_token_hash = %refresh_token_hash,
                "refresh token was not found"
            );
            return Err(Error::InvalidRefreshToken);
        }
        Err(error) => {
            log_sqlx_error(
                "auth.refresh_tokens.load_refresh_token",
                &error,
                "failed to load refresh token",
            );
            return Err(Error::FailedToLoadRefreshToken);
        }
    };

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
        .map_err(|error| {
            log_sqlx_error(
                "auth.refresh_tokens.create_refresh_token",
                &error,
                "failed to create replacement refresh token",
            );
            Error::FailedToCreateRefreshToken
        })?;

    info!(
        operation = "auth.refresh_tokens.create_refresh_token",
        user_id = %user_id,
        is_api_key,
        "refresh token renewed"
    );

    let cookie_headers = auth_cookie_headers(&new_access_token, &new_refresh_token);
    Ok((
        cookie_headers,
        Json(AuthResponse {
            access_token: new_access_token,
            refresh_token: new_refresh_token,
        }),
    )
        .into_response())
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
pub async fn privacy_policy() -> Html<&'static str> {
    Html(include_str!("privacy_policy.html"))
}

#[debug_handler]
pub async fn support_page() -> Html<&'static str> {
    Html(include_str!("support_page.html"))
}

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct MeResponse {
    email: Option<String>,
    subscription_source: Option<String>,
    subscription_status: String,
    subscription_product_id: Option<String>,
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
        subscription_product_id: account_state.subscription_product_id,
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
    if !matches!(subscription_status, "active" | "grace_period") {
        return false;
    }

    subscription_expires_at
        .map(|expires_at| expires_at > chrono::Utc::now().naive_utc())
        .unwrap_or(true)
}

#[debug_handler]
pub async fn me(State(app): State<App>, headers: HeaderMap) -> Result<Response, Error> {
    let user_id = authenticated_user_id_from_headers(&app, &headers)?;

    let account_state = app
        .database
        .get_user_account_state(user_id)
        .await
        .map_err(|error| {
            if is_row_not_found(&error) {
                warn!(
                    operation = "auth.me.load_account_state",
                    user_id = %user_id,
                    "authenticated user id was not found"
                );
                return Error::Unauthorized;
            }

            log_sqlx_error(
                "auth.me.load_account_state",
                &error,
                "failed to load authenticated account state",
            );
            Error::FailedToLoadAccount
        })?;

    Ok(Json(me_response_from_account_state(account_state)).into_response())
}

#[debug_handler]
#[tracing::instrument(
    name = "auth.delete_account",
    skip(app, headers),
    fields(user_id = tracing::field::Empty)
)]
pub async fn delete_account(State(app): State<App>, headers: HeaderMap) -> Result<Response, Error> {
    let user_id = authenticated_user_id_from_headers(&app, &headers)?;

    let apple_refresh_token = app
        .database
        .get_apple_refresh_token_for_user(user_id)
        .await
        .map_err(|error| {
            if is_row_not_found(&error) {
                warn!(
                    operation = "auth.delete_account.load_user",
                    user_id = %user_id,
                    "account deletion requested for missing user"
                );
                return Error::Unauthorized;
            }

            log_sqlx_error(
                "auth.delete_account.load_user",
                &error,
                "failed to load account before deletion",
            );
            Error::FailedToLoadAccount
        })?;

    revoke_stored_apple_refresh_token(user_id, apple_refresh_token.as_deref());

    let deleted = app
        .database
        .delete_user_account(user_id)
        .await
        .map_err(|error| {
            log_sqlx_error(
                "auth.delete_account.delete_user",
                &error,
                "failed to delete account",
            );
            Error::FailedToDeleteAccount
        })?;

    if !deleted {
        warn!(
            operation = "auth.delete_account.delete_user",
            user_id = %user_id,
            "account deletion requested for missing user"
        );
        return Err(Error::Unauthorized);
    }

    info!(
        operation = "auth.delete_account.delete_user",
        user_id = %user_id,
        "account deleted"
    );

    let clear_headers = clear_auth_cookie_headers();
    Ok((clear_headers, Json(LogoutResponse { success: true })).into_response())
}

#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct LinkAppleSubscriptionInput {
    transaction_id: String,
    original_transaction_id: String,
    product_id: Option<String>,
    environment: String,
    subscription_expires_at: Option<String>,
}

#[debug_handler]
#[tracing::instrument(
    name = "auth.link_apple_subscription",
    skip(app, headers, input),
    fields(
        user_id = tracing::field::Empty,
        apple_transaction_id_hash = tracing::field::Empty,
        apple_original_transaction_id_hash = tracing::field::Empty,
        apple_product_id = tracing::field::Empty,
        apple_environment = tracing::field::Empty,
        apple_subscription_status = tracing::field::Empty
    )
)]
pub async fn link_apple_subscription(
    State(app): State<App>,
    headers: HeaderMap,
    Json(input): Json<LinkAppleSubscriptionInput>,
) -> Result<Response, Error> {
    let user_id = authenticated_user_id_from_headers(&app, &headers)?;
    let transaction_id_hash = log_value_hash(input.transaction_id.as_str());
    let original_transaction_id_hash = log_value_hash(input.original_transaction_id.as_str());
    let span = Span::current();
    span.record("user_id", tracing::field::display(user_id));
    span.record("apple_transaction_id_hash", transaction_id_hash.as_str());
    span.record(
        "apple_original_transaction_id_hash",
        original_transaction_id_hash.as_str(),
    );
    span.record(
        "apple_product_id",
        input.product_id.as_deref().unwrap_or("<missing>"),
    );
    span.record("apple_environment", input.environment.as_str());

    let mut errors = vec![];
    if input.transaction_id.trim().is_empty() {
        errors.push(ValidationError::TransactionIdMissing);
    }
    if input.transaction_id.len() > 255 {
        errors.push(ValidationError::TransactionIdTooLong);
    }
    if input.original_transaction_id.trim().is_empty() {
        errors.push(ValidationError::OriginalTransactionIdMissing);
    }
    if input.original_transaction_id.len() > 255 {
        errors.push(ValidationError::OriginalTransactionIdTooLong);
    }

    let product_id = input
        .product_id
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty());
    if product_id.is_none() {
        errors.push(ValidationError::ProductIdMissing);
    }
    if product_id.is_some_and(|value| value.len() > 255) {
        errors.push(ValidationError::ProductIdTooLong);
    }
    if product_id.is_some_and(|value| !billing::is_apple_premium_product_id(value)) {
        errors.push(ValidationError::InvalidProductId);
    }
    let environment = input.environment.trim();
    if billing::normalize_apple_environment(environment).is_none() {
        errors.push(ValidationError::InvalidAppStoreEnvironment);
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

    let product_id = product_id
        .ok_or_else(|| Error::ValidationErrorList(vec![ValidationError::ProductIdMissing]))?;

    info!(
        operation = "auth.link_apple_subscription.request_received",
        user_id = %user_id,
        apple_transaction_id_hash = %transaction_id_hash,
        apple_original_transaction_id_hash = %original_transaction_id_hash,
        apple_product_id = product_id,
        apple_environment = environment,
        apple_client_subscription_expires_at = ?subscription_expires_at,
        "Apple subscription link request received"
    );

    if let Some(existing_user_id) = app
        .database
        .get_user_id_from_app_store_original_transaction_id(input.original_transaction_id.as_str())
        .await
        .map_err(|error| {
            log_sqlx_error(
                "auth.link_apple_subscription.find_existing_owner",
                &error,
                "failed to check Apple subscription ownership",
            );
            Error::FailedToLinkAppleSubscription
        })?
    {
        if existing_user_id != user_id {
            warn!(
                operation = "auth.link_apple_subscription.ownership_conflict",
                user_id = %user_id,
                existing_user_id = %existing_user_id,
                apple_original_transaction_id_hash = %original_transaction_id_hash,
                "Apple subscription is already linked to another account"
            );
            return Err(Error::SubscriptionAlreadyLinked);
        }
    }

    let verified_transaction = billing::verify_linked_transaction(
        input.transaction_id.as_str(),
        input.original_transaction_id.as_str(),
        product_id,
        environment,
        subscription_expires_at,
    )
    .map_err(|error| match error {
        billing::AppleBillingError::InvalidProduct => {
            warn!(
                operation = "auth.link_apple_subscription.verify_transaction",
                user_id = %user_id,
                apple_transaction_id_hash = %transaction_id_hash,
                apple_original_transaction_id_hash = %original_transaction_id_hash,
                apple_product_id = product_id,
                apple_environment = environment,
                error = ?error,
                "Apple transaction rejected"
            );
            Error::ValidationErrorList(vec![ValidationError::InvalidProductId])
        }
        billing::AppleBillingError::InvalidEnvironment => {
            warn!(
                operation = "auth.link_apple_subscription.verify_transaction",
                user_id = %user_id,
                apple_transaction_id_hash = %transaction_id_hash,
                apple_original_transaction_id_hash = %original_transaction_id_hash,
                apple_product_id = product_id,
                apple_environment = environment,
                error = ?error,
                "Apple transaction rejected"
            );
            Error::ValidationErrorList(vec![ValidationError::InvalidAppStoreEnvironment])
        }
        billing::AppleBillingError::InvalidPayload => {
            warn!(
                operation = "auth.link_apple_subscription.verify_transaction",
                user_id = %user_id,
                apple_transaction_id_hash = %transaction_id_hash,
                apple_original_transaction_id_hash = %original_transaction_id_hash,
                apple_product_id = product_id,
                apple_environment = environment,
                error = ?error,
                "Apple transaction payload failed verification"
            );
            Error::FailedToLinkAppleSubscription
        }
        billing::AppleBillingError::VerificationUnavailable => {
            error!(
                operation = "auth.link_apple_subscription.verify_transaction",
                user_id = %user_id,
                apple_transaction_id_hash = %transaction_id_hash,
                apple_original_transaction_id_hash = %original_transaction_id_hash,
                apple_product_id = product_id,
                apple_environment = environment,
                error = ?error,
                "Apple transaction verification unavailable"
            );
            Error::FailedToLinkAppleSubscription
        }
    })?;

    let subscription_status =
        billing::status_for_apple_transaction(&verified_transaction, None, None);
    Span::current().record("apple_subscription_status", subscription_status);
    info!(
        operation = "auth.link_apple_subscription.verify_transaction",
        user_id = %user_id,
        apple_transaction_id_hash = %transaction_id_hash,
        apple_original_transaction_id_hash = %original_transaction_id_hash,
        apple_product_id = verified_transaction.product_id.as_str(),
        apple_environment = verified_transaction.environment.as_str(),
        apple_subscription_status = subscription_status,
        "Apple transaction verified"
    );

    let account_state = app
        .database
        .link_apple_subscription(
            user_id,
            verified_transaction.original_transaction_id.as_str(),
            verified_transaction.transaction_id.as_str(),
            Some(verified_transaction.product_id.as_str()),
            subscription_status,
            verified_transaction.expires_at,
            verified_transaction.environment.as_str(),
        )
        .await
        .map_err(|error| {
            log_sqlx_error(
                "auth.link_apple_subscription.store_entitlement",
                &error,
                "failed to store linked Apple subscription",
            );
            Error::FailedToLinkAppleSubscription
        })?;

    info!(
        operation = "auth.link_apple_subscription.store_entitlement",
        user_id = %user_id,
        apple_transaction_id_hash = %transaction_id_hash,
        apple_original_transaction_id_hash = %original_transaction_id_hash,
        apple_product_id = verified_transaction.product_id.as_str(),
        apple_environment = verified_transaction.environment.as_str(),
        apple_subscription_status = subscription_status,
        "Apple subscription linked"
    );

    Ok(Json(me_response_from_account_state(account_state)).into_response())
}

#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AppleNotificationInput {
    signed_payload: String,
}

#[derive(serde::Serialize)]
struct BillingNotificationResponse {
    success: bool,
}

#[debug_handler]
#[tracing::instrument(
    name = "billing.apple_server_notification_v2",
    skip(app, input),
    fields(
        apple_notification_uuid = tracing::field::Empty,
        apple_notification_type = tracing::field::Empty,
        apple_notification_subtype = tracing::field::Empty,
        apple_original_transaction_id_hash = tracing::field::Empty,
        apple_transaction_id_hash = tracing::field::Empty,
        apple_subscription_status = tracing::field::Empty
    )
)]
pub async fn apple_server_notification_v2(
    State(app): State<App>,
    Json(input): Json<AppleNotificationInput>,
) -> Result<Response, Error> {
    let signed_payload_hash = log_value_hash(input.signed_payload.as_str());
    let notification =
        billing::verify_apple_notification(input.signed_payload.as_str()).map_err(|error| {
            warn!(
                operation = "billing.apple_notification.verify",
                signed_payload_hash = %signed_payload_hash,
                error = ?error,
                "invalid Apple server notification"
            );
            Error::InvalidAppleBillingPayload
        })?;
    let transaction = notification.transaction.as_ref();
    let subscription_status = transaction.map(|transaction| {
        billing::status_for_apple_transaction(
            transaction,
            notification.notification_type.as_deref(),
            notification.subtype.as_deref(),
        )
    });
    let entitlement_expires_at = transaction.and_then(|transaction| {
        billing::entitlement_expires_at_for_apple_notification(
            transaction,
            notification.renewal_info.as_ref(),
            notification.notification_type.as_deref(),
            notification.subtype.as_deref(),
        )
    });
    let span = Span::current();
    span.record(
        "apple_notification_uuid",
        notification.notification_uuid.as_str(),
    );
    if let Some(notification_type) = notification.notification_type.as_deref() {
        span.record("apple_notification_type", notification_type);
    }
    if let Some(subtype) = notification.subtype.as_deref() {
        span.record("apple_notification_subtype", subtype);
    }
    if let Some(transaction) = transaction {
        span.record(
            "apple_original_transaction_id_hash",
            log_value_hash(transaction.original_transaction_id.as_str()).as_str(),
        );
        span.record(
            "apple_transaction_id_hash",
            log_value_hash(transaction.transaction_id.as_str()).as_str(),
        );
    }
    if let Some(subscription_status) = subscription_status {
        span.record("apple_subscription_status", subscription_status);
    }

    let inserted = app
        .database
        .record_apple_server_notification(
            notification.notification_uuid.as_str(),
            notification.notification_type.as_deref(),
            notification.subtype.as_deref(),
            transaction.map(|value| value.original_transaction_id.as_str()),
            transaction.map(|value| value.transaction_id.as_str()),
            transaction.map(|value| value.product_id.as_str()),
            transaction.map(|value| value.environment.as_str()),
            subscription_status,
            entitlement_expires_at,
            notification.signed_at,
            notification.payload_hash.as_str(),
        )
        .await
        .map_err(|error| {
            log_sqlx_error(
                "billing.apple_notification.record",
                &error,
                "failed to record Apple server notification",
            );
            Error::FailedToProcessAppleNotification
        })?;

    if !inserted {
        info!(
            operation = "billing.apple_notification.record",
            apple_notification_uuid = notification.notification_uuid.as_str(),
            "duplicate Apple server notification ignored"
        );
        return Ok(Json(BillingNotificationResponse { success: true }).into_response());
    }

    if let Some(transaction) = transaction {
        let _subscription_status = subscription_status.ok_or(Error::InvalidAppleBillingPayload)?;

        app.database
            .update_apple_entitlement_from_notification(
                transaction.original_transaction_id.as_str(),
            )
            .await
            .map_err(|error| {
                log_sqlx_error(
                    "billing.apple_notification.update_entitlement",
                    &error,
                    "failed to update Apple entitlement from notification",
                );
                Error::FailedToProcessAppleNotification
            })?;
    }

    info!(
        operation = "billing.apple_notification.process",
        apple_notification_uuid = notification.notification_uuid.as_str(),
        apple_notification_type = notification
            .notification_type
            .as_deref()
            .unwrap_or("<none>"),
        apple_notification_subtype = notification.subtype.as_deref().unwrap_or("<none>"),
        apple_subscription_status = subscription_status.unwrap_or("<none>"),
        "Apple server notification processed"
    );

    Ok(Json(BillingNotificationResponse { success: true }).into_response())
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
#[tracing::instrument(
    name = "auth.logout",
    skip(app, headers, input),
    fields(user_id = tracing::field::Empty, refresh_token_hash = tracing::field::Empty)
)]
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
    let refresh_token_hash = log_value_hash(token.as_str());
    Span::current().record("refresh_token_hash", refresh_token_hash.as_str());
    let (user_id, name, refresh_token) = parse_refresh_token(token.as_str()).map_err(|error| {
        warn!(
            operation = "auth.logout.parse_refresh_token",
            refresh_token_hash = %refresh_token_hash,
            error = ?error,
            "invalid refresh token format"
        );
        Error::InvalidRefreshToken
    })?;
    Span::current().record("user_id", tracing::field::display(user_id));

    // Validate the refresh token exists and matches
    let refresh_token_row = app
        .database
        .get_refresh_token_from_name_user(name.as_str(), user_id)
        .await
        .map_err(|error| {
            if is_row_not_found(&error) {
                warn!(
                    operation = "auth.logout.load_refresh_token",
                    user_id = %user_id,
                    refresh_token_hash = %refresh_token_hash,
                    "refresh token was not found"
                );
                return Error::InvalidRefreshToken;
            }

            log_sqlx_error(
                "auth.logout.load_refresh_token",
                &error,
                "failed to load refresh token during logout",
            );
            Error::FailedToLoadRefreshToken
        })?;

    if !security::check_password(refresh_token_row.key.as_str(), refresh_token.as_str()) {
        return Err(Error::InvalidRefreshToken);
    }

    // Delete the validated refresh token
    if let Err(error) = app
        .database
        .delete_refresh_token_by_user_and_name(user_id, name.as_str())
        .await
    {
        log_sqlx_error(
            "auth.logout.delete_refresh_token",
            &error,
            "failed to delete refresh token during logout",
        );
    } else {
        info!(
            operation = "auth.logout.delete_refresh_token",
            user_id = %user_id,
            "refresh token deleted during logout"
        );
    }

    let clear_headers = clear_auth_cookie_headers();
    Ok((clear_headers, Json(LogoutResponse { success: true })).into_response())
}
