mod database;
mod graphql;
mod router;
mod routes;
mod secrets;
mod security;

#[tokio::main]
async fn main() {
    let app = router::router().await;
    let listener = tokio::net::TcpListener::bind("127.0.0.1:8080").await.unwrap();
    println!("the app is listening");
    axum::serve(listener, app.into_make_service())
        .await
        .unwrap();
}
