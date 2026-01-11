use axum::body::Body;
use axum::http::{Request, StatusCode};
use http::Method;
use http_body_util::BodyExt;
use serde_json::json;
use tofustash_backend::router;
use tower::ServiceExt;
use uuid::Uuid;

/// Helper to call /auth/anonymous endpoint
async fn anonymous_auth(device_id: &str) -> (StatusCode, serde_json::Value) {
    let router = router::router().await;

    let request_body = json!({
        "deviceId": device_id
    });

    let response = router
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/auth/anonymous")
                .header(http::header::CONTENT_TYPE, "application/json")
                .body(Body::from(request_body.to_string()))
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
    let json: serde_json::Value =
        serde_json::from_slice(&response_body_bytes).expect("Failed to parse JSON response body");

    (status, json)
}

/// Helper to call /auth/claim endpoint
async fn claim_account(
    access_token: &str,
    email: &str,
    password: &str,
) -> (StatusCode, serde_json::Value) {
    let router = router::router().await;

    let request_body = json!({
        "email": email,
        "password": password
    });

    let response = router
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/auth/claim")
                .header(http::header::CONTENT_TYPE, "application/json")
                .header(http::header::AUTHORIZATION, format!("Bearer {}", access_token))
                .body(Body::from(request_body.to_string()))
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
    let json: serde_json::Value =
        serde_json::from_slice(&response_body_bytes).expect("Failed to parse JSON response body");

    (status, json)
}

#[tokio::test]
async fn test_anonymous_auth_success() {
    let device_id = Uuid::new_v4().to_string();

    let (status, json) = anonymous_auth(&device_id).await;

    assert_eq!(status, StatusCode::OK);
    assert!(
        json["refreshToken"].is_string(),
        "Response should contain refreshToken as a string"
    );
    assert!(
        json["accessToken"].is_string(),
        "Response should contain accessToken as a string"
    );
}

#[tokio::test]
async fn test_anonymous_auth_idempotent() {
    // Same device_id should return the same user (idempotent)
    let device_id = Uuid::new_v4().to_string();

    // First call
    let (status1, json1) = anonymous_auth(&device_id).await;
    assert_eq!(status1, StatusCode::OK);

    // Extract user_id from first token
    let access_token1 = json1["accessToken"].as_str().unwrap();
    let payload1 = decode_jwt_payload(access_token1);
    let user_id1 = payload1["sub"].as_str().unwrap();

    // Second call with same device_id
    let (status2, json2) = anonymous_auth(&device_id).await;
    assert_eq!(status2, StatusCode::OK);

    // Extract user_id from second token
    let access_token2 = json2["accessToken"].as_str().unwrap();
    let payload2 = decode_jwt_payload(access_token2);
    let user_id2 = payload2["sub"].as_str().unwrap();

    // Same device_id should return same user
    assert_eq!(
        user_id1, user_id2,
        "Same device_id should return same user"
    );
}

#[tokio::test]
async fn test_anonymous_auth_different_devices() {
    // Different device_ids should create different users
    let device_id1 = Uuid::new_v4().to_string();
    let device_id2 = Uuid::new_v4().to_string();

    let (status1, json1) = anonymous_auth(&device_id1).await;
    assert_eq!(status1, StatusCode::OK);
    let access_token1 = json1["accessToken"].as_str().unwrap();
    let payload1 = decode_jwt_payload(access_token1);
    let user_id1 = payload1["sub"].as_str().unwrap();

    let (status2, json2) = anonymous_auth(&device_id2).await;
    assert_eq!(status2, StatusCode::OK);
    let access_token2 = json2["accessToken"].as_str().unwrap();
    let payload2 = decode_jwt_payload(access_token2);
    let user_id2 = payload2["sub"].as_str().unwrap();

    assert_ne!(
        user_id1, user_id2,
        "Different device_ids should create different users"
    );
}

#[tokio::test]
async fn test_anonymous_auth_invalid_device_id() {
    // Invalid device_id (not a UUID) should fail
    let (status, json) = anonymous_auth("not-a-uuid").await;

    assert_eq!(status, StatusCode::BAD_REQUEST);

    let errors = json
        .get("errors")
        .and_then(|v| v.as_array())
        .expect("Should have errors array");
    assert_eq!(errors.len(), 1, "Should have exactly one error");

    let error = &errors[0];
    assert_eq!(
        error.get("code").and_then(|v| v.as_str()),
        Some("INVALID_DEVICE_ID")
    );
}

