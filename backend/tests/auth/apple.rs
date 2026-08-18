use axum::body::Body;
use axum::http::{Request, StatusCode};
use bochi_backend::router;
use http::Method;
use http_body_util::BodyExt;
use serde_json::json;
use tower::ServiceExt;

async fn post_json(path: &str, body: serde_json::Value) -> (StatusCode, serde_json::Value) {
    std::env::set_var("ALLOW_INSECURE_APPLE_SIGN_IN_TEST_TOKENS", "true");
    let router = router::router().await;

    let response = router
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri(path)
                .header(http::header::CONTENT_TYPE, "application/json")
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    let status = response.status();
    let response_body_bytes = response
        .into_body()
        .collect()
        .await
        .expect("Failed to read response body")
        .to_bytes();

    let json = if response_body_bytes.is_empty() {
        serde_json::Value::Null
    } else {
        serde_json::from_slice(&response_body_bytes).expect("Failed to parse JSON response body")
    };

    (status, json)
}

#[tokio::test]
async fn test_sign_in_with_apple_creates_account_and_returns_tokens() {
    // A first Apple authorization should create a backend account keyed by
    // Apple's stable subject and return the app's normal session token pair.
    let subject = "apple-create-user";
    let (status, json) = post_json(
        "/auth/sign-in-with-apple",
        json!({
            "identityToken": format!("test-apple-subject:{}", subject),
            "email": "apple-create-user@example.com"
        }),
    )
    .await;

    assert_eq!(status, StatusCode::OK, "Response: {:?}", json);
    assert!(json.get("refreshToken").and_then(|v| v.as_str()).is_some());
    assert!(json.get("accessToken").and_then(|v| v.as_str()).is_some());
}

#[tokio::test]
async fn test_sign_in_with_apple_reuses_existing_apple_account() {
    // Apple only sends email on the first authorization. Later sign-ins with
    // the same Apple subject should return the existing account without
    // requiring or erasing the stored email.
    let subject = "apple-existing-user";
    let first = post_json(
        "/auth/sign-in-with-apple",
        json!({
            "identityToken": format!("test-apple-subject:{}", subject),
            "email": "apple-existing-user@example.com"
        }),
    )
    .await;
    assert_eq!(first.0, StatusCode::OK, "Response: {:?}", first.1);

    let second = post_json(
        "/auth/sign-in-with-apple",
        json!({
            "identityToken": format!("test-apple-subject:{}", subject)
        }),
    )
    .await;

    assert_eq!(second.0, StatusCode::OK, "Response: {:?}", second.1);
    assert!(second
        .1
        .get("refreshToken")
        .and_then(|v| v.as_str())
        .is_some());
}

#[tokio::test]
async fn test_sign_in_with_apple_rejects_invalid_identity_token() {
    // The backend should not create accounts from arbitrary strings unless the
    // token verifies as a Sign in with Apple identity token.
    let (status, json) = post_json(
        "/auth/sign-in-with-apple",
        json!({
            "identityToken": "not-a-valid-test-token",
            "email": "invalid@example.com"
        }),
    )
    .await;

    assert_eq!(status, StatusCode::UNAUTHORIZED, "Response: {:?}", json);
    assert_eq!(
        json.get("errors")
            .and_then(|v| v.as_array())
            .and_then(|errors| errors.first())
            .and_then(|error| error.get("code"))
            .and_then(|v| v.as_str()),
        Some("INVALID_APPLE_IDENTITY_TOKEN")
    );
}

#[tokio::test]
async fn test_email_password_auth_routes_are_not_registered() {
    // Removing username/password auth means clients can no longer create or
    // access accounts through credential endpoints.
    let register = post_json(
        "/auth/register",
        json!({
            "email": "removed-register@example.com",
            "password": "password123"
        }),
    )
    .await;
    let login = post_json(
        "/auth/login",
        json!({
            "email": "removed-login@example.com",
            "password": "password123"
        }),
    )
    .await;

    assert_eq!(register.0, StatusCode::NOT_FOUND);
    assert_eq!(login.0, StatusCode::NOT_FOUND);
}
