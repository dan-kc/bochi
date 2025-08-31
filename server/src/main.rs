mod database;
mod graphql;
mod router;
mod routes;
mod secrets;
mod security;

#[tokio::main]
async fn main() {
    let db_user = secrets::SecretsManager::new()
        .await
        .get_secret("db-user")
        .await
        .unwrap();
    let db_password = secrets::SecretsManager::new()
        .await
        .get_secret("db-password")
        .await
        .unwrap();

    println!("{db_user}");
    println!("{db_password}");

    let app = router::router().await;
    let listener = tokio::net::TcpListener::bind("0.0.0.0:80").await.unwrap();
    println!("the app is listening");
    axum::serve(listener, app.into_make_service())
        .await
        .unwrap();
}
