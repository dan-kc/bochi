use crate::common::register_and_get_refresh_token;
use crate::generate_email_from_fn;
use axum::body::Body;
use axum::http::{Request, StatusCode};
use tofustash_backend::router;
use http::Method;
use http_body_util::BodyExt;
use serde_json::json;
use std::time::{SystemTime, UNIX_EPOCH};
use tower::ServiceExt;

#[tokio::test]
async fn test_logout_success() {
    // Use a known working email pattern
    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs();
    let email = format!("user{}@example.com", timestamp);
    let password = "password123";

    // Register user and get refresh token
    let refresh_token = register_and_get_refresh_token(&email, password)
        .await
        .expect("Failed to register and get refresh token");

    // Test logout
    let router = router::router().await;

    let request_body = json!({
        "refreshToken": refresh_token
    });

    let response = router
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/auth/logout")
                .header(http::header::CONTENT_TYPE, "application/json")
                .body(Body::from(request_body.to_string()))
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
        json.get("success").and_then(|v| v.as_bool()),
        Some(true),
        "Response should indicate success"
    );
}

#[tokio::test]
async fn test_logout_with_invalid_token() {
    let router = router::router().await;

    let request_body = json!({
        "refreshToken": "invalid.token.here"
    });

    let response = router
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/auth/logout")
                .header(http::header::CONTENT_TYPE, "application/json")
                .body(Body::from(request_body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);

    let response_body_bytes = response
        .into_body()
        .collect()
        .await
        .expect("Failed to read response body")
        .to_bytes();
    let json: serde_json::Value =
        serde_json::from_slice(&response_body_bytes).expect("Failed to parse JSON response body");

    let errors = json
        .get("errors")
        .and_then(|v| v.as_array())
        .expect("Should have errors array");
    assert_eq!(errors.len(), 1, "Should have exactly one error");

    let error = &errors[0];
    assert_eq!(
        error.get("code").and_then(|v| v.as_str()),
        Some("INVALID_REFRESH_TOKEN")
    );
    assert_eq!(
        error.get("message").and_then(|v| v.as_str()),
        Some("Invalid refresh token.")
    );
}

#[tokio::test]
async fn test_logout_twice_with_same_token() {
    let email = generate_email_from_fn!(test_logout_twice_with_same_token);
    let password = "password123";

    // Register and get refresh token
    let refresh_token = register_and_get_refresh_token(&email, password)
        .await
        .expect("Failed to register and get refresh token");

    // First logout should succeed
    let router = router::router().await;

    let request_body = json!({
        "refreshToken": &refresh_token
    });

    let response1 = router
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/auth/logout")
                .header(http::header::CONTENT_TYPE, "application/json")
                .body(Body::from(request_body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response1.status(), StatusCode::OK);

    // Second logout with same token should fail (token already invalidated)
    let router2 = router::router().await;

    let request_body2 = json!({
        "refreshToken": refresh_token
    });

    let response2 = router2
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/auth/logout")
                .header(http::header::CONTENT_TYPE, "application/json")
                .body(Body::from(request_body2.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response2.status(), StatusCode::UNAUTHORIZED);

    let response_body_bytes = response2
        .into_body()
        .collect()
        .await
        .expect("Failed to read response body")
        .to_bytes();
    let json: serde_json::Value =
        serde_json::from_slice(&response_body_bytes).expect("Failed to parse JSON response body");

    let errors = json
        .get("errors")
        .and_then(|v| v.as_array())
        .expect("Should have errors array");
    assert_eq!(errors.len(), 1, "Should have exactly one error");

    let error = &errors[0];
    assert_eq!(
        error.get("code").and_then(|v| v.as_str()),
        Some("INVALID_REFRESH_TOKEN")
    );
}
