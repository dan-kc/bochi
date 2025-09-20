use crate::generate_email_from_fn;
use axum::body::Body;
use axum::http::{Request, StatusCode};
use habit_market_backend::router;
use http::Method;
use http_body_util::BodyExt;
use serde_json::json;
use tower::ServiceExt;

async fn register_and_login_user(email: &str, password: &str) -> Result<(String, String), String> {
    let router = router::router().await;

    // Try to register user first
    let register_request = json!({
        "email": email,
        "password": password
    });

    let register_response = router
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/auth/register")
                .header(http::header::CONTENT_TYPE, "application/json")
                .body(Body::from(register_request.to_string()))
                .unwrap(),
        )
        .await
        .map_err(|e| format!("Failed to register: {}", e))?;

    let response = if register_response.status() == StatusCode::OK {
        register_response
    } else if register_response.status() == StatusCode::CONFLICT {
        // User already exists, try login
        let router2 = router::router().await;
        let login_request = json!({
            "email": email,
            "password": password
        });

        router2
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/auth/login")
                    .header(http::header::CONTENT_TYPE, "application/json")
                    .body(Body::from(login_request.to_string()))
                    .unwrap(),
            )
            .await
            .map_err(|e| format!("Login failed: {}", e))?
    } else {
        return Err(format!(
            "Registration failed with status: {}",
            register_response.status()
        ));
    };

    let response_body_bytes = response
        .into_body()
        .collect()
        .await
        .map_err(|e| format!("Failed to read response body: {}", e))?
        .to_bytes();

    let json: serde_json::Value = serde_json::from_slice(&response_body_bytes)
        .map_err(|e| format!("Failed to parse JSON: {}", e))?;

    let refresh_token = json
        .get("refreshToken")
        .and_then(|v| v.as_str())
        .ok_or("No refreshToken in response")?;
    let access_token = json
        .get("accessToken")
        .and_then(|v| v.as_str())
        .ok_or("No accessToken in response")?;

    Ok((refresh_token.to_string(), access_token.to_string()))
}

#[tokio::test]
async fn test_refresh_tokens_success() {
    let email = generate_email_from_fn!(test_refresh_tokens_success);
    let password = "password123";

    // Register and get tokens
    let (refresh_token, _access_token) = register_and_login_user(&email, password)
        .await
        .expect("Failed to register and login user");

    // Test refresh tokens
    let router = router::router().await;

    let request_body = json!({
        "refreshToken": refresh_token
    });

    let response = router
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/auth/refresh-tokens")
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
        json.get("refreshToken").is_some(),
        "Response should contain new refreshToken"
    );
    assert!(
        json.get("accessToken").is_some(),
        "Response should contain new accessToken"
    );

    // Verify new tokens are different from original
    let new_refresh_token = json.get("refreshToken").unwrap().as_str().unwrap();

    assert_ne!(
        new_refresh_token, refresh_token,
        "New refresh token should be different"
    );
}

#[tokio::test]
async fn test_refresh_tokens_invalid_token() {
    let router = router::router().await;

    let request_body = json!({
        "refreshToken": "invalid.token.here"
    });

    let response = router
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/auth/refresh-tokens")
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
async fn test_refresh_tokens_malformed_token() {
    let router = router::router().await;

    let request_body = json!({
        "refreshToken": "not-a-valid-format"
    });

    let response = router
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/auth/refresh-tokens")
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
async fn test_refresh_tokens_after_logout() {
    let email = generate_email_from_fn!(test_refresh_tokens_after_logout);
    let password = "password123";

    // Register and get tokens
    let (refresh_token, _access_token) = register_and_login_user(&email, password)
        .await
        .expect("Failed to get user tokens");

    // Logout should invalidate the refresh token
    let router = router::router().await;

    let logout_request = json!({
        "refreshToken": &refresh_token
    });

    let logout_response = router
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/auth/logout")
                .header(http::header::CONTENT_TYPE, "application/json")
                .body(Body::from(logout_request.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(logout_response.status(), StatusCode::OK);

    // Try to refresh with logged out token - should fail
    let router2 = router::router().await;

    let refresh_request = json!({
        "refreshToken": refresh_token
    });

    let response = router2
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/auth/refresh-tokens")
                .header(http::header::CONTENT_TYPE, "application/json")
                .body(Body::from(refresh_request.to_string()))
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
async fn test_refresh_tokens_multiple_times() {
    let email = generate_email_from_fn!(test_refresh_tokens_multiple_times);
    let password = "password123";

    // Register and get initial tokens
    let (mut refresh_token, _access_token) = register_and_login_user(&email, password)
        .await
        .expect("Failed to register and login user");

    // Refresh tokens multiple times
    for i in 0..3 {
        let router = router::router().await;

        let request_body = json!({
            "refreshToken": &refresh_token
        });

        let response = router
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/auth/refresh-tokens")
                    .header(http::header::CONTENT_TYPE, "application/json")
                    .body(Body::from(request_body.to_string()))
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(
            response.status(),
            StatusCode::OK,
            "Token refresh {} should succeed",
            i + 1
        );

        let response_body_bytes = response
            .into_body()
            .collect()
            .await
            .expect("Failed to read response body")
            .to_bytes();
        let json: serde_json::Value = serde_json::from_slice(&response_body_bytes)
            .expect("Failed to parse JSON response body");

        let new_refresh_token = json
            .get("refreshToken")
            .and_then(|v| v.as_str())
            .expect("Should have new refreshToken");

        assert_ne!(
            new_refresh_token, refresh_token,
            "New refresh token should be different"
        );

        // Update for next iteration
        refresh_token = new_refresh_token.to_string();
    }
}
