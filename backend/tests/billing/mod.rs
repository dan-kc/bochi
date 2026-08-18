use crate::common::{
    get_access_token_for_user, make_authenticated_get_request, make_authenticated_post_request,
    make_unauthenticated_post_request, register_user,
};
use crate::generate_email_from_fn;
use axum::http::StatusCode;
use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
use serde_json::json;
use std::time::Duration;

fn test_signed_payload(payload: serde_json::Value) -> String {
    format!(
        "test-jws:{}",
        URL_SAFE_NO_PAD.encode(payload.to_string().as_bytes())
    )
}

fn test_signed_transaction(
    original_transaction_id: &str,
    transaction_id: &str,
    product_id: &str,
    environment: &str,
    expires_date_ms: Option<i64>,
    revocation_date_ms: Option<i64>,
) -> String {
    test_signed_payload(json!({
        "originalTransactionId": original_transaction_id,
        "transactionId": transaction_id,
        "productId": product_id,
        "environment": environment,
        "expiresDate": expires_date_ms,
        "revocationDate": revocation_date_ms
    }))
}

fn test_signed_renewal_info(
    original_transaction_id: &str,
    product_id: &str,
    environment: &str,
    grace_period_expires_date_ms: Option<i64>,
    renewal_date_ms: Option<i64>,
) -> String {
    test_signed_payload(json!({
        "originalTransactionId": original_transaction_id,
        "productId": product_id,
        "environment": environment,
        "gracePeriodExpiresDate": grace_period_expires_date_ms,
        "renewalDate": renewal_date_ms
    }))
}

#[tokio::test]
async fn test_apple_notification_renewal_updates_linked_entitlement() {
    // A renewal arrives server-to-server, so the next account read should show
    // the latest Apple transaction without waiting for the app to restore.
    std::env::set_var("ALLOW_INSECURE_APPLE_BILLING_TEST_TRANSACTIONS", "true");

    let email = generate_email_from_fn!(test_apple_notification_renewal_updates_linked_entitlement);
    let password = "password123";
    let original_transaction_id = "1000002234567890";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, password).await;

    let link = make_authenticated_post_request(
        &access_token,
        "/auth/link-apple-subscription",
        json!({
            "transactionId": original_transaction_id,
            "originalTransactionId": original_transaction_id,
            "productId": "annual.membership",
            "environment": "xcode",
            "subscriptionExpiresAt": "2027-05-18T09:00:00"
        }),
    )
    .await;
    assert_eq!(link.0, StatusCode::OK, "Response: {:?}", link.1);

    let renewal_payload = test_signed_payload(json!({
        "notificationUUID": "renewal-notification-1",
        "notificationType": "DID_RENEW",
        "subtype": null,
        "version": "2.0",
        "signedDate": 1_809_000_000_000i64,
        "data": {
            "environment": "Xcode",
            "signedTransactionInfo": test_signed_transaction(
                original_transaction_id,
                "1000002234567891",
                "monthly.membership",
                "Xcode",
                Some(1_831_600_800_000),
                None
            )
        }
    }));

    let (status, json) = make_unauthenticated_post_request(
        "/billing/apple/notifications/v2",
        json!({ "signedPayload": renewal_payload }),
    )
    .await;

    assert_eq!(status, StatusCode::OK, "Response: {:?}", json);

    let (me_status, me_json) = make_authenticated_get_request(&access_token, "/auth/me").await;

    assert_eq!(me_status, StatusCode::OK, "Response: {:?}", me_json);
    assert_eq!(
        me_json.get("subscriptionStatus").and_then(|v| v.as_str()),
        Some("active")
    );
    assert_eq!(
        me_json
            .get("subscriptionProductId")
            .and_then(|v| v.as_str()),
        Some("monthly.membership")
    );
    assert_eq!(
        me_json.get("isEntitled").and_then(|v| v.as_bool()),
        Some(true)
    );
}

