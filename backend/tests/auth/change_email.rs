use crate::common::{
    get_access_token_for_user, make_authenticated_post_request, make_unauthenticated_post_request,
    register_user,
};
use crate::generate_email_from_fn;
use axum::body::Body;
use axum::http::{Request, StatusCode};
use http::Method;
use serde_json::json;
use tofustash_backend::router;
use tower::ServiceExt;

#[tokio::test]
async fn test_change_email_success() {
    let old_email = generate_email_from_fn!(test_change_email_success);
    let new_email = "new_test_change_email_success@test.com";
    let password = "password123";

    // Register and get access token
    register_user(&old_email, password).await;
    let access_token = get_access_token_for_user(&old_email, password).await;

    // Change email
    let (status, json) = make_authenticated_post_request(
        &access_token,
        "/auth/change-email",
        json!({
            "newEmail": new_email,
            "password": password
        }),
    )
    .await;

    assert_eq!(status, StatusCode::OK, "Response: {:?}", json);
    assert_eq!(json.get("success").and_then(|v| v.as_bool()), Some(true));

    // Verify old email no longer works for login
    let router = router::router().await;
    let login_response = router
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/auth/login")
                .header(http::header::CONTENT_TYPE, "application/json")
                .body(Body::from(
                    json!({
                        "email": &old_email,
                        "password": password
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(
        login_response.status(),
        StatusCode::UNAUTHORIZED,
        "Old email should no longer work"
    );

    // Verify new email works
    let router2 = router::router().await;
    let login_response2 = router2
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/auth/login")
                .header(http::header::CONTENT_TYPE, "application/json")
                .body(Body::from(
                    json!({
                        "email": new_email,
                        "password": password
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(
        login_response2.status(),
        StatusCode::OK,
        "New email should work"
    );
}

#[tokio::test]
async fn test_change_email_incorrect_password() {
    let email = generate_email_from_fn!(test_change_email_incorrect_password);
    let password = "correctpassword";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, password).await;

    let (status, json) = make_authenticated_post_request(
        &access_token,
        "/auth/change-email",
        json!({
            "newEmail": "new@test.com",
            "password": "wrongpassword"
        }),
    )
    .await;

    assert_eq!(status, StatusCode::UNAUTHORIZED, "Response: {:?}", json);

    let errors = json
        .get("errors")
        .and_then(|v| v.as_array())
        .expect("Should have errors array");
    assert_eq!(errors.len(), 1);
    assert_eq!(
        errors[0].get("code").and_then(|v| v.as_str()),
        Some("INCORRECT_PASSWORD")
    );
}

#[tokio::test]
async fn test_change_email_invalid_format() {
    let email = generate_email_from_fn!(test_change_email_invalid_format);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, password).await;

    let (status, json) = make_authenticated_post_request(
        &access_token,
        "/auth/change-email",
        json!({
            "newEmail": "notanemail",
            "password": password
        }),
    )
    .await;

    assert_eq!(status, StatusCode::BAD_REQUEST, "Response: {:?}", json);

    let errors = json
        .get("errors")
        .and_then(|v| v.as_array())
        .expect("Should have errors array");
    assert_eq!(errors.len(), 1);
    assert_eq!(
        errors[0].get("code").and_then(|v| v.as_str()),
        Some("INVALID_EMAIL_ADDRESS")
    );
}

#[tokio::test]
async fn test_change_email_too_long() {
    let email = generate_email_from_fn!(test_change_email_too_long);
    let password = "password123";
    let long_email = format!("{}@test.com", "x".repeat(246));

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, password).await;

    let (status, json) = make_authenticated_post_request(
        &access_token,
        "/auth/change-email",
        json!({
            "newEmail": long_email,
            "password": password
        }),
    )
    .await;

    assert_eq!(status, StatusCode::BAD_REQUEST, "Response: {:?}", json);

    let errors = json
        .get("errors")
        .and_then(|v| v.as_array())
        .expect("Should have errors array");

    let error_codes: Vec<&str> = errors
        .iter()
        .filter_map(|e| e.get("code").and_then(|v| v.as_str()))
        .collect();

    assert!(error_codes.contains(&"EMAIL_TOO_LONG"));
}

#[tokio::test]
async fn test_change_email_already_in_use() {
    let email1 = generate_email_from_fn!(test_change_email_already_in_use_1);
    let email2 = generate_email_from_fn!(test_change_email_already_in_use_2);
    let password = "password123";

    // Register both users
    register_user(&email1, password).await;
    register_user(&email2, password).await;

    // User 1 tries to change to user 2's email
    let access_token = get_access_token_for_user(&email1, password).await;

    let (status, json) = make_authenticated_post_request(
        &access_token,
        "/auth/change-email",
        json!({
            "newEmail": email2,
            "password": password
        }),
    )
    .await;

    // Generic error to prevent email enumeration
    assert_eq!(status, StatusCode::BAD_REQUEST, "Response: {:?}", json);

    let errors = json
        .get("errors")
        .and_then(|v| v.as_array())
        .expect("Should have errors array");
    assert_eq!(errors.len(), 1);
    assert_eq!(
        errors[0].get("code").and_then(|v| v.as_str()),
        Some("FAILED_TO_CHANGE_EMAIL")
    );
}

#[tokio::test]
async fn test_change_email_same_as_current() {
    let email = generate_email_from_fn!(test_change_email_same_as_current);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, password).await;

    let (status, json) = make_authenticated_post_request(
        &access_token,
        "/auth/change-email",
        json!({
            "newEmail": email,
            "password": password
        }),
    )
    .await;

    assert_eq!(status, StatusCode::BAD_REQUEST, "Response: {:?}", json);

    let errors = json
        .get("errors")
        .and_then(|v| v.as_array())
        .expect("Should have errors array");
    assert_eq!(errors.len(), 1);
    assert_eq!(
        errors[0].get("code").and_then(|v| v.as_str()),
        Some("NEW_EMAIL_SAME_AS_OLD")
    );
}

#[tokio::test]
async fn test_change_email_unauthorized() {
    let (status, json) = make_unauthenticated_post_request(
        "/auth/change-email",
        json!({
            "newEmail": "new@test.com",
            "password": "password123"
        }),
    )
    .await;

    assert_eq!(status, StatusCode::UNAUTHORIZED, "Response: {:?}", json);
}
