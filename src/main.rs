use tracing::info;
mod database;
mod graphql;
mod observability;
mod router;
mod routes;
mod security;

#[tokio::main]
async fn main() {
    let _guard = observability::init_tracing();

    let listener = tokio::net::TcpListener::bind("127.0.0.1:8080")
        .await
        .unwrap();
    info!("the app is listening");

    let router = router::router().await;
    axum::serve(listener, router.into_make_service())
        .await
        .unwrap();
}