#[tokio::test]
async fn test_claim_account_success() {
    // First create an anonymous user
    let device_id = Uuid::new_v4().to_string();
    let (status, json) = anonymous_auth(&device_id).await;
    assert_eq!(status, StatusCode::OK);

    let access_token = json["accessToken"].as_str().unwrap();

    // Claim the account with email and password
    let email = format!("claim_test_{}@test.com", Uuid::new_v4());
    let password = "password123";

    let (claim_status, claim_json) = claim_account(access_token, &email, password).await;

    assert_eq!(claim_status, StatusCode::OK);
    assert!(
        claim_json["refreshToken"].is_string(),
        "Response should contain refreshToken"
    );
    assert!(
        claim_json["accessToken"].is_string(),
        "Response should contain accessToken"
    );

    // Should now be able to login with email/password
    let router = router::router().await;
    let login_body = json!({
        "email": email,
        "password": password
    });

    let login_response = router
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/auth/login")
                .header(http::header::CONTENT_TYPE, "application/json")
                .body(Body::from(login_body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(login_response.status(), StatusCode::OK);
}

#[tokio::test]
async fn test_claim_account_already_claimed() {
    // First create an anonymous user
    let device_id = Uuid::new_v4().to_string();
    let (status, json) = anonymous_auth(&device_id).await;
    assert_eq!(status, StatusCode::OK);

    let access_token = json["accessToken"].as_str().unwrap();

    // Claim the account
    let email = format!("claim_twice_{}@test.com", Uuid::new_v4());
    let password = "password123";

    let (claim_status, _) = claim_account(access_token, &email, password).await;
    assert_eq!(claim_status, StatusCode::OK);

    // Get new tokens by logging in
    let router = router::router().await;
    let login_body = json!({
        "email": email,
        "password": password
    });

    let login_response = router
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/auth/login")
                .header(http::header::CONTENT_TYPE, "application/json")
                .body(Body::from(login_body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    let login_body_bytes = login_response
        .into_body()
        .collect()
        .await
        .unwrap()
        .to_bytes();
    let login_json: serde_json::Value = serde_json::from_slice(&login_body_bytes).unwrap();
    let new_access_token = login_json["accessToken"].as_str().unwrap();

    // Try to claim again - should fail
    let email2 = format!("claim_twice_second_{}@test.com", Uuid::new_v4());
    let (second_claim_status, second_claim_json) =
        claim_account(new_access_token, &email2, password).await;

    assert_eq!(second_claim_status, StatusCode::BAD_REQUEST);

    let errors = second_claim_json
        .get("errors")
        .and_then(|v| v.as_array())
        .expect("Should have errors array");
    assert_eq!(errors.len(), 1, "Should have exactly one error");

    let error = &errors[0];
    assert_eq!(
        error.get("code").and_then(|v| v.as_str()),
        Some("ACCOUNT_ALREADY_CLAIMED")
    );
}

#[tokio::test]
async fn test_claim_account_email_already_exists() {
    // Register a normal user first
    let existing_email = format!("existing_{}@test.com", Uuid::new_v4());
    let password = "password123";

    let router = router::router().await;
    let register_body = json!({
        "email": existing_email,
        "password": password
    });

    let register_response = router
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/auth/register")
                .header(http::header::CONTENT_TYPE, "application/json")
                .body(Body::from(register_body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(register_response.status(), StatusCode::OK);

    // Create an anonymous user
    let device_id = Uuid::new_v4().to_string();
    let (status, json) = anonymous_auth(&device_id).await;
    assert_eq!(status, StatusCode::OK);

    let access_token = json["accessToken"].as_str().unwrap();

    // Try to claim with the existing email - should fail
    let (claim_status, claim_json) = claim_account(access_token, &existing_email, password).await;

    assert_eq!(claim_status, StatusCode::BAD_REQUEST);

    let errors = claim_json
        .get("errors")
        .and_then(|v| v.as_array())
        .expect("Should have errors array");

    let error = &errors[0];
    // Generic error to prevent email enumeration
    assert_eq!(
        error.get("code").and_then(|v| v.as_str()),
        Some("FAILED_TO_CLAIM")
    );
}

#[tokio::test]
async fn test_claim_account_validation() {
    // Create an anonymous user
    let device_id = Uuid::new_v4().to_string();
    let (status, json) = anonymous_auth(&device_id).await;
    assert_eq!(status, StatusCode::OK);

    let access_token = json["accessToken"].as_str().unwrap();

    // Try to claim with invalid email
    let (claim_status, claim_json) = claim_account(access_token, "notanemail", "password123").await;

    assert_eq!(claim_status, StatusCode::BAD_REQUEST);

    let errors = claim_json
        .get("errors")
        .and_then(|v| v.as_array())
        .expect("Should have errors array");

    let error = &errors[0];
    assert_eq!(
        error.get("code").and_then(|v| v.as_str()),
        Some("INVALID_EMAIL_ADDRESS")
    );
}

#[tokio::test]
async fn test_claim_account_unauthorized() {
    // Try to claim without auth token
    let router = router::router().await;

    let request_body = json!({
        "email": "test@test.com",
        "password": "password123"
    });

    let response = router
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/auth/claim")
                .header(http::header::CONTENT_TYPE, "application/json")
                .body(Body::from(request_body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

/// Helper to decode JWT payload
fn decode_jwt_payload(token: &str) -> serde_json::Value {
    use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};

    let parts: Vec<&str> = token.split('.').collect();
    assert_eq!(parts.len(), 3, "JWT should have 3 parts");

    let payload_bytes = URL_SAFE_NO_PAD
        .decode(parts[1])
        .expect("Failed to decode JWT payload");
    serde_json::from_slice(&payload_bytes).expect("Failed to parse JWT payload as JSON")
}