#[tokio::test]
async fn test_apple_notification_revocation_locks_linked_entitlement() {
    // Refunds and revocations happen outside the app. The backend should lock
    // premium based on Apple's notification even if the user never opens restore.
    std::env::set_var("ALLOW_INSECURE_APPLE_BILLING_TEST_TRANSACTIONS", "true");

    let email =
        generate_email_from_fn!(test_apple_notification_revocation_locks_linked_entitlement);
    let password = "password123";
    let original_transaction_id = "1000003234567890";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, password).await;

    let link = make_authenticated_post_request(
        &access_token,
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
    assert_eq!(link.0, StatusCode::OK, "Response: {:?}", link.1);

    let revocation_payload = test_signed_payload(json!({
        "notificationUUID": "revocation-notification-1",
        "notificationType": "REFUND",
        "subtype": null,
        "version": "2.0",
        "signedDate": 1_809_000_000_000i64,
        "data": {
            "environment": "Xcode",
            "signedTransactionInfo": test_signed_transaction(
                original_transaction_id,
                "1000003234567891",
                "lifetime.membership",
                "Xcode",
                None,
                Some(1_809_000_000_000)
            )
        }
    }));

    let first = make_unauthenticated_post_request(
        "/billing/apple/notifications/v2",
        json!({ "signedPayload": revocation_payload.clone() }),
    )
    .await;
    let duplicate = make_unauthenticated_post_request(
        "/billing/apple/notifications/v2",
        json!({ "signedPayload": revocation_payload }),
    )
    .await;

    assert_eq!(first.0, StatusCode::OK, "Response: {:?}", first.1);
    assert_eq!(duplicate.0, StatusCode::OK, "Response: {:?}", duplicate.1);

    let (me_status, me_json) = make_authenticated_get_request(&access_token, "/auth/me").await;

    assert_eq!(me_status, StatusCode::OK, "Response: {:?}", me_json);
    assert_eq!(
        me_json.get("subscriptionStatus").and_then(|v| v.as_str()),
        Some("revoked")
    );
    assert_eq!(
        me_json.get("isEntitled").and_then(|v| v.as_bool()),
        Some(false)
    );
}

#[tokio::test]
async fn test_apple_notification_expiration_locks_linked_entitlement() {
    // Apple's EXPIRED notification is the entitlement-ending event. The backend
    // should not keep premium open just because the signed transaction payload
    // still contains a future-looking paid-through timestamp.
    std::env::set_var("ALLOW_INSECURE_APPLE_BILLING_TEST_TRANSACTIONS", "true");

    let email =
        generate_email_from_fn!(test_apple_notification_expiration_locks_linked_entitlement);
    let password = "password123";
    let original_transaction_id = "1000007234567890";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, password).await;

    let link = make_authenticated_post_request(
        &access_token,
        "/auth/link-apple-subscription",
        json!({
            "transactionId": original_transaction_id,
            "originalTransactionId": original_transaction_id,
            "productId": "annual.membership",
            "environment": "xcode",
            "subscriptionExpiresAt": "2027-05-18T09:00:00"
        }),
    )
    .await;
    assert_eq!(link.0, StatusCode::OK, "Response: {:?}", link.1);

    let expiration_payload = test_signed_payload(json!({
        "notificationUUID": "expiration-notification-1",
        "notificationType": "EXPIRED",
        "subtype": "BILLING_RETRY",
        "version": "2.0",
        "signedDate": 1_909_000_000_000i64,
        "data": {
            "environment": "Xcode",
            "signedTransactionInfo": test_signed_transaction(
                original_transaction_id,
                "1000007234567891",
                "annual.membership",
                "Xcode",
                Some(1_931_600_800_000),
                None
            )
        }
    }));

    let notification = make_unauthenticated_post_request(
        "/billing/apple/notifications/v2",
        json!({ "signedPayload": expiration_payload }),
    )
    .await;
    assert_eq!(
        notification.0,
        StatusCode::OK,
        "Response: {:?}",
        notification.1
    );

    let (me_status, me_json) = make_authenticated_get_request(&access_token, "/auth/me").await;

    assert_eq!(me_status, StatusCode::OK, "Response: {:?}", me_json);
    assert_eq!(
        me_json.get("subscriptionStatus").and_then(|v| v.as_str()),
        Some("expired")
    );
    assert_eq!(
        me_json.get("isEntitled").and_then(|v| v.as_bool()),
        Some(false)
    );
}

