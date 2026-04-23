use crate::common::{
    get_access_token_for_user, make_authenticated_get_request, make_unauthenticated_get_request,
    register_user,
};
use crate::generate_email_from_fn;
use axum::http::StatusCode;

#[tokio::test]
async fn test_get_me_requires_authentication() {
    // A signed-out user should not be able to inspect account or subscription state.
    let (status, json) = make_unauthenticated_get_request("/auth/me").await;

    assert_eq!(status, StatusCode::UNAUTHORIZED, "Response: {:?}", json);
}

#[tokio::test]
async fn test_get_me_returns_registered_user_default_subscription_state() {
    // When a user signs in on a device, the app needs one place to learn who the
    // account belongs to and whether premium sync features are currently unlocked.
    let email =
        generate_email_from_fn!(test_get_me_returns_registered_user_default_subscription_state);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, password).await;

    let (status, json) = make_authenticated_get_request(&access_token, "/auth/me").await;

    assert_eq!(status, StatusCode::OK, "Response: {:?}", json);
    assert_eq!(
        json.get("email").and_then(|v| v.as_str()),
        Some(email.as_str())
    );
    assert_eq!(
        json.get("subscriptionSource"),
        Some(&serde_json::Value::Null),
        "New accounts should start without any linked subscription source"
    );
    assert_eq!(
        json.get("subscriptionStatus").and_then(|v| v.as_str()),
        Some("none"),
        "New accounts should report no active subscription state"
    );
    assert_eq!(
        json.get("isEntitled").and_then(|v| v.as_bool()),
        Some(false),
        "New accounts should not unlock premium until a subscription is linked"
    );
    assert_eq!(
        json.get("subscriptionExpiresAt"),
        Some(&serde_json::Value::Null),
        "Without a linked subscription there should be no expiry timestamp"
    );
}
