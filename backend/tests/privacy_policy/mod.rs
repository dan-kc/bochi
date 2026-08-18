use axum::body::Body;
use axum::http::{Request, StatusCode};
use bochi_backend::router;
use http::Method;
use http_body_util::BodyExt;
use tower::ServiceExt;

#[tokio::test]
async fn test_privacy_policy_is_served_as_public_html() {
    // Users and App Review need to read the policy before signing in.
    let router = router::router().await;

    let response = router
        .oneshot(
            Request::builder()
                .method(Method::GET)
                .uri("/privacy-policy")
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
    let html = String::from_utf8(response_body_bytes.to_vec()).expect("Policy should be UTF-8");
    let normalized_html = html.split_whitespace().collect::<Vec<_>>().join(" ");

    assert!(html.contains("<h1>Bochi Privacy Policy</h1>"));
    assert!(html.contains("Sentry"));
    assert!(html.contains("Crash Data, Performance Data, and Other Diagnostic Data"));
    assert!(html.contains("delete your Bochi account from Settings"));
    assert!(normalized_html.contains("does not cancel billing managed by Apple"));
    assert!(html.contains("Bochi's App Store age rating is 4+"));
    assert!(normalized_html.contains("except in mainland China"));
}