#[tokio::test]
async fn test_apple_notification_grace_period_expired_enters_billing_retry() {
    // Once Apple says the grace period ended, premium access should stop while
    // the App Store continues billing retry in the background.
    std::env::set_var("ALLOW_INSECURE_APPLE_BILLING_TEST_TRANSACTIONS", "true");

    let email =
        generate_email_from_fn!(test_apple_notification_grace_period_expired_enters_billing_retry);
    let password = "password123";
    let original_transaction_id = "1000008234567890";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, password).await;

    let link = make_authenticated_post_request(
        &access_token,
        "/auth/link-apple-subscription",
        json!({
            "transactionId": original_transaction_id,
            "originalTransactionId": original_transaction_id,
            "productId": "monthly.membership",
            "environment": "xcode",
            "subscriptionExpiresAt": "2027-05-18T09:00:00"
        }),
    )
    .await;
    assert_eq!(link.0, StatusCode::OK, "Response: {:?}", link.1);

    let grace_expired_payload = test_signed_payload(json!({
        "notificationUUID": "grace-period-expired-notification-1",
        "notificationType": "GRACE_PERIOD_EXPIRED",
        "subtype": null,
        "version": "2.0",
        "signedDate": 1_909_000_000_000i64,
        "data": {
            "environment": "Xcode",
            "signedTransactionInfo": test_signed_transaction(
                original_transaction_id,
                "1000008234567891",
                "monthly.membership",
                "Xcode",
                Some(1_931_600_800_000),
                None
            )
        }
    }));

    let notification = make_unauthenticated_post_request(
        "/billing/apple/notifications/v2",
        json!({ "signedPayload": grace_expired_payload }),
    )
    .await;
    assert_eq!(
        notification.0,
        StatusCode::OK,
        "Response: {:?}",
        notification.1
    );

    let (me_status, me_json) = make_authenticated_get_request(&access_token, "/auth/me").await;

    assert_eq!(me_status, StatusCode::OK, "Response: {:?}", me_json);
    assert_eq!(
        me_json.get("subscriptionStatus").and_then(|v| v.as_str()),
        Some("billing_retry")
    );
    assert_eq!(
        me_json.get("isEntitled").and_then(|v| v.as_bool()),
        Some(false)
    );
}

#[tokio::test]
async fn test_apple_notification_grace_period_uses_renewal_grace_expiry() {
    // In billing grace period, Apple reports the access window in signedRenewalInfo.
    // The original transaction expiry can already be past and should not lock premium early.
    std::env::set_var("ALLOW_INSECURE_APPLE_BILLING_TEST_TRANSACTIONS", "true");

    let email =
        generate_email_from_fn!(test_apple_notification_grace_period_uses_renewal_grace_expiry);
    let password = "password123";
    let original_transaction_id = "1000012234567890";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, password).await;

    let link = make_authenticated_post_request(
        &access_token,
        "/auth/link-apple-subscription",
        json!({
            "transactionId": original_transaction_id,
            "originalTransactionId": original_transaction_id,
            "productId": "monthly.membership",
            "environment": "xcode",
            "subscriptionExpiresAt": "2027-05-18T09:00:00"
        }),
    )
    .await;
    assert_eq!(link.0, StatusCode::OK, "Response: {:?}", link.1);

    let grace_payload = test_signed_payload(json!({
        "notificationUUID": "grace-period-notification-1",
        "notificationType": "DID_FAIL_TO_RENEW",
        "subtype": "GRACE_PERIOD",
        "version": "2.0",
        "signedDate": 1_909_000_000_000i64,
        "data": {
            "environment": "Xcode",
            "signedTransactionInfo": test_signed_transaction(
                original_transaction_id,
                "1000012234567891",
                "monthly.membership",
                "Xcode",
                Some(1_577_836_800_000),
                None
            ),
            "signedRenewalInfo": test_signed_renewal_info(
                original_transaction_id,
                "monthly.membership",
                "Xcode",
                Some(1_931_600_800_000),
                Some(1_931_600_800_000)
            )
        }
    }));

    let notification = make_unauthenticated_post_request(
        "/billing/apple/notifications/v2",
        json!({ "signedPayload": grace_payload }),
    )
    .await;
    assert_eq!(
        notification.0,
        StatusCode::OK,
        "Response: {:?}",
        notification.1
    );

    let (me_status, me_json) = make_authenticated_get_request(&access_token, "/auth/me").await;

    assert_eq!(me_status, StatusCode::OK, "Response: {:?}", me_json);
    assert_eq!(
        me_json.get("subscriptionStatus").and_then(|v| v.as_str()),
        Some("grace_period")
    );
    assert_eq!(
        me_json.get("isEntitled").and_then(|v| v.as_bool()),
        Some(true)
    );
}

