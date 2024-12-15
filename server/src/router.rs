use crate::{
    database,
    model::{MutationRoot, QueryRoot, ServiceSchema},
    security::jwt::Validator,
};
use async_graphql::{EmptySubscription, Schema};
use async_graphql_axum::{GraphQLRequest, GraphQLResponse};
use axum::{
    debug_handler,
    extract::{Extension, Request, State},
    http::StatusCode,
    middleware::Next,
    response::{IntoResponse, Response},
    routing::{get, post},
    Json,
};
use serde::Serialize;
use tower_http::trace::TraceLayer;

/// Stuff we need in every route and all middleware. This is seperate to what we need in gql
/// resolvers.
#[derive(Clone)]
pub struct App {
    pub jwt_validator: Validator,
    pub database: database::Database,
}
impl App {
    fn new(jwt_validator: Validator, database: database::Database) -> Self {
        Self {
            jwt_validator,
            database,
        }
    }
}

pub async fn router() -> axum::Router {
    let database = database::Database::new().await;
    let jwt_validator = Validator::new();
    let schema = Schema::build(QueryRoot, MutationRoot, EmptySubscription)
        .data(database.clone())
        .finish();
    let app = App::new(jwt_validator, database);

    println!("connected to db");

    let middleware_stack = tower::ServiceBuilder::new()
        .layer(axum::middleware::from_fn_with_state(app.clone(), auth))
        .layer(Extension(schema))
        .layer(TraceLayer::new_for_http());

    axum::Router::new()
        .route("/health", get(health))
        .route("/graphql", post(graphql_handler))
        .layer(middleware_stack)
        .with_state(app) // TODO: See if you can delete this
}

#[derive(Clone, Debug)]
#[allow(dead_code)]
pub enum AuthStatus {
    Authenticated(i32),
    Unauthenticated,
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
    let api_key_optional = headers
        .get("x-api-key")
        .and_then(|header_value| header_value.to_str().ok());

    match (jwt_optional, api_key_optional) {
        (None, None) => {
            req.extensions_mut().insert(AuthStatus::Unauthenticated);
            next.run(req).await
        }
        (Some(jwt), None) => {
            match app.jwt_validator.validate(jwt) {
                Some(user_id) => {
                    req.extensions_mut()
                        .insert(AuthStatus::Authenticated(user_id));
                }
                None => {
                    req.extensions_mut().insert(AuthStatus::Unauthenticated);
                }
            }

            next.run(req).await
        }
        (Some(_), Some(_)) => (
            StatusCode::BAD_REQUEST,
            "Both a JWT and an API Key were supplied. You must only supply one",
        )
            .into_response(),
        (None, Some(api_key)) => {
            match app.database.get_user_from_api_key(api_key).await {
                Some(user) => {
                    req.extensions_mut()
                        .insert(AuthStatus::Authenticated(user.id));
                }
                None => {
                    req.extensions_mut().insert(AuthStatus::Unauthenticated);
                }
            };
            next.run(req).await
        }
    }
}

#[derive(Serialize)]
struct Health {
    healthy: bool,
}

#[debug_handler]
async fn health() -> impl IntoResponse {
    let health = Health { healthy: true };
    (StatusCode::OK, Json(health))
}

#[debug_handler]
async fn graphql_handler(
    Extension(schema): Extension<ServiceSchema>,
    Extension(auth_status): Extension<AuthStatus>,
    req: GraphQLRequest,
) -> GraphQLResponse {
    let inner_req = req.into_inner();
    schema.execute(inner_req.data(auth_status)).await.into()
}
