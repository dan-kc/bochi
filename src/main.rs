use tracing_subscriber::EnvFilter;
use tracing::info;

mod database;
mod graphql;
mod router;
mod routes;
mod secrets;
mod security;

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env()
                .or_else(|_| EnvFilter::try_new("habit_market_backend=error,tower_http=warn"))
                .unwrap(),
        )
        .init();

    let app = router::router().await;
    let listener = tokio::net::TcpListener::bind("127.0.0.1:8080")
        .await
        .unwrap();
    info!("the app is listening");
    axum::serve(listener, app.into_make_service())
        .await
        .unwrap();
}