#[tokio::test]
async fn test_apple_notification_refund_reversal_restores_linked_entitlement() {
    // A refund reversal means Apple reinstated a previously revoked purchase, so
    // the refund's revocation timestamp must not keep the account locked.
    std::env::set_var("ALLOW_INSECURE_APPLE_BILLING_TEST_TRANSACTIONS", "true");

    let email = generate_email_from_fn!(
        test_apple_notification_refund_reversal_restores_linked_entitlement
    );
    let password = "password123";
    let original_transaction_id = "1000009234567890";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, password).await;

    let link = make_authenticated_post_request(
        &access_token,
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
    assert_eq!(link.0, StatusCode::OK, "Response: {:?}", link.1);

    let refund_payload = test_signed_payload(json!({
        "notificationUUID": "refund-before-reversal-notification-1",
        "notificationType": "REFUND",
        "subtype": null,
        "version": "2.0",
        "signedDate": 1_909_000_000_000i64,
        "data": {
            "environment": "Xcode",
            "signedTransactionInfo": test_signed_transaction(
                original_transaction_id,
                "1000009234567891",
                "lifetime.membership",
                "Xcode",
                None,
                Some(1_909_000_000_000)
            )
        }
    }));
    let reversal_payload = test_signed_payload(json!({
        "notificationUUID": "refund-reversal-notification-1",
        "notificationType": "REFUND_REVERSED",
        "subtype": null,
        "version": "2.0",
        "signedDate": 1_909_000_100_000i64,
        "data": {
            "environment": "Xcode",
            "signedTransactionInfo": test_signed_transaction(
                original_transaction_id,
                "1000009234567891",
                "lifetime.membership",
                "Xcode",
                None,
                Some(1_909_000_000_000)
            )
        }
    }));

    let refund = make_unauthenticated_post_request(
        "/billing/apple/notifications/v2",
        json!({ "signedPayload": refund_payload }),
    )
    .await;
    assert_eq!(refund.0, StatusCode::OK, "Response: {:?}", refund.1);

    let reversal = make_unauthenticated_post_request(
        "/billing/apple/notifications/v2",
        json!({ "signedPayload": reversal_payload }),
    )
    .await;
    assert_eq!(reversal.0, StatusCode::OK, "Response: {:?}", reversal.1);

    let (me_status, me_json) = make_authenticated_get_request(&access_token, "/auth/me").await;

    assert_eq!(me_status, StatusCode::OK, "Response: {:?}", me_json);
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
async fn test_out_of_order_apple_notification_delivery_keeps_latest_signed_state() {
    // Apple provides signedDate for ordering. A stale notification that arrives
    // later must not undo a newer refund/revocation.
    std::env::set_var("ALLOW_INSECURE_APPLE_BILLING_TEST_TRANSACTIONS", "true");

    let email = generate_email_from_fn!(
        test_out_of_order_apple_notification_delivery_keeps_latest_signed_state
    );
    let password = "password123";
    let original_transaction_id = "1000010234567890";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, password).await;

    let link = make_authenticated_post_request(
        &access_token,
        "/auth/link-apple-subscription",
        json!({
            "transactionId": original_transaction_id,
            "originalTransactionId": original_transaction_id,
            "productId": "annual.membership",
            "environment": "xcode",
            "subscriptionExpiresAt": "2027-05-18T09:00:00"
        }),
    )
    .await;
    assert_eq!(link.0, StatusCode::OK, "Response: {:?}", link.1);

    let newer_refund_payload = test_signed_payload(json!({
        "notificationUUID": "out-of-order-refund-notification-1",
        "notificationType": "REFUND",
        "subtype": null,
        "version": "2.0",
        "signedDate": 1_909_000_100_000i64,
        "data": {
            "environment": "Xcode",
            "signedTransactionInfo": test_signed_transaction(
                original_transaction_id,
                "1000010234567892",
                "annual.membership",
                "Xcode",
                Some(1_931_600_800_000),
                Some(1_909_000_100_000)
            )
        }
    }));
    let older_renewal_payload = test_signed_payload(json!({
        "notificationUUID": "out-of-order-renewal-notification-1",
        "notificationType": "DID_RENEW",
        "subtype": null,
        "version": "2.0",
        "signedDate": 1_809_000_000_000i64,
        "data": {
            "environment": "Xcode",
            "signedTransactionInfo": test_signed_transaction(
                original_transaction_id,
                "1000010234567891",
                "annual.membership",
                "Xcode",
                Some(1_931_600_800_000),
                None
            )
        }
    }));

    let refund = make_unauthenticated_post_request(
        "/billing/apple/notifications/v2",
        json!({ "signedPayload": newer_refund_payload }),
    )
    .await;
    assert_eq!(refund.0, StatusCode::OK, "Response: {:?}", refund.1);

    tokio::time::sleep(Duration::from_millis(5)).await;

    let stale_renewal = make_unauthenticated_post_request(
        "/billing/apple/notifications/v2",
        json!({ "signedPayload": older_renewal_payload }),
    )
    .await;
    assert_eq!(
        stale_renewal.0,
        StatusCode::OK,
        "Response: {:?}",
        stale_renewal.1
    );

    let (me_status, me_json) = make_authenticated_get_request(&access_token, "/auth/me").await;

    assert_eq!(me_status, StatusCode::OK, "Response: {:?}", me_json);
    assert_eq!(
        me_json.get("subscriptionStatus").and_then(|v| v.as_str()),
        Some("revoked")
    );
    assert_eq!(
        me_json.get("isEntitled").and_then(|v| v.as_bool()),
        Some(false)
    );
}

