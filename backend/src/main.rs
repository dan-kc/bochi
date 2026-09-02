use axum::ServiceExt;
use bochi_backend::{network, observability, router};
use std::net::SocketAddr;
use tracing::info;

#[tokio::main]
async fn main() {
    let _guard = observability::init_tracing();

    let bind_host = std::env::var("SERVER_BIND_HOST").ok();
    let port = std::env::var("PORT").ok();
    let addr = network::listen_address(bind_host.as_deref(), port.as_deref());
    let listener = tokio::net::TcpListener::bind(&addr).await.unwrap();
    info!(%addr, "the app is listening");

    let router = router::router().await;
    let make_service = <_ as ServiceExt<
        axum::http::Request<axum::body::Body>,
    >>::into_make_service_with_connect_info::<SocketAddr>(router);
    axum::serve(listener, make_service).await.unwrap();
}
