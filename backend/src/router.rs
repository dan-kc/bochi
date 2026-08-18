use crate::{api, database, routes, security::jwt::JWTManager};
use axum::{
    extract::{MatchedPath, Request, State},
    http::{header, HeaderMap, StatusCode},
    middleware::Next,
    response::{IntoResponse, Response},
    routing::{delete, get, post},
};
use std::time::Duration;
use tower_http::{cors::CorsLayer, normalize_path::NormalizePath, trace::TraceLayer};
use tracing::{error, info, warn, Level, Span};
use uuid::Uuid;

/// Stuff we need in every route and all middleware.
#[derive(Clone)]
pub struct App {
    pub jwt_manager: JWTManager,
    pub database: database::Database,
}
impl App {
    fn new(jwt_manager: JWTManager, database: database::Database) -> Self {
        Self {
            jwt_manager,
            database,
        }
    }
}

pub async fn router() -> NormalizePath<axum::Router> {
    NormalizePath::trim_trailing_slash(base_router().await)
}

async fn base_router() -> axum::Router {
    let database = database::Database::new().await;
    let jwt_manager = JWTManager::new();
    let app = App::new(jwt_manager, database);

    info!("connected to db");

    let auth_router = axum::Router::new()
        .route("/sign-in-with-apple", post(routes::sign_in_with_apple))
        .route("/account", delete(routes::delete_account))
        .route("/logout", post(routes::logout))
        .route("/me", get(routes::me))
        .route(
            "/link-apple-subscription",
            post(routes::link_apple_subscription),
        )
        .route("/refresh-tokens", post(routes::refresh_tokens));

    // Versioned REST API routes (require authentication)
    let api_v1_router = axum::Router::new()
        .route("/sync", get(api::sync::get_sync).post(api::sync::post_sync))
        .layer(axum::middleware::from_fn_with_state(app.clone(), auth));

    let cors = CorsLayer::new()
        .allow_origin(
            "http://localhost:8500"
                .parse::<axum::http::HeaderValue>()
                .unwrap(),
        )
        .allow_origin(
            "http://localhost:8501"
                .parse::<axum::http::HeaderValue>()
                .unwrap(),
        )
        .allow_origin(
            "http://localhost:8502"
                .parse::<axum::http::HeaderValue>()
                .unwrap(),
        )
        .allow_methods([
            axum::http::Method::GET,
            axum::http::Method::POST,
            axum::http::Method::DELETE,
            axum::http::Method::OPTIONS,
        ])
        .allow_headers([
            axum::http::header::CONTENT_TYPE,
            axum::http::header::AUTHORIZATION,
        ])
        .allow_credentials(true);

    axum::Router::new()
        .route("/health", get(routes::health))
        .route("/privacy-policy", get(routes::privacy_policy))
        .route("/support", get(routes::support_page))
        .route(
            "/billing/apple/notifications/v2",
            post(routes::apple_server_notification_v2),
        )
        .nest("/auth", auth_router)
        .nest("/api/v1", api_v1_router)
        .layer(axum::middleware::from_fn_with_state(
            app.clone(),
            attach_auth_context,
        ))
        .layer(cors)
        .layer(
            // This will make all routes implicitly have a:
            // #[tracing::instrument(level = Level::INFO, ...)]
            TraceLayer::new_for_http()
                .make_span_with(|request: &Request<_>| {
                    let request_id = uuid::Uuid::new_v4().to_string();
                    let matched_path = request
                        .extensions()
                        .get::<MatchedPath>()
                        .map(MatchedPath::as_str)
                        .unwrap_or_else(|| request.uri().path());
                    let user_agent = header_value(request.headers(), header::USER_AGENT);
                    let client_ip = first_forwarded_for(request.headers())
                        .or_else(|| header_value(request.headers(), "x-real-ip"));

                    tracing::span!(
                        Level::INFO,
                        "request",
                        %request_id,
                        method = %request.method(),
                        route = %matched_path,
                        path = %request.uri().path(),
                        user_agent = user_agent,
                        client_ip = client_ip,
                        user_id = tracing::field::Empty,
                        auth_source = tracing::field::Empty,
                        auth_failure = tracing::field::Empty,
                        status_code = tracing::field::Empty,
                        latency_ms = tracing::field::Empty,
                    )
                })
                .on_response(|response: &Response, latency: Duration, span: &Span| {
                    let status = response.status();
                    let latency_ms = latency.as_secs_f64() * 1000.0;
                    span.record("status_code", status.as_u16());
                    span.record("latency_ms", latency_ms);

                    if status.is_server_error() {
                        error!(
                            parent: span,
                            status_code = status.as_u16(),
                            latency_ms,
                            "request completed with server error"
                        );
                    } else if status.is_client_error() {
                        warn!(
                            parent: span,
                            status_code = status.as_u16(),
                            latency_ms,
                            "request completed with client error"
                        );
                    } else {
                        info!(
                            parent: span,
                            status_code = status.as_u16(),
                            latency_ms,
                            "request completed"
                        );
                    }
                })
                .on_failure(()),
        )
        .with_state(app)
}