#[tokio::test]
async fn test_link_after_out_of_order_apple_notifications_uses_latest_signed_state() {
    // The same signedDate ordering matters when Apple notifies us before the
    // user signs in and links the local StoreKit entitlement.
    std::env::set_var("ALLOW_INSECURE_APPLE_BILLING_TEST_TRANSACTIONS", "true");

    let email = generate_email_from_fn!(
        test_link_after_out_of_order_apple_notifications_uses_latest_signed_state
    );
    let password = "password123";
    let original_transaction_id = "1000011234567890";

    let newer_refund_payload = test_signed_payload(json!({
        "notificationUUID": "early-out-of-order-refund-notification-1",
        "notificationType": "REFUND",
        "subtype": null,
        "version": "2.0",
        "signedDate": 1_909_000_100_000i64,
        "data": {
            "environment": "Xcode",
            "signedTransactionInfo": test_signed_transaction(
                original_transaction_id,
                "1000011234567892",
                "annual.membership",
                "Xcode",
                Some(1_931_600_800_000),
                Some(1_909_000_100_000)
            )
        }
    }));
    let older_renewal_payload = test_signed_payload(json!({
        "notificationUUID": "early-out-of-order-renewal-notification-1",
        "notificationType": "DID_RENEW",
        "subtype": null,
        "version": "2.0",
        "signedDate": 1_809_000_000_000i64,
        "data": {
            "environment": "Xcode",
            "signedTransactionInfo": test_signed_transaction(
                original_transaction_id,
                "1000011234567891",
                "annual.membership",
                "Xcode",
                Some(1_931_600_800_000),
                None
            )
        }
    }));

    let refund = make_unauthenticated_post_request(
        "/billing/apple/notifications/v2",
        json!({ "signedPayload": newer_refund_payload }),
    )
    .await;
    assert_eq!(refund.0, StatusCode::OK, "Response: {:?}", refund.1);

    tokio::time::sleep(Duration::from_millis(5)).await;

    let stale_renewal = make_unauthenticated_post_request(
        "/billing/apple/notifications/v2",
        json!({ "signedPayload": older_renewal_payload }),
    )
    .await;
    assert_eq!(
        stale_renewal.0,
        StatusCode::OK,
        "Response: {:?}",
        stale_renewal.1
    );

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, password).await;

    let link = make_authenticated_post_request(
        &access_token,
        "/auth/link-apple-subscription",
        json!({
            "transactionId": original_transaction_id,
            "originalTransactionId": original_transaction_id,
            "productId": "annual.membership",
            "environment": "xcode",
            "subscriptionExpiresAt": "2027-05-18T09:00:00"
        }),
    )
    .await;

    assert_eq!(link.0, StatusCode::OK, "Response: {:?}", link.1);
    assert_eq!(
        link.1.get("subscriptionStatus").and_then(|v| v.as_str()),
        Some("revoked")
    );
    assert_eq!(
        link.1.get("isEntitled").and_then(|v| v.as_bool()),
        Some(false)
    );
}

