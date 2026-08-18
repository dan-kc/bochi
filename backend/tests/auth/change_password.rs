use crate::common::{
    create_password_of_length, get_access_token_for_user, make_authenticated_post_request,
    make_unauthenticated_post_request, register_user,
};
use crate::generate_email_from_fn;
use axum::body::Body;
use axum::http::{Request, StatusCode};
use http::Method;
use serde_json::json;
use bochi_backend::router;
use tower::ServiceExt;

#[tokio::test]
async fn test_change_password_success() {
    let email = generate_email_from_fn!(test_change_password_success);
    let old_password = "oldpassword123";
    let new_password = "newpassword456";

    // Register and get access token
    register_user(&email, old_password).await;
    let access_token = get_access_token_for_user(&email, old_password).await;

    // Change password
    let (status, json) = make_authenticated_post_request(
        &access_token,
        "/auth/change-password",
        json!({
            "currentPassword": old_password,
            "newPassword": new_password
        }),
    )
    .await;

    assert_eq!(status, StatusCode::OK, "Response: {:?}", json);
    assert_eq!(json.get("success").and_then(|v| v.as_bool()), Some(true));

    // Verify old password no longer works
    let router = router::router().await;
    let login_response = router
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/auth/login")
                .header(http::header::CONTENT_TYPE, "application/json")
                .body(Body::from(
                    json!({
                        "email": &email,
                        "password": old_password
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
        "Old password should no longer work"
    );

    // Verify new password works
    let router2 = router::router().await;
    let login_response2 = router2
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/auth/login")
                .header(http::header::CONTENT_TYPE, "application/json")
                .body(Body::from(
                    json!({
                        "email": &email,
                        "password": new_password
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
        "New password should work"
    );
}

#[tokio::test]
async fn test_change_password_incorrect_current() {
    let email = generate_email_from_fn!(test_change_password_incorrect_current);
    let password = "correctpassword";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, password).await;

    let (status, json) = make_authenticated_post_request(
        &access_token,
        "/auth/change-password",
        json!({
            "currentPassword": "wrongpassword",
            "newPassword": "newpassword456"
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
async fn test_change_password_new_too_short() {
    let email = generate_email_from_fn!(test_change_password_new_too_short);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, password).await;

    let (status, json) = make_authenticated_post_request(
        &access_token,
        "/auth/change-password",
        json!({
            "currentPassword": password,
            "newPassword": "short"
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
        Some("PASSWORD_TOO_SHORT")
    );
}

#[tokio::test]
async fn test_change_password_new_too_long() {
    let email = generate_email_from_fn!(test_change_password_new_too_long);
    let password = "password123";
    let long_password = create_password_of_length(65);

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, password).await;

    let (status, json) = make_authenticated_post_request(
        &access_token,
        "/auth/change-password",
        json!({
            "currentPassword": password,
            "newPassword": long_password
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
        Some("PASSWORD_TOO_LONG")
    );
}

#[tokio::test]
async fn test_change_password_new_not_ascii() {
    let email = generate_email_from_fn!(test_change_password_new_not_ascii);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, password).await;

    let (status, json) = make_authenticated_post_request(
        &access_token,
        "/auth/change-password",
        json!({
            "currentPassword": password,
            "newPassword": "pass😊word"
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
        Some("PASSWORD_NOT_ASCII")
    );
}

#[tokio::test]
async fn test_change_password_same_as_current() {
    let email = generate_email_from_fn!(test_change_password_same_as_current);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, password).await;

    let (status, json) = make_authenticated_post_request(
        &access_token,
        "/auth/change-password",
        json!({
            "currentPassword": password,
            "newPassword": password
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
        Some("NEW_PASSWORD_SAME_AS_OLD")
    );
}

#[tokio::test]
async fn test_change_password_unauthorized() {
    let (status, json) = make_unauthenticated_post_request(
        "/auth/change-password",
        json!({
            "currentPassword": "password123",
            "newPassword": "newpassword456"
        }),
    )
    .await;

    assert_eq!(status, StatusCode::UNAUTHORIZED, "Response: {:?}", json);
}
