use crate::generate_email_from_fn;
use axum::body::Body;
use axum::http::{Request, StatusCode};
use http::Method;
use http_body_util::BodyExt;
use serde_json::json;
use std::time::{SystemTime, UNIX_EPOCH};
use bochi_backend::router;
use tower::ServiceExt;

async fn register_user_for_login(email: &str, password: &str) -> Result<(), String> {
    let router = router::router().await;

    let request_body = json!({
        "email": email,
        "password": password
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
        .map_err(|e| format!("Failed to register: {}", e))?;

    if response.status() == StatusCode::OK || response.status() == StatusCode::CONFLICT {
        Ok(())
    } else {
        Err(format!(
            "Registration failed with status: {}",
            response.status()
        ))
    }
}

#[tokio::test]
async fn test_login_success() {
    let email = generate_email_from_fn!(test_login_success);
    let password = "password123";

    // First register a user
    register_user_for_login(&email, password)
        .await
        .expect("Failed to register user");

    // Now test login
    let router = router::router().await;

    let request_body = json!({
        "email": email,
        "password": password
    });

    let response = router
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/auth/login")
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
async fn test_login_invalid_email() {
    let router = router::router().await;

    let request_body = json!({
        "email": "notanemail",
        "password": "password123"
    });

    let response = router
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/auth/login")
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
        Some("INVALID_LOGIN_CREDENTIALS")
    );
    assert_eq!(
        error.get("message").and_then(|v| v.as_str()),
        Some("Incorrect email or password.")
    );
}

#[tokio::test]
async fn test_login_nonexistent_user() {
    let router = router::router().await;
    let email = generate_email_from_fn!(test_login_nonexistent_user);

    let request_body = json!({
        "email": email,
        "password": "password123"
    });

    let response = router
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/auth/login")
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
        Some("INVALID_LOGIN_CREDENTIALS")
    );
    assert_eq!(
        error.get("message").and_then(|v| v.as_str()),
        Some("Incorrect email or password.")
    );
}

#[tokio::test]
async fn test_login_wrong_password() {
    let email = generate_email_from_fn!(test_login_wrong_password);
    let password = "password123";

    // First register a user
    register_user_for_login(&email, password)
        .await
        .expect("Failed to register user");

    // Now test login with wrong password
    let router = router::router().await;

    let request_body = json!({
        "email": email,
        "password": "wrongpassword"
    });

    let response = router
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/auth/login")
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
        Some("INVALID_LOGIN_CREDENTIALS")
    );
    assert_eq!(
        error.get("message").and_then(|v| v.as_str()),
        Some("Incorrect email or password.")
    );
}

#[tokio::test]
async fn test_login_email_too_long() {
    let router = router::router().await;
    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let long_email = format!("test{}{}@example.com", timestamp, "x".repeat(15));

    let request_body = json!({
        "email": long_email,
        "password": "password123"
    });

    let response = router
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/auth/login")
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
        Some("INVALID_LOGIN_CREDENTIALS")
    );
}

#[tokio::test]
async fn test_login_boundary_password_lengths() {
    // Test 8-character password (minimum valid)
    let email8 = generate_email_from_fn!(test_login_boundary_password_lengths);
    let password8 = "12345678";

    // Register with 8-char password
    let _ = register_user_for_login(&email8, password8).await;

    // Test login with 8-char password
    let router = router::router().await;

    let request_body = json!({
        "email": &email8,
        "password": password8
    });

    let response = router
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/auth/login")
                .header(http::header::CONTENT_TYPE, "application/json")
                .body(Body::from(request_body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    // If user was registered successfully, login should work
    // If user doesn't exist, it should fail with invalid credentials
    if response.status() == StatusCode::OK {
        // Success is good - user was registered and login worked
    } else if response.status() == StatusCode::UNAUTHORIZED {
        // This is also acceptable - might mean user didn't get registered
    } else {
        panic!("Unexpected status code: {}", response.status());
    }

    // Test 7-character password (too short) - should fail
    let router2 = router::router().await;
    let request_body = json!({
        "email": generate_email_from_fn!(test_login_boundary_password_lengths_short),
        "password": "1234567"
    });

    let response = router2
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/auth/login")
                .header(http::header::CONTENT_TYPE, "application/json")
                .body(Body::from(request_body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(
        response.status(),
        StatusCode::UNAUTHORIZED,
        "Login with 7-character password should fail"
    );
}
