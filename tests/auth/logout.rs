use crate::common::{register_and_login_user, unique_email, SharedTestServer};
use serde_json::json;
use std::time::{SystemTime, UNIX_EPOCH};

#[test]
fn test_logout_success() {
    let server = SharedTestServer::get();

    // Use a known working email pattern
    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs();
    let email = format!("user{}@example.com", timestamp);
    let password = "password123";

    // Register user
    let register_response = server.post_json(
        "/auth/register",
        json!({
            "email": &email,
            "password": password,
            "confirmPassword": password
        }),
    );

    let refresh_token = register_response
        .expect("Registration should succeed with fresh email")
        .into_string()
        .expect("Failed to read register response")
        .parse::<serde_json::Value>()
        .expect("Failed to parse register JSON")
        .get("refreshToken")
        .and_then(|v| v.as_str())
        .expect("No refreshToken")
        .to_string();

    // Test logout
    let response = server.post_json(
        "/auth/logout",
        json!({
            "refreshToken": refresh_token
        }),
    );

    assert!(response.is_ok(), "Logout should succeed");
    let response = response.unwrap();
    assert_eq!(response.status(), 200, "Expected status code 200");

    let body = response
        .into_string()
        .expect("Failed to read response body");
    let json: serde_json::Value = serde_json::from_str(&body).expect("Failed to parse JSON");

    assert_eq!(
        json.get("success").and_then(|v| v.as_bool()),
        Some(true),
        "Response should indicate success"
    );
}

#[test]
fn test_logout_with_invalid_token() {
    let server = SharedTestServer::get();

    let response = server.post_json(
        "/auth/logout",
        json!({
            "refreshToken": "invalid.token.here"
        }),
    );

    // Logout should now fail with invalid token
    assert!(response.is_err(), "Logout with invalid token should fail");
    if let Err(ureq::Error::Status(code, response)) = response {
        assert_eq!(code, 401, "Expected status code 401 for invalid token");

        let body = response
            .into_string()
            .expect("Failed to read response body");
        let json: serde_json::Value = serde_json::from_str(&body).expect("Failed to parse JSON");

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
    } else {
        panic!("Expected error status 401");
    }
}

#[test]
fn test_logout_twice_with_same_token() {
    let server = SharedTestServer::get();
    let email = unique_email("logout2x");
    let password = "password123";

    // Register and get refresh token using existing pattern
    let refresh_token = register_and_login_user(&server, &email, password)
        .unwrap_or_else(|e| panic!("Failed to get user with email {}: {}", email, e));

    // First logout should succeed
    let response1 = server.post_json(
        "/auth/logout",
        json!({
            "refreshToken": &refresh_token
        }),
    );

    assert!(response1.is_ok(), "First logout should succeed");
    assert_eq!(response1.unwrap().status(), 200, "Expected status code 200");

    // Second logout with same token should fail (token already invalidated)
    let response2 = server.post_json(
        "/auth/logout",
        json!({
            "refreshToken": refresh_token
        }),
    );

    assert!(
        response2.is_err(),
        "Second logout should fail - token already invalidated"
    );
    if let Err(ureq::Error::Status(code, response)) = response2 {
        assert_eq!(code, 401, "Expected status code 401 for invalidated token");

        let body = response
            .into_string()
            .expect("Failed to read response body");
        let json: serde_json::Value = serde_json::from_str(&body).expect("Failed to parse JSON");

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
    } else {
        panic!("Expected error status 401");
    }
}
