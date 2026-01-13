use crate::common::register_user;
use crate::generate_email_from_fn;
use axum::body::Body;
use axum::http::{Request, StatusCode};
use http::Method;
use http_body_util::BodyExt;
use serde_json::json;
use tofustash_backend::router;
use tower::ServiceExt;

/// Helper to extract Set-Cookie headers from a response
fn get_set_cookie_headers(response: &http::Response<axum::body::Body>) -> Vec<String> {
    response
        .headers()
        .get_all(http::header::SET_COOKIE)
        .iter()
        .map(|v| v.to_str().unwrap_or("").to_string())
        .collect()
}

/// Helper to find a specific cookie by name from Set-Cookie headers
fn find_cookie<'a>(cookies: &'a [String], name: &str) -> Option<&'a String> {
    cookies.iter().find(|c| c.starts_with(&format!("{}=", name)))
}

/// Helper to check if a cookie has a specific attribute
fn cookie_has_attribute(cookie: &str, attr: &str) -> bool {
    cookie
        .split(';')
        .map(|s| s.trim().to_lowercase())
        .any(|s| s == attr.to_lowercase() || s.starts_with(&format!("{}=", attr.to_lowercase())))
}

// ============ Register Cookie Tests ============

#[tokio::test]
async fn test_register_sets_access_token_cookie() {
    let router = router::router().await;

    let request_body = json!({
        "email": generate_email_from_fn!(test_register_sets_access_token_cookie),
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

    assert_eq!(response.status(), StatusCode::OK);

    let cookies = get_set_cookie_headers(&response);
    let access_cookie = find_cookie(&cookies, "access_token");

    assert!(
        access_cookie.is_some(),
        "Response should set access_token cookie. Cookies: {:?}",
        cookies
    );

    let access_cookie = access_cookie.unwrap();
    assert!(
        cookie_has_attribute(access_cookie, "HttpOnly"),
        "access_token cookie should be HttpOnly"
    );
    assert!(
        cookie_has_attribute(access_cookie, "Secure"),
        "access_token cookie should be Secure"
    );
    assert!(
        cookie_has_attribute(access_cookie, "SameSite=Strict")
            || cookie_has_attribute(access_cookie, "SameSite=Lax"),
        "access_token cookie should have SameSite attribute"
    );
}

#[tokio::test]
async fn test_register_sets_refresh_token_cookie() {
    let router = router::router().await;

    let request_body = json!({
        "email": generate_email_from_fn!(test_register_sets_refresh_token_cookie),
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

    assert_eq!(response.status(), StatusCode::OK);

    let cookies = get_set_cookie_headers(&response);
    let refresh_cookie = find_cookie(&cookies, "refresh_token");

    assert!(
        refresh_cookie.is_some(),
        "Response should set refresh_token cookie. Cookies: {:?}",
        cookies
    );

    let refresh_cookie = refresh_cookie.unwrap();
    assert!(
        cookie_has_attribute(refresh_cookie, "HttpOnly"),
        "refresh_token cookie should be HttpOnly"
    );
    assert!(
        cookie_has_attribute(refresh_cookie, "Secure"),
        "refresh_token cookie should be Secure"
    );
    assert!(
        cookie_has_attribute(refresh_cookie, "SameSite=Strict")
            || cookie_has_attribute(refresh_cookie, "SameSite=Lax"),
        "refresh_token cookie should have SameSite attribute"
    );
}

// ============ Login Cookie Tests ============

#[tokio::test]
async fn test_login_sets_access_token_cookie() {
    let email = generate_email_from_fn!(test_login_sets_access_token_cookie);
    let password = "password123";

    // First register a user
    register_user(&email, password).await;

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

    let cookies = get_set_cookie_headers(&response);
    let access_cookie = find_cookie(&cookies, "access_token");

    assert!(
        access_cookie.is_some(),
        "Response should set access_token cookie. Cookies: {:?}",
        cookies
    );

    let access_cookie = access_cookie.unwrap();
    assert!(
        cookie_has_attribute(access_cookie, "HttpOnly"),
        "access_token cookie should be HttpOnly"
    );
    assert!(
        cookie_has_attribute(access_cookie, "Secure"),
        "access_token cookie should be Secure"
    );
}

#[tokio::test]
async fn test_login_sets_refresh_token_cookie() {
    let email = generate_email_from_fn!(test_login_sets_refresh_token_cookie);
    let password = "password123";

    // First register a user
    register_user(&email, password).await;

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

    let cookies = get_set_cookie_headers(&response);
    let refresh_cookie = find_cookie(&cookies, "refresh_token");

    assert!(
        refresh_cookie.is_some(),
        "Response should set refresh_token cookie. Cookies: {:?}",
        cookies
    );

    let refresh_cookie = refresh_cookie.unwrap();
    assert!(
        cookie_has_attribute(refresh_cookie, "HttpOnly"),
        "refresh_token cookie should be HttpOnly"
    );
    assert!(
        cookie_has_attribute(refresh_cookie, "Secure"),
        "refresh_token cookie should be Secure"
    );
}

// ============ Refresh Token Cookie Tests ============

#[tokio::test]
async fn test_refresh_tokens_sets_new_cookies() {
    let email = generate_email_from_fn!(test_refresh_tokens_sets_new_cookies);
    let password = "password123";

    // Register and get refresh token from body
    register_user(&email, password).await;

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
    let refresh_token = login_json["refreshToken"].as_str().unwrap();

    // Now refresh tokens
    let router2 = router::router().await;
    let refresh_body = json!({
        "refreshToken": refresh_token
    });

    let refresh_response = router2
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/auth/refresh-tokens")
                .header(http::header::CONTENT_TYPE, "application/json")
                .body(Body::from(refresh_body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(refresh_response.status(), StatusCode::OK);

    let cookies = get_set_cookie_headers(&refresh_response);

    assert!(
        find_cookie(&cookies, "access_token").is_some(),
        "Refresh should set new access_token cookie"
    );
    assert!(
        find_cookie(&cookies, "refresh_token").is_some(),
        "Refresh should set new refresh_token cookie"
    );
}

// ============ Logout Cookie Tests ============

#[tokio::test]
async fn test_logout_clears_cookies() {
    let email = generate_email_from_fn!(test_logout_clears_cookies);
    let password = "password123";

    // Register and login
    register_user(&email, password).await;

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
    let refresh_token = login_json["refreshToken"].as_str().unwrap();

    // Now logout
    let router2 = router::router().await;
    let logout_body = json!({
        "refreshToken": refresh_token
    });

    let logout_response = router2
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/auth/logout")
                .header(http::header::CONTENT_TYPE, "application/json")
                .body(Body::from(logout_body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(logout_response.status(), StatusCode::OK);

    let cookies = get_set_cookie_headers(&logout_response);

    // Check that cookies are cleared (set to empty with past expiry or Max-Age=0)
    let access_cookie = find_cookie(&cookies, "access_token");
    let refresh_cookie = find_cookie(&cookies, "refresh_token");

    assert!(
        access_cookie.is_some(),
        "Logout should set access_token cookie (to clear it)"
    );
    assert!(
        refresh_cookie.is_some(),
        "Logout should set refresh_token cookie (to clear it)"
    );

    // Verify cookies are being cleared (Max-Age=0 or empty value)
    let access_cookie = access_cookie.unwrap();
    let is_cleared = access_cookie.contains("Max-Age=0")
        || access_cookie.contains("max-age=0")
        || access_cookie.starts_with("access_token=;")
        || access_cookie.starts_with("access_token=\"\";");

    assert!(
        is_cleared,
        "access_token cookie should be cleared (Max-Age=0 or empty value). Got: {}",
        access_cookie
    );
}

// ============ Refresh Token from Cookie Tests ============

#[tokio::test]
async fn test_refresh_tokens_from_cookie() {
    let email = generate_email_from_fn!(test_refresh_tokens_from_cookie);
    let password = "password123";

    // Register and get tokens
    register_user(&email, password).await;

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
    let refresh_token = login_json["refreshToken"].as_str().unwrap();

    // Refresh using cookie instead of body
    let router2 = router::router().await;

    let refresh_response = router2
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/auth/refresh-tokens")
                .header(http::header::CONTENT_TYPE, "application/json")
                .header(
                    http::header::COOKIE,
                    format!("refresh_token={}", refresh_token),
                )
                .body(Body::from("{}")) // Empty body - token comes from cookie
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(
        refresh_response.status(),
        StatusCode::OK,
        "Refresh should succeed with token in cookie"
    );

    let refresh_body_bytes = refresh_response
        .into_body()
        .collect()
        .await
        .unwrap()
        .to_bytes();
    let refresh_json: serde_json::Value = serde_json::from_slice(&refresh_body_bytes).unwrap();

    assert!(
        refresh_json["accessToken"].is_string(),
        "Response should contain new accessToken"
    );
    assert!(
        refresh_json["refreshToken"].is_string(),
        "Response should contain new refreshToken"
    );
}

#[tokio::test]
async fn test_refresh_tokens_body_takes_precedence_over_cookie() {
    let email = generate_email_from_fn!(test_refresh_tokens_body_takes_precedence);
    let password = "password123";

    // Register and login
    register_user(&email, password).await;

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
    let valid_refresh_token = login_json["refreshToken"].as_str().unwrap();

    // Send valid token in body, invalid in cookie - should succeed (body takes precedence)
    let router2 = router::router().await;
    let refresh_body = json!({
        "refreshToken": valid_refresh_token
    });

    let refresh_response = router2
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/auth/refresh-tokens")
                .header(http::header::CONTENT_TYPE, "application/json")
                .header(http::header::COOKIE, "refresh_token=invalid_token")
                .body(Body::from(refresh_body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(
        refresh_response.status(),
        StatusCode::OK,
        "Body token should take precedence over cookie"
    );
}

// ============ Logout from Cookie Tests ============

#[tokio::test]
async fn test_logout_from_cookie() {
    let email = generate_email_from_fn!(test_logout_from_cookie);
    let password = "password123";

    // Register and login
    register_user(&email, password).await;

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
    let refresh_token = login_json["refreshToken"].as_str().unwrap();

    // Logout using cookie instead of body
    let router2 = router::router().await;

    let logout_response = router2
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/auth/logout")
                .header(http::header::CONTENT_TYPE, "application/json")
                .header(
                    http::header::COOKIE,
                    format!("refresh_token={}", refresh_token),
                )
                .body(Body::from("{}")) // Empty body - token comes from cookie
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(
        logout_response.status(),
        StatusCode::OK,
        "Logout should succeed with token in cookie"
    );

    // Verify the token is invalidated - try to refresh with it
    let router3 = router::router().await;
    let refresh_body = json!({
        "refreshToken": refresh_token
    });

    let refresh_response = router3
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/auth/refresh-tokens")
                .header(http::header::CONTENT_TYPE, "application/json")
                .body(Body::from(refresh_body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(
        refresh_response.status(),
        StatusCode::UNAUTHORIZED,
        "Token should be invalidated after logout"
    );
}