#[allow(dead_code)]
#[derive(Clone, Debug)]
pub struct AuthenticatedUser {
    pub user_id: Uuid,
}

/// Extract access_token from Cookie header
fn extract_token_from_cookies(cookie_header: &str) -> Option<&str> {
    cookie_header
        .split(';')
        .map(|s| s.trim())
        .find(|s| s.starts_with("access_token="))
        .and_then(|s| s.strip_prefix("access_token="))
}

fn header_value<'a, K>(headers: &'a HeaderMap, key: K) -> Option<&'a str>
where
    K: axum::http::header::AsHeaderName,
{
    headers.get(key).and_then(|value| value.to_str().ok())
}

fn first_forwarded_for(headers: &HeaderMap) -> Option<&str> {
    header_value(headers, "x-forwarded-for")
        .and_then(|value| value.split(',').next())
        .map(str::trim)
        .filter(|value| !value.is_empty())
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
        .and_then(extract_token_from_cookies)
        .map(|token| (token, "cookie"));

    jwt_from_header.or(jwt_from_cookie)
}

fn record_authenticated_user(user_id: Uuid, auth_source: &'static str) {
    let span = Span::current();
    span.record("user_id", tracing::field::display(user_id));
    span.record("auth_source", auth_source);
}

async fn attach_auth_context(State(app): State<App>, mut req: Request, next: Next) -> Response {
    let auth_result = extract_access_token_from_headers(req.headers())
        .map(|(jwt, auth_source)| (app.jwt_manager.validate(jwt), auth_source));

    if let Some((Some(user_id), auth_source)) = auth_result {
        record_authenticated_user(user_id, auth_source);
        req.extensions_mut().insert(AuthenticatedUser { user_id });
    }

    next.run(req).await
}

async fn auth(State(app): State<App>, mut req: Request, next: Next) -> Response {
    if req.extensions().get::<AuthenticatedUser>().is_some() {
        return next.run(req).await;
    }

    match extract_access_token_from_headers(req.headers()) {
        None => {
            Span::current().record("auth_failure", "missing_token");
            warn!("authenticated route rejected request without an access token");
            StatusCode::UNAUTHORIZED.into_response()
        }
        Some((jwt, auth_source)) => match app.jwt_manager.validate(jwt) {
            Some(user_id) => {
                record_authenticated_user(user_id, auth_source);
                req.extensions_mut().insert(AuthenticatedUser { user_id });
                next.run(req).await
            }
            None => {
                let span = Span::current();
                span.record("auth_source", auth_source);
                span.record("auth_failure", "invalid_token");
                warn!(
                    auth_source,
                    "authenticated route rejected invalid access token"
                );
                StatusCode::UNAUTHORIZED.into_response()
            }
        },
    }
}
