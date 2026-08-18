use axum::body::Body;
use axum::http::{Request, StatusCode};
use bochi_backend::router;
use http::Method;
use http_body_util::BodyExt;
use tower::ServiceExt;

#[tokio::test]
async fn test_support_page_is_served_as_public_html() {
    // App Review and users need support contact information without signing in.
    let router = router::router().await;

    let response = router
        .oneshot(
            Request::builder()
                .method(Method::GET)
                .uri("/support")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);
    assert_eq!(
        response
            .headers()
            .get(http::header::CONTENT_TYPE)
            .and_then(|value| value.to_str().ok()),
        Some("text/html; charset=utf-8")
    );

    let response_body_bytes = response
        .into_body()
        .collect()
        .await
        .expect("Failed to read response body")
        .to_bytes();
    let html =
        String::from_utf8(response_body_bytes.to_vec()).expect("Support page should be UTF-8");

    assert!(html.contains("<h1>Bochi Support</h1>"));
    assert!(html.contains("contact@bochi.app"));
    assert!(html.contains("mailto:contact@bochi.app"));
    assert!(html.contains("<h2>Account deletion</h2>"));
    assert!(html.contains("apps.apple.com/account/subscriptions"));
}
