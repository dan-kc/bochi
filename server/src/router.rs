use async_graphql::{EmptyMutation, EmptySubscription, Schema};
use async_graphql_axum::{GraphQLRequest, GraphQLResponse};
use axum::{
    extract::Extension,
    http::StatusCode,
    response::IntoResponse,
    routing::{get, post},
    Json,
};
use serde::Serialize;
use sqlx::postgres::PgPoolOptions;

use crate::model::{QueryRoot, ServiceSchema};

pub async fn router() -> axum::Router {
    let database_url = std::env::var("DATABASE_URL").expect("Need db url");
    let schema = Schema::build(QueryRoot, EmptyMutation, EmptySubscription).finish();

    let pool = PgPoolOptions::new()
        .max_connections(5)
        .connect(&database_url)
        .await
        .expect("Unable to connect to database");

    println!("connected to db");

    axum::Router::new()
        .route("/health", get(health))
        .route("/graphql", post(graphql_handler))
        .layer(Extension(schema))
        .with_state(pool)
}

#[derive(Serialize)]
struct Health {
    healthy: bool,
}

async fn health() -> impl IntoResponse {
    let health = Health { healthy: true };

    (StatusCode::OK, Json(health))
}

async fn graphql_handler(
    Extension(schema): Extension<ServiceSchema>,
    req: GraphQLRequest,
) -> GraphQLResponse {
    schema.execute(req.into_inner()).await.into()
}
