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
        .route("/refresh-tokens", post(routes::refresh_tokens));

    let cors = CorsLayer::new()
        .allow_origin(
            "http://localhost:3000"
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
            TraceLayer::new_for_http().make_span_with(|request: &Request<_>| {
                let request_id = uuid::Uuid::new_v4().to_string();

                tracing::span!(
                    Level::DEBUG,
                    "request",
                    %request_id,
                    method = ?request.method(),
                    uri = %request.uri(),
                    version = ?request.version(),
                )
            }),
        )
        .with_state(app)
}

#[allow(dead_code)]
#[derive(Clone, Debug)]
pub struct AuthenticatedUser {
    pub user_id: i32,
}

async fn auth(State(app): State<App>, mut req: Request, next: Next) -> Response {
    let headers = req.headers();
    let jwt_optional = headers
        .get(axum::http::header::AUTHORIZATION)
        .and_then(|header_value| header_value.to_str().ok());

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
