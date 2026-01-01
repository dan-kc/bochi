use tracing_appender::rolling::hourly;
use tracing_subscriber::fmt::format::FmtSpan;
use tracing_subscriber::{fmt, prelude::*, EnvFilter};


pub fn init_tracing() -> Option<tracing_appender::non_blocking::WorkerGuard> {
    // Always log to stdout
    let stdout_layer = fmt::layer()
        .json()
        .with_target(false)
        .with_span_events(FmtSpan::CLOSE | FmtSpan::NEW) // Log when a span starts and ends
        .with_writer(std::io::stdout);

    // The subscriber contains: timestamp, level, fields, span and spans
    // 'fields' by default, will just look like {"message": "Hi"} for Info!("Hi"), but this
    // can be changed by adding a k,v pair into Info! like Info!(test="yes", "Hi") - This will
    // log {"test": "yes", "message": "Hi"}

    // Also, because each log entry has a 'spans' field, it will list all of the context needed
    // from this one log entry. You will be able to see the entire journey without needing to
    // look at multiple logs.

    // There are Span log levels and there are message log levels. As far as filtering is concerned,
    // the span's log level controls whether the span's own lifecycle events (like its
    // creation/entry/closure logs) are emitted. It does not override or change the log level of
    // individual log messages (info!, debug!, error!, etc.) that occur within that span.

    let registry = tracing_subscriber::registry().with(stdout_layer).with(
        EnvFilter::try_from_default_env()
            .or_else(|_| EnvFilter::try_new("tofustash_backend=error,tower_http=warn"))
            .unwrap(),
    );

    // Conditionally add file logging
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
