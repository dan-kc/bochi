use crate::common::{
    make_authenticated_delete_request, make_authenticated_get_request,
    make_authenticated_post_request, make_unauthenticated_delete_request,
    make_unauthenticated_post_request,
};
use axum::body::Body;
use axum::http::{Request, StatusCode};
use bochi_backend::router;
use http::Method;
use http_body_util::BodyExt;
use serde_json::{json, Value};
use tower::ServiceExt;

async fn sign_in_with_apple_subject(subject: &str, email: &str) -> (String, String) {
    std::env::set_var("ALLOW_INSECURE_APPLE_SIGN_IN_TEST_TOKENS", "true");
    let router = router::router().await;

    let response = router
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/auth/sign-in-with-apple")
                .header(http::header::CONTENT_TYPE, "application/json")
                .body(Body::from(
                    json!({
                        "identityToken": format!("test-apple-subject:{}", subject),
                        "email": email
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let body = response
        .into_body()
        .collect()
        .await
        .expect("Failed to read response body")
        .to_bytes();
    let json: Value = serde_json::from_slice(&body).expect("Failed to parse auth response");

    (
        json.get("accessToken")
            .and_then(|value| value.as_str())
            .expect("auth response should include access token")
            .to_string(),
        json.get("refreshToken")
            .and_then(|value| value.as_str())
            .expect("auth response should include refresh token")
            .to_string(),
    )
}

fn upsert_task_body(task_id: &str) -> Value {
    json!({
        "operations": [{
            "operationId": uuid::Uuid::new_v4().to_string(),
            "kind": "upsertTask",
            "baseRecordRevision": null,
            "payload": {
                "id": task_id,
                "name": "Delete me",
                "description": "",
                "createdAt": "2026-07-10T09:00:00",
                "updatedAt": "2026-07-10T09:00:00",
                "deletedAt": null,
                "basePrice": 10,
                "dueDate": null,
                "pinned": false,
                "hidden": false,
                "timerMode": null,
                "timerId": null
            }
        }]
    })
}

async fn link_lifetime_apple_entitlement(access_token: &str, original_transaction_id: &str) {
    std::env::set_var("ALLOW_INSECURE_APPLE_BILLING_TEST_TRANSACTIONS", "true");

    let (status, json) = make_authenticated_post_request(
        access_token,
        "/auth/link-apple-subscription",
        json!({
            "transactionId": original_transaction_id,
            "originalTransactionId": original_transaction_id,
            "productId": "lifetime.membership",
            "environment": "xcode",
            "subscriptionExpiresAt": null
        }),
    )
    .await;

    assert_eq!(status, StatusCode::OK, "Response: {:?}", json);
    assert_eq!(
        json.get("isEntitled").and_then(|value| value.as_bool()),
        Some(true)
    );
}

#[tokio::test]
async fn test_delete_account_requires_authentication() {
    // Account deletion is destructive, so anonymous callers must never be able
    // to initiate it.
    let (status, json) = make_unauthenticated_delete_request("/auth/account").await;

    assert_eq!(status, StatusCode::UNAUTHORIZED, "Response: {:?}", json);
}

#[tokio::test]
async fn test_delete_account_removes_account_data_and_invalidates_refresh_tokens() {
    // Deleting an account should remove synced user content, invalidate existing
    // sessions, and let the same Apple account create a fresh empty account later.
    let subject = "delete-account-content";
    let email = "delete-account-content@example.com";
    let (access_token, refresh_token) = sign_in_with_apple_subject(subject, email).await;

    let task_id = uuid::Uuid::new_v4().to_string();
    let (sync_status, sync_json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", upsert_task_body(&task_id))
            .await;
    assert_eq!(sync_status, StatusCode::OK, "Response: {:?}", sync_json);

    let (delete_status, delete_json) =
        make_authenticated_delete_request(&access_token, "/auth/account").await;
    assert_eq!(delete_status, StatusCode::OK, "Response: {:?}", delete_json);
    assert_eq!(
        delete_json.get("success").and_then(|value| value.as_bool()),
        Some(true)
    );

    let (me_status, _) = make_authenticated_get_request(&access_token, "/auth/me").await;
    assert_eq!(me_status, StatusCode::UNAUTHORIZED);

    let (refresh_status, refresh_json) = make_unauthenticated_post_request(
        "/auth/refresh-tokens",
        json!({ "refreshToken": refresh_token }),
    )
    .await;
    assert_eq!(
        refresh_status,
        StatusCode::UNAUTHORIZED,
        "Response: {:?}",
        refresh_json
    );

    let (new_access_token, _) = sign_in_with_apple_subject(subject, email).await;
    let (new_sync_status, new_sync_json) =
        make_authenticated_get_request(&new_access_token, "/api/v1/sync").await;
    assert_eq!(
        new_sync_status,
        StatusCode::OK,
        "Response: {:?}",
        new_sync_json
    );
    assert_eq!(
        new_sync_json
            .get("tasks")
            .and_then(|value| value.as_array())
            .map(Vec::len),
        Some(0)
    );
}

#[tokio::test]
async fn test_delete_account_unlinks_apple_entitlement_for_future_account() {
    // Deleting the Bochi account should remove the server-side Apple entitlement
    // link so a future fresh account is not blocked by stale ownership.
    let original_transaction_id = "delete-account-original-transaction";
    let (access_token, _) = sign_in_with_apple_subject(
        "delete-account-entitlement",
        "delete-account-entitlement@example.com",
    )
    .await;
    link_lifetime_apple_entitlement(&access_token, original_transaction_id).await;

    let (delete_status, delete_json) =
        make_authenticated_delete_request(&access_token, "/auth/account").await;
    assert_eq!(delete_status, StatusCode::OK, "Response: {:?}", delete_json);

    let (new_access_token, _) = sign_in_with_apple_subject(
        "delete-account-entitlement",
        "delete-account-entitlement@example.com",
    )
    .await;
    link_lifetime_apple_entitlement(&new_access_token, original_transaction_id).await;
}
