use crate::{
    database,
    graphql::{MutationRoot, QueryRoot},
    routes, secrets,
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
use tower_http::trace::TraceLayer;

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
    // Get secrets
    let secrets_client = secrets::SecretsManager::new().await;
    let eddsa_public_key =
        secrets_client.get_secret("eddsa-public-key").await.unwrap();
    let eddsa_private_key = secrets_client
        .get_secret("eddsa-private-key")
        .await
        .unwrap();
    let db_user = secrets_client.get_secret("db-user").await.unwrap();
    let db_password = secrets_client.get_secret("db-password").await.unwrap();
    let db_host = secrets_client.get_secret("db-host").await.unwrap();

    let database = database::Database::new(
        db_user.as_str(),
        db_password.as_str(),
        db_host.as_str(),
    )
    .await;
    let jwt_manager =
        JWTManager::new(eddsa_public_key.as_str(), eddsa_private_key.as_str());
    let schema = Schema::build(QueryRoot, MutationRoot, EmptySubscription)
        .data(database.clone())
        .data(jwt_manager.clone())
        .finish();
    let app = App::new(jwt_manager, database);

    println!("connected to db");

    let graphql_middleware_stack = tower::ServiceBuilder::new()
        .layer(axum::middleware::from_fn_with_state(app.clone(), auth))
        .layer(Extension(schema));

    let auth_router = axum::Router::new()
        .route("/login", post(routes::login))
        .route("/logout", post(routes::logout))
        .route("/register", post(routes::register))
        .route("/refresh-tokens", post(routes::refresh_tokens));

    axum::Router::new()
        .route("/health", get(routes::health))
        .route(
            "/graphql",
            post(routes::graphql).layer(graphql_middleware_stack),
        )
        .nest("/auth", auth_router)
        .layer(TraceLayer::new_for_http())
        .with_state(app)
}

#[allow(dead_code)]
#[derive(Clone, Debug)]
pub struct AuthenticatedUser {
    pub user_id: i32,
}
async fn auth(
    State(app): State<App>,
    mut req: Request,
    next: Next,
) -> Response {
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
