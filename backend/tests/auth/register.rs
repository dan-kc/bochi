use crate::common::create_password_of_length;
use crate::generate_email_from_fn;
use axum::body::Body;
use axum::http::{Request, StatusCode};
use http::Method;
use http_body_util::BodyExt;
use serde_json::json;
use tofustash_backend::router;
use tower::ServiceExt;

#[tokio::test]
async fn test_register_success() {
    let router = router::router().await;

    let request_body = json!({
        "email": generate_email_from_fn!(test_register_success),
        "password": "password123"
    });

    let response = router
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/auth/register")
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

    if status != StatusCode::OK {
        let error_text = String::from_utf8_lossy(&response_body_bytes);
        panic!("Expected status 200, got {}: {}", status, error_text);
    }
    let json: serde_json::Value =
        serde_json::from_slice(&response_body_bytes).expect("Failed to parse JSON response body");

    assert!(
        json["refreshToken"].is_string(),
        "Response should contain refreshToken as a string, got: {:?}",
        json.get("refreshToken")
    );
    assert!(
        json["accessToken"].is_string(),
        "Response should contain accessToken as a string, got: {:?}",
        json.get("accessToken")
    );
}

#[tokio::test]
async fn test_register_user_already_exists() {
    let email = generate_email_from_fn!(test_register_user_already_exists);

    // First registration
    let router = router::router().await;

    let request_body = json!({
        "email": &email,
        "password": "password123"
    });

    let first_response = router
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/auth/register")
                .header(http::header::CONTENT_TYPE, "application/json")
                .body(Body::from(request_body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(first_response.status(), StatusCode::OK);

    // Second registration with same email - returns generic error to prevent email enumeration
    let router2 = router::router().await;

    let request_body2 = json!({
        "email": &email,
        "password": "password456"
    });

    let second_response = router2
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/auth/register")
                .header(http::header::CONTENT_TYPE, "application/json")
                .body(Body::from(request_body2.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    // Returns BAD_REQUEST with generic error to prevent email enumeration
    assert_eq!(second_response.status(), StatusCode::BAD_REQUEST);

    let response_body_bytes = second_response
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
    // Generic error message that doesn't reveal whether the email exists
    assert_eq!(
        error.get("code").and_then(|v| v.as_str()),
        Some("FAILED_TO_REGISTER")
    );
    assert_eq!(
        error.get("message").and_then(|v| v.as_str()),
        Some("Registration failed. Please try again.")
    );
}

#[tokio::test]
async fn test_register_invalid_email() {
    let router = router::router().await;

    let request_body = json!({
        "email": "notanemail",
        "password": "password123"
    });

    let response = router
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/auth/register")
                .header(http::header::CONTENT_TYPE, "application/json")
                .body(Body::from(request_body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::BAD_REQUEST);

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
        Some("INVALID_EMAIL_ADDRESS")
    );
    assert_eq!(
        error.get("message").and_then(|v| v.as_str()),
        Some("Invalid email address.")
    );
}

#[tokio::test]
async fn test_register_email_too_long() {
    let router = router::router().await;
    let long_email = format!("{}@test.com", "x".repeat(246));

    let request_body = json!({
        "email": long_email,
        "password": "password123"
    });

    let response = router
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/auth/register")
                .header(http::header::CONTENT_TYPE, "application/json")
                .body(Body::from(request_body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    // The long email will also fail the regex validation because it contains too many 'x' characters
    // So we check that it fails with status 400 or 409
    assert!(
        response.status() == StatusCode::BAD_REQUEST || response.status() == StatusCode::CONFLICT,
        "Expected status code 400 or 409, got {}",
        response.status()
    );

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
    assert!(errors.len() >= 1, "Should have at least one error");

    let error_codes: Vec<&str> = errors
        .iter()
        .filter_map(|e| e.get("code").and_then(|v| v.as_str()))
        .collect();

    assert!(error_codes.contains(&"EMAIL_TOO_LONG"));
}

#[tokio::test]
async fn test_register_password_too_short() {
    let router = router::router().await;

    let request_body = json!({
        "email": generate_email_from_fn!(test_register_password_too_short),
        "password": "short"
    });

    let response = router
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/auth/register")
                .header(http::header::CONTENT_TYPE, "application/json")
                .body(Body::from(request_body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::BAD_REQUEST);

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
        Some("PASSWORD_TOO_SHORT")
    );
    assert_eq!(
        error.get("message").and_then(|v| v.as_str()),
        Some("Password too short. The min password length is 8.")
    );
}

#[tokio::test]
async fn test_register_password_too_long() {
    let router = router::router().await;
    let long_password = create_password_of_length(65);

    let request_body = json!({
        "email": generate_email_from_fn!(test_register_password_too_long),
        "password": &long_password
    });

    let response = router
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/auth/register")
                .header(http::header::CONTENT_TYPE, "application/json")
                .body(Body::from(request_body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::BAD_REQUEST);

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
        Some("PASSWORD_TOO_LONG")
    );
    assert_eq!(
        error.get("message").and_then(|v| v.as_str()),
        Some("Password too long. The maximum password length is 64.")
    );
}

#[tokio::test]
async fn test_register_password_not_ascii() {
    let router = router::router().await;

    let request_body = json!({
        "email": generate_email_from_fn!(test_register_password_not_ascii),
        "password": "pass😊word"
    });

    let response = router
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/auth/register")
                .header(http::header::CONTENT_TYPE, "application/json")
                .body(Body::from(request_body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::BAD_REQUEST);

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
        Some("PASSWORD_NOT_ASCII")
    );
    assert_eq!(
        error.get("message").and_then(|v| v.as_str()),
        Some(
            "Password must contain only standard English letters, numbers, and common punctuation."
        )
    );
}

#[tokio::test]
async fn test_register_multiple_validation_errors() {
    let router = router::router().await;
    let long_email = format!("{}@test.com", "x".repeat(246));
    let long_password = create_password_of_length(65);

    let request_body = json!({
        "email": long_email,
        "password": long_password
    });

    let response = router
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/auth/register")
                .header(http::header::CONTENT_TYPE, "application/json")
                .body(Body::from(request_body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert!(
        response.status() == StatusCode::BAD_REQUEST || response.status() == StatusCode::CONFLICT,
        "Expected status code 400 or 409, got {}",
        response.status()
    );

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
    assert!(errors.len() >= 2, "Should have multiple errors");

    // Check that we have the expected error codes
    let error_codes: Vec<&str> = errors
        .iter()
        .filter_map(|e| e.get("code").and_then(|v| v.as_str()))
        .collect();

    // We should get validation errors
    assert!(
        error_codes.contains(&"EMAIL_TOO_LONG") || error_codes.contains(&"INVALID_EMAIL_ADDRESS"),
        "Should have EMAIL_TOO_LONG or INVALID_EMAIL_ADDRESS error"
    );
    assert!(
        error_codes.contains(&"PASSWORD_TOO_LONG"),
        "Should have PASSWORD_TOO_LONG error"
    );
}

#[tokio::test]
async fn test_register_edge_cases() {
    // Test minimum valid password length (8 characters)
    let router = router::router().await;

    let request_body = json!({
        "email": generate_email_from_fn!(test_register_edge_cases_min),
        "password": "12345678"
    });

    let response = router
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/auth/register")
                .header(http::header::CONTENT_TYPE, "application/json")
                .body(Body::from(request_body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(
        response.status(),
        StatusCode::OK,
        "8-character password should be valid"
    );

    // Test maximum valid password length (64 characters)
    let router2 = router::router().await;
    let max_password = create_password_of_length(64);

    let request_body2 = json!({
        "email": generate_email_from_fn!(test_register_edge_cases_max),
        "password": &max_password
    });

    let response2 = router2
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/auth/register")
                .header(http::header::CONTENT_TYPE, "application/json")
                .body(Body::from(request_body2.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(
        response2.status(),
        StatusCode::OK,
        "64-character password should be valid"
    );

    // Test a reasonably sized email
    let router3 = router::router().await;

    let request_body3 = json!({
        "email": generate_email_from_fn!(test_register_edge_cases_normal),
        "password": "password123"
    });

    let response3 = router3
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/auth/register")
                .header(http::header::CONTENT_TYPE, "application/json")
                .body(Body::from(request_body3.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(
        response3.status(),
        StatusCode::OK,
        "Normal length email should be valid"
    );

    // Test email with dots
    let router4 = router::router().await;

    let request_body4 = json!({
        "email": generate_email_from_fn!(test_register_edge_cases_dots),
        "password": "password123"
    });

    let response4 = router4
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/auth/register")
                .header(http::header::CONTENT_TYPE, "application/json")
                .body(Body::from(request_body4.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(
        response4.status(),
        StatusCode::OK,
        "Email with dots should be valid"
    );
}
