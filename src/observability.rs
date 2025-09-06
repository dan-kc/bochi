use tracing_appender::rolling::hourly;
use tracing_subscriber::{fmt, prelude::*, EnvFilter};

pub fn init_tracing() -> Option<tracing_appender::non_blocking::WorkerGuard> {
    // Always log to stdout
    let stdout_layer = fmt::layer().json().with_writer(std::io::stdout);

    // Conditionally add file logging
    let registry = tracing_subscriber::registry().with(stdout_layer).with(
        EnvFilter::try_from_default_env()
            .or_else(|_| EnvFilter::try_new("habit_market_backend=error,tower_http=warn"))
            .unwrap(),
    );

    // _guard has to be alive for the duration of the application
    match std::env::var("LOG_DESTINATION") {
        Ok(dest) => {
            let path = std::path::Path::new(&dest);
            let file_prefix = "server.log";
            let rolling_file_appender = hourly(path, file_prefix);
            let (non_blocking, guard) = tracing_appender::non_blocking(rolling_file_appender);

            let file_layer = fmt::layer().json().with_writer(non_blocking);

            registry.with(file_layer).init();
            Some(guard)
        }
        Err(_) => {
            registry.init();
            None
        }
    }
}

