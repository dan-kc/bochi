use crate::generate_email_from_fn;
use axum::body::Body;
use axum::http::{Request, StatusCode};
use bochi_backend::router;
use http::Method;
use http_body_util::BodyExt;
use serde_json::json;
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
    cookies
        .iter()
        .find(|c| c.starts_with(&format!("{}=", name)))
}

/// Helper to check if a cookie has a specific attribute
fn cookie_has_attribute(cookie: &str, attr: &str) -> bool {
    cookie
        .split(';')
        .map(|s| s.trim().to_lowercase())
        .any(|s| s == attr.to_lowercase() || s.starts_with(&format!("{}=", attr.to_lowercase())))
}

/// Helper to assert a cookie's Max-Age matches the server token lifetime.
fn cookie_has_max_age(cookie: &str, seconds: i64) -> bool {
    cookie_has_attribute(cookie, &format!("Max-Age={seconds}"))
}

async fn sign_in_with_apple_response(email: &str) -> http::Response<Body> {
    std::env::set_var("ALLOW_INSECURE_APPLE_SIGN_IN_TEST_TOKENS", "true");
    let router = router::router().await;
    let request_body = json!({
        "identityToken": format!("test-apple-subject:{}", email),
        "email": email
    });

    router
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/auth/sign-in-with-apple")
                .header(http::header::CONTENT_TYPE, "application/json")
                .body(Body::from(request_body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap()
}

async fn sign_in_with_apple_refresh_token(email: &str) -> String {
    let response = sign_in_with_apple_response(email).await;
    let body_bytes = response.into_body().collect().await.unwrap().to_bytes();
    let json: serde_json::Value = serde_json::from_slice(&body_bytes).unwrap();
    json["refreshToken"].as_str().unwrap().to_string()
}

// ============ Apple Sign-In Cookie Tests ============

#[tokio::test]
async fn test_apple_sign_in_sets_access_token_cookie() {
    let email = generate_email_from_fn!(test_apple_sign_in_sets_access_token_cookie);
    let response = sign_in_with_apple_response(&email).await;

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
async fn test_apple_sign_in_sets_refresh_token_cookie() {
    let email = generate_email_from_fn!(test_apple_sign_in_sets_refresh_token_cookie);
    let response = sign_in_with_apple_response(&email).await;

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

#[tokio::test]
async fn test_apple_sign_in_cookie_max_age_matches_token_lifetime() {
    let email = generate_email_from_fn!(test_apple_sign_in_cookie_max_age_matches_token_lifetime);
    let response = sign_in_with_apple_response(&email).await;

    assert_eq!(response.status(), StatusCode::OK);

    let cookies = get_set_cookie_headers(&response);
    let access_cookie =
        find_cookie(&cookies, "access_token").expect("Register should set access_token");
    let refresh_cookie =
        find_cookie(&cookies, "refresh_token").expect("Register should set refresh_token");

    assert!(
        cookie_has_max_age(access_cookie, 1800),
        "access_token cookie should match the 30 minute JWT lifetime. Got: {}",
        access_cookie
    );
    assert!(
        cookie_has_max_age(refresh_cookie, 2_592_000),
        "refresh_token cookie should match the 30 day refresh token lifetime. Got: {}",
        refresh_cookie
    );
}

// ============ Refresh Token Cookie Tests ============

#[tokio::test]
async fn test_refresh_tokens_sets_new_cookies() {
    let email = generate_email_from_fn!(test_refresh_tokens_sets_new_cookies);
    let refresh_token = sign_in_with_apple_refresh_token(&email).await;

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
    let refresh_token = sign_in_with_apple_refresh_token(&email).await;

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
    let refresh_token = sign_in_with_apple_refresh_token(&email).await;

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
    let valid_refresh_token = sign_in_with_apple_refresh_token(&email).await;

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
    let refresh_token = sign_in_with_apple_refresh_token(&email).await;

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
