use crate::common::{unique_email, SharedTestServer};
use serde_json::json;

fn register_and_login_user(
    server: &SharedTestServer,
    email: &str,
    password: &str,
) -> Result<(String, String), String> {
    // Try to register user first
    let register_response = server.post_json(
        "/auth/register",
        json!({
            "email": email,
            "password": password
        }),
    );

    // If registration fails (user might already exist), try login instead
    let tokens_response = match register_response {
        Ok(resp) => resp,
        Err(_) => {
            // Registration failed, try login
            server
                .post_json(
                    "/auth/login",
                    json!({
                        "email": email,
                        "password": password
                    }),
                )
                .map_err(|e| format!("Both register and login failed: {}", e))?
        }
    };

    let body = tokens_response
        .into_string()
        .map_err(|e| format!("Failed to read response: {}", e))?;
    let json: serde_json::Value =
        serde_json::from_str(&body).map_err(|e| format!("Failed to parse JSON: {}", e))?;

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

#[test]
fn test_refresh_tokens_success() {
    let server = SharedTestServer::get();
    let email = unique_email("refresh");
    let password = "password123";

    // Register and get tokens
    let (refresh_token, _access_token) = register_and_login_user(&server, &email, password)
        .expect("Failed to register and login user");

    // Test refresh tokens
    let response = server.post_json(
        "/auth/refresh-tokens",
        json!({
            "refreshToken": refresh_token
        }),
    );

    assert!(response.is_ok(), "Token refresh should succeed");
    let response = response.unwrap();
    assert_eq!(response.status(), 200, "Expected status code 200");

    let body = response
        .into_string()
        .expect("Failed to read response body");
    let json: serde_json::Value = serde_json::from_str(&body).expect("Failed to parse JSON");

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
    let _new_access_token = json.get("accessToken").unwrap().as_str().unwrap();

    assert_ne!(
        new_refresh_token, refresh_token,
        "New refresh token should be different"
    );
    // Access tokens may be identical if created within the same second (same exp time + user_id)
}

#[test]
fn test_refresh_tokens_invalid_token() {
    let server = SharedTestServer::get();

    let response = server.post_json(
        "/auth/refresh-tokens",
        json!({
            "refreshToken": "invalid.token.here"
        }),
    );

    assert!(response.is_err(), "Refresh with invalid token should fail");
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
fn test_refresh_tokens_malformed_token() {
    let server = SharedTestServer::get();

    let response = server.post_json(
        "/auth/refresh-tokens",
        json!({
            "refreshToken": "not-a-valid-format"
        }),
    );

    assert!(
        response.is_err(),
        "Refresh with malformed token should fail"
    );
    if let Err(ureq::Error::Status(code, response)) = response {
        assert_eq!(code, 401, "Expected status code 401 for malformed token");

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
fn test_refresh_tokens_after_logout() {
    let server = SharedTestServer::get();
    let email = unique_email("logref");
    let password = "password123";

    // Register and get tokens using the shared helper
    let (refresh_token, _access_token) =
        register_and_login_user(&server, &email, password).expect("Failed to get user tokens");

    // Logout should invalidate the refresh token
    let logout_response = server.post_json(
        "/auth/logout",
        json!({
            "refreshToken": &refresh_token
        }),
    );
    assert!(logout_response.is_ok(), "Logout should succeed");

    // Try to refresh with logged out token - should fail
    let response = server.post_json(
        "/auth/refresh-tokens",
        json!({
            "refreshToken": refresh_token
        }),
    );

    assert!(response.is_err(), "Refresh after logout should fail");
    if let Err(ureq::Error::Status(code, response)) = response {
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
        assert_eq!(
            error.get("message").and_then(|v| v.as_str()),
            Some("Invalid refresh token.")
        );
    } else {
        panic!("Expected error status 401");
    }
}

#[test]
fn test_refresh_tokens_multiple_times() {
    let server = SharedTestServer::get();
    let email = unique_email("refreshmulti");
    let password = "password123";

    // Register and get initial tokens
    let (mut refresh_token, _access_token) = register_and_login_user(&server, &email, password)
        .expect("Failed to register and login user");

    // Refresh tokens multiple times
    for i in 0..3 {
        let response = server.post_json(
            "/auth/refresh-tokens",
            json!({
                "refreshToken": &refresh_token
            }),
        );

        assert!(response.is_ok(), "Token refresh {} should succeed", i + 1);
        let response = response.unwrap();
        assert_eq!(response.status(), 200, "Expected status code 200");

        let body = response
            .into_string()
            .expect("Failed to read response body");
        let json: serde_json::Value = serde_json::from_str(&body).expect("Failed to parse JSON");

        let new_refresh_token = json
            .get("refreshToken")
            .and_then(|v| v.as_str())
            .expect("Should have new refreshToken");
        let _new_access_token = json
            .get("accessToken")
            .and_then(|v| v.as_str())
            .expect("Should have new accessToken");

        assert_ne!(
            new_refresh_token, refresh_token,
            "New refresh token should be different"
        );

        // Update for next iteration
        refresh_token = new_refresh_token.to_string();
    }
}
