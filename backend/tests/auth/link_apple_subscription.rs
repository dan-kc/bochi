use crate::common::{
    get_access_token_for_user, make_authenticated_get_request, make_authenticated_post_request,
    make_unauthenticated_post_request, register_user,
};
use crate::generate_email_from_fn;
use axum::http::StatusCode;
use serde_json::json;

#[tokio::test]
async fn test_link_apple_subscription_requires_authentication() {
    // A signed-out device restore should not be able to attach premium sync
    // benefits to any backend account until the user explicitly signs in.
    let (status, json) = make_unauthenticated_post_request(
        "/auth/link-apple-subscription",
        json!({
            "originalTransactionId": "1000001234567891",
            "subscriptionExpiresAt": "2026-05-18T09:00:00"
        }),
    )
    .await;

    assert_eq!(status, StatusCode::UNAUTHORIZED, "Response: {:?}", json);
}

#[tokio::test]
async fn test_link_apple_subscription_marks_signed_in_account_as_apple_premium() {
    // After restoring an Apple subscription on-device and then signing in,
    // the app needs one explicit backend step that links that purchase to the
    // account so sync and premium can both unlock together.
    let email = generate_email_from_fn!(
        test_link_apple_subscription_marks_signed_in_account_as_apple_premium
    );
    let password = "password123";
    let expires_at = "2026-05-18T09:00:00";
    let original_transaction_id = "1000001234567892";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, password).await;

    let (status, json) = make_authenticated_post_request(
        &access_token,
        "/auth/link-apple-subscription",
        json!({
            "originalTransactionId": original_transaction_id,
            "subscriptionExpiresAt": expires_at
        }),
    )
    .await;

    assert_eq!(status, StatusCode::OK, "Response: {:?}", json);
    assert_eq!(json.get("email").and_then(|v| v.as_str()), Some(email.as_str()));
    assert_eq!(
        json.get("subscriptionSource").and_then(|v| v.as_str()),
        Some("apple")
    );
    assert_eq!(
        json.get("subscriptionStatus").and_then(|v| v.as_str()),
        Some("active")
    );
    assert_eq!(json.get("isEntitled").and_then(|v| v.as_bool()), Some(true));
    assert_eq!(
        json.get("subscriptionExpiresAt").and_then(|v| v.as_str()),
        Some(expires_at)
    );

    let (me_status, me_json) = make_authenticated_get_request(&access_token, "/auth/me").await;

    assert_eq!(me_status, StatusCode::OK, "Response: {:?}", me_json);
    assert_eq!(
        me_json.get("subscriptionSource").and_then(|v| v.as_str()),
        Some("apple")
    );
    assert_eq!(
        me_json.get("subscriptionStatus").and_then(|v| v.as_str()),
        Some("active")
    );
    assert_eq!(
        me_json.get("isEntitled").and_then(|v| v.as_bool()),
        Some(true)
    );
}

#[tokio::test]
async fn test_link_apple_subscription_rejects_purchase_already_linked_to_different_account() {
    // One Apple purchase should not silently move from account A to account B.
    // If the restore belongs to another account already, the app should surface
    // a support-style resolution instead of transferring ownership automatically.
    let first_email = generate_email_from_fn!(
        test_link_apple_subscription_rejects_purchase_already_linked_to_different_account
    );
    let second_email = format!("second-{}", first_email);
    let password = "password123";

    register_user(&first_email, password).await;
    register_user(&second_email, password).await;

    let first_access_token = get_access_token_for_user(&first_email, password).await;
    let second_access_token = get_access_token_for_user(&second_email, password).await;

    let original_transaction_id = "1000001234567893";
    let first_link = make_authenticated_post_request(
        &first_access_token,
        "/auth/link-apple-subscription",
        json!({
            "originalTransactionId": original_transaction_id,
            "subscriptionExpiresAt": "2026-05-18T09:00:00"
        }),
    )
    .await;
    assert_eq!(first_link.0, StatusCode::OK, "Response: {:?}", first_link.1);

    let (status, json) = make_authenticated_post_request(
        &second_access_token,
        "/auth/link-apple-subscription",
        json!({
            "originalTransactionId": original_transaction_id,
            "subscriptionExpiresAt": "2026-05-18T09:00:00"
        }),
    )
    .await;

    assert_eq!(status, StatusCode::CONFLICT, "Response: {:?}", json);
    assert_eq!(
        json.get("errors")
            .and_then(|v| v.as_array())
            .and_then(|errors| errors.first())
            .and_then(|error| error.get("code"))
            .and_then(|v| v.as_str()),
        Some("SUBSCRIPTION_ALREADY_LINKED")
    );
}
