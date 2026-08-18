use axum::ServiceExt;
use tracing::info;
mod api;
mod billing;
mod database;
mod error_context;
mod observability;
mod router;
mod routes;
mod security;

#[tokio::main]
async fn main() {
    let _guard = observability::init_tracing();

    let port = std::env::var("PORT").unwrap_or_else(|_| "8080".to_string());
    let addr = format!("0.0.0.0:{}", port);
    let listener = tokio::net::TcpListener::bind(&addr).await.unwrap();
    info!("the app is listening");

    let router = router::router().await;
    let make_service =
        <_ as ServiceExt<axum::http::Request<axum::body::Body>>>::into_make_service(router);
    axum::serve(listener, make_service).await.unwrap();
}
