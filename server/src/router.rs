use axum::{http::StatusCode, response::IntoResponse, routing::get, Json};
use serde::Serialize;
use sqlx::postgres::PgPoolOptions;

pub async fn router() -> axum::Router {
    let database_url = std::env::var("DATABASE_URL").expect("Need db url");
    let pool = PgPoolOptions::new()
        .max_connections(5)
        .connect(&database_url)
        .await
        .expect("Unable to connect to database");

    println!("connected to db");

    axum::Router::new()
        .route("/health", get(health))
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
