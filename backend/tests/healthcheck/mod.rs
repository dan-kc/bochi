use axum::body::Body;
use axum::http::{Request, StatusCode};
use bochi_backend::router;
use http::Method;
use http_body_util::BodyExt;
use tower::ServiceExt;

#[tokio::test]
async fn test_healthcheck() {
    let router = router::router().await;

    let response = router
        .oneshot(
            Request::builder()
                .method(Method::GET)
                .uri("/health")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let response_body_bytes = response
        .into_body()
        .collect()
        .await
        .expect("Failed to read response body")
        .to_bytes();
    let json: serde_json::Value =
        serde_json::from_slice(&response_body_bytes).expect("Failed to parse JSON response body");

    assert_eq!(
        json.get("healthy").and_then(|v| v.as_bool()),
        Some(true),
        "Response should indicate healthy status"
    );
}

#[tokio::test]
async fn test_trailing_slash_matches_healthcheck_without_redirect() {
    // A manually typed URL with a trailing slash should hit the same endpoint
    // instead of relying on clients to follow a redirect.
    let router = router::router().await;

    let response = router
        .oneshot(
            Request::builder()
                .method(Method::GET)
                .uri("/health/")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);
}
