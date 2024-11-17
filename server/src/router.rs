use async_graphql::{EmptySubscription, Schema};
use async_graphql_axum::{GraphQLRequest, GraphQLResponse};
use axum::{
    debug_handler,
    extract::Extension,
    http::StatusCode,
    response::IntoResponse,
    routing::{get, post},
    Json,
};
use serde::Serialize;
use sqlx::postgres::PgPoolOptions;

use crate::model::{MutationRoot, QueryRoot, ServiceSchema};

pub async fn router() -> axum::Router {
    let database_url = std::env::var("DATABASE_URL").expect("Need db url");

    let pool = PgPoolOptions::new()
        .max_connections(5)
        .connect(&database_url)
        .await
        .expect("Unable to create database pool");

    let schema = Schema::build(QueryRoot, MutationRoot, EmptySubscription)
        .data(pool)
        .finish();

    println!("connected to db");

    axum::Router::new()
        .route("/health", get(health))
        .route("/graphql", post(graphql_handler))
        .layer(Extension(schema))
    // .with_state(pool) This would be required to use pool it in a non-gql query
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
    req: GraphQLRequest,
) -> GraphQLResponse {
    // let ctx = async_graphql::Context::from(model::Context::new(db_pool));

    schema.execute(req.into_inner()).await.into()
}