#[tokio::test]
async fn test_apple_notification_for_unlinked_purchase_is_accepted() {
    // Apple can send notifications before a signed-in account links the local
    // restore. A valid but currently unowned event should not be retried forever.
    std::env::set_var("ALLOW_INSECURE_APPLE_BILLING_TEST_TRANSACTIONS", "true");

    let payload = test_signed_payload(json!({
        "notificationUUID": "unlinked-notification-1",
        "notificationType": "DID_RENEW",
        "subtype": null,
        "version": "2.0",
        "signedDate": 1_809_000_000_000i64,
        "data": {
            "environment": "Xcode",
            "signedTransactionInfo": test_signed_transaction(
                "1000004234567890",
                "1000004234567891",
                "annual.membership",
                "Xcode",
                Some(1_831_600_800_000),
                None
            )
        }
    }));

    let (status, json) = make_unauthenticated_post_request(
        "/billing/apple/notifications/v2",
        json!({ "signedPayload": payload }),
    )
    .await;

    assert_eq!(status, StatusCode::OK, "Response: {:?}", json);
}

#[tokio::test]
async fn test_trailing_slash_apple_notification_uses_same_webhook_route() {
    // App Store Connect is configured by hand, so a trailing slash should not
    // make Apple treat an otherwise valid notification as undeliverable.
    std::env::set_var("ALLOW_INSECURE_APPLE_BILLING_TEST_TRANSACTIONS", "true");

    let payload = test_signed_payload(json!({
        "notificationUUID": "trailing-slash-notification-1",
        "notificationType": "DID_RENEW",
        "subtype": null,
        "version": "2.0",
        "signedDate": 1_809_000_000_000i64,
        "data": {
            "environment": "Xcode",
            "signedTransactionInfo": test_signed_transaction(
                "1000006234567890",
                "1000006234567891",
                "annual.membership",
                "Xcode",
                Some(1_831_600_800_000),
                None
            )
        }
    }));

    let (status, json) = make_unauthenticated_post_request(
        "/billing/apple/notifications/v2/",
        json!({ "signedPayload": payload }),
    )
    .await;

    assert_eq!(status, StatusCode::OK, "Response: {:?}", json);
}

#[tokio::test]
async fn test_link_after_early_apple_notification_uses_latest_entitlement_state() {
    // Apple may notify the backend before the app comes back online and links
    // the purchase. Linking later should preserve Apple's latest known state
    // instead of overwriting it with the older client transaction.
    std::env::set_var("ALLOW_INSECURE_APPLE_BILLING_TEST_TRANSACTIONS", "true");

    let email = generate_email_from_fn!(
        test_link_after_early_apple_notification_uses_latest_entitlement_state
    );
    let password = "password123";
    let original_transaction_id = "1000005234567890";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, password).await;

    let early_notification_payload = test_signed_payload(json!({
        "notificationUUID": "early-link-notification-1",
        "notificationType": "DID_RENEW",
        "subtype": null,
        "version": "2.0",
        "signedDate": 1_809_000_000_000i64,
        "data": {
            "environment": "Xcode",
            "signedTransactionInfo": test_signed_transaction(
                original_transaction_id,
                "1000005234567892",
                "monthly.membership",
                "Xcode",
                Some(1_831_600_800_000),
                None
            )
        }
    }));

    let notification = make_unauthenticated_post_request(
        "/billing/apple/notifications/v2",
        json!({ "signedPayload": early_notification_payload }),
    )
    .await;
    assert_eq!(
        notification.0,
        StatusCode::OK,
        "Response: {:?}",
        notification.1
    );

    let link = make_authenticated_post_request(
        &access_token,
        "/auth/link-apple-subscription",
        json!({
            "transactionId": original_transaction_id,
            "originalTransactionId": original_transaction_id,
            "productId": "annual.membership",
            "environment": "xcode",
            "subscriptionExpiresAt": "2027-05-18T09:00:00"
        }),
    )
    .await;
    assert_eq!(link.0, StatusCode::OK, "Response: {:?}", link.1);
    assert_eq!(
        link.1.get("subscriptionProductId").and_then(|v| v.as_str()),
        Some("monthly.membership")
    );

    let (me_status, me_json) = make_authenticated_get_request(&access_token, "/auth/me").await;

    assert_eq!(me_status, StatusCode::OK, "Response: {:?}", me_json);
    assert_eq!(
        me_json
            .get("subscriptionProductId")
            .and_then(|v| v.as_str()),
        Some("monthly.membership")
    );
    assert_eq!(
        me_json.get("isEntitled").and_then(|v| v.as_bool()),
        Some(true)
    );
}
