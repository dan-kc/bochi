use tracing::info;
use tracing_appender::rolling::hourly;
use tracing_subscriber::EnvFilter;
mod database;
mod graphql;
mod router;
mod routes;
mod secrets;
mod security;

#[tokio::main]
async fn main() {
    // Create a rolling file appender
    // _guard has to alive for the duration of the application
    let (writer, _guard) = match std::env::var("LOG_DESTINATION") {
        Ok(dest) => {
            let path = std::path::Path::new(&dest);
            let file_prefix = "server.log";
            let rolling_file_appender = hourly(path, file_prefix);
            tracing_appender::non_blocking(rolling_file_appender)
        }
        Err(_) => tracing_appender::non_blocking(std::io::stdout()),
    };

    tracing_subscriber::fmt()
        .json()
        .with_env_filter(
            EnvFilter::try_from_default_env()
                .or_else(|_| EnvFilter::try_new("habit_market_backend=error,tower_http=warn"))
                .unwrap(),
        )
        .with_writer(writer) // Use our conditional writer
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
