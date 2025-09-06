use tracing::info;
use tracing_appender::rolling::hourly;
use tracing_subscriber::{EnvFilter, fmt, prelude::*};
mod database;
mod graphql;
mod router;
mod routes;
mod secrets;
mod security;

#[tokio::main]
async fn main() {
    // Always log to stdout
    let stdout_layer = fmt::layer()
        .json()
        .with_writer(std::io::stdout);

    // Conditionally add file logging
    let registry = tracing_subscriber::registry()
        .with(stdout_layer)
        .with(
            EnvFilter::try_from_default_env()
                .or_else(|_| EnvFilter::try_new("habit_market_backend=error,tower_http=warn"))
                .unwrap(),
        );

    // _guard has to be alive for the duration of the application
    let _guard = match std::env::var("LOG_DESTINATION") {
        Ok(dest) => {
            let path = std::path::Path::new(&dest);
            let file_prefix = "server.log";
            let rolling_file_appender = hourly(path, file_prefix);
            let (non_blocking, guard) = tracing_appender::non_blocking(rolling_file_appender);
            
            let file_layer = fmt::layer()
                .json()
                .with_writer(non_blocking);
            
            registry.with(file_layer).init();
            Some(guard)
        }
        Err(_) => {
            registry.init();
            None
        }
    };

    let app = router::router().await;
    let listener = tokio::net::TcpListener::bind("127.0.0.1:8080")
        .await
        .unwrap();
    info!("the app is listening");
    axum::serve(listener, app.into_make_service())
        .await
        .unwrap();
}
