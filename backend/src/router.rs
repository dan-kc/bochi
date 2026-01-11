use crate::{
    database,
    graphql::{mutations::MutationRoot, queries::QueryRoot},
    routes,
    security::jwt::JWTManager,
};
use async_graphql::{EmptySubscription, Schema};
use axum::{
    extract::{Extension, Request, State},
    http::StatusCode,
    middleware::Next,
    response::{IntoResponse, Response},
    routing::{get, post},
};
use tower_http::{cors::CorsLayer, trace::TraceLayer};
use tracing::{info, Level};
use uuid::Uuid;

/// Stuff we need in every route and all middleware. This is seperate to what we need in gql
/// resolvers.
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

pub async fn router() -> axum::Router {
    let database = database::Database::new().await;
    let jwt_manager = JWTManager::new();
    let schema = Schema::build(QueryRoot, MutationRoot, EmptySubscription)
        .data(database.clone())
        .data(jwt_manager.clone())
        .finish();
    let app = App::new(jwt_manager, database);

    info!("connected to db");

    let graphql_middleware_stack = tower::ServiceBuilder::new()
        .layer(axum::middleware::from_fn_with_state(app.clone(), auth))
        .layer(Extension(schema));

    let auth_router = axum::Router::new()
        .route("/register", post(routes::register))
        .route("/login", post(routes::login))
        .route("/logout", post(routes::logout))
        .route("/refresh-tokens", post(routes::refresh_tokens))
        .route("/anonymous", post(routes::anonymous))
        .route("/claim", post(routes::claim));

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
            axum::http::Method::OPTIONS,
        ])
        .allow_headers([
            axum::http::header::CONTENT_TYPE,
            axum::http::header::AUTHORIZATION,
        ])
        .allow_credentials(true);

    axum::Router::new()
        .route("/health", get(routes::health))
        .route(
            "/graphql",
            post(routes::graphql).layer(graphql_middleware_stack),
        )
        .nest("/auth", auth_router)
        .layer(cors)
        .layer(
            // This will make all routes implicitly have a:
            // #[tracing::instrument(level = Level::INFO, ...)]
            TraceLayer::new_for_http().make_span_with(|request: &Request<_>| {
                let request_id = uuid::Uuid::new_v4().to_string();
                tracing::span!(
                    Level::INFO,
                    "request",
                    %request_id,
                    method = ?request.method(),
                    uri = %request.uri(),
                )
            }),
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

async fn auth(State(app): State<App>, mut req: Request, next: Next) -> Response {
    let headers = req.headers();

    // First try Authorization header (takes precedence)
    let jwt_from_header = headers
        .get(axum::http::header::AUTHORIZATION)
        .and_then(|header_value| header_value.to_str().ok())
        .and_then(|header| header.strip_prefix("Bearer "));

    // Fall back to cookie if no Authorization header
    let jwt_from_cookie = headers
        .get(axum::http::header::COOKIE)
        .and_then(|header_value| header_value.to_str().ok())
        .and_then(extract_token_from_cookies);

    let jwt_optional = jwt_from_header.or(jwt_from_cookie);

    match jwt_optional {
        None => StatusCode::UNAUTHORIZED.into_response(),
        Some(jwt) => match app.jwt_manager.validate(jwt) {
            Some(user_id) => {
                req.extensions_mut().insert(AuthenticatedUser { user_id });
                next.run(req).await
            }
            None => StatusCode::UNAUTHORIZED.into_response(),
        },
    }
}
