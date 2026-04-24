use crate::common::{
    get_access_token_for_user, make_authenticated_get_request, make_authenticated_post_request,
    make_unauthenticated_get_request, register_user,
};
use crate::generate_email_from_fn;
use axum::http::StatusCode;
use serde_json::json;

#[tokio::test]
async fn test_get_balance_success() {
    let email = generate_email_from_fn!(test_get_balance_success);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let (status, json) = make_authenticated_get_request(&access_token, "/api/balance").await;

    assert_eq!(status, StatusCode::OK);
    assert_eq!(json.get("tofuBalance").unwrap(), 0.0);
}

#[tokio::test]
async fn test_get_balance_sums_active_trade_history() {
    let email = generate_email_from_fn!(test_get_balance_sums_active_trade_history);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let habit_body = json!({
        "name": "Balance Endpoint Habit",
        "description": "API balance should follow trades"
    });
    let (_, habit_json) =
        make_authenticated_post_request(&access_token, "/api/habits", habit_body).await;
    let habit_id = habit_json.get("id").unwrap().as_str().unwrap();

    let deleted_at = "2025-01-01T10:10:00";
    let sync_body = json!({
        "trades": [
            {
                "id": uuid::Uuid::new_v4().to_string(),
                "habitId": habit_id,
                "amount": 282,
                "createdAt": "2025-01-01T10:00:00"
            },
            {
                "id": uuid::Uuid::new_v4().to_string(),
                "habitId": habit_id,
                "amount": 50,
                "createdAt": "2025-01-01T10:05:00",
                "deletedAt": deleted_at
            }
        ]
    });
    let (push_status, _) = make_authenticated_post_request(&access_token, "/api/sync", sync_body).await;
    assert_eq!(push_status, StatusCode::OK);

    let (status, json) = make_authenticated_get_request(&access_token, "/api/balance").await;

    assert_eq!(status, StatusCode::OK);
    assert_eq!(json.get("tofuBalance").unwrap(), 282.0);
}

#[tokio::test]
async fn test_get_balance_without_authentication() {
    let (status, _) = make_unauthenticated_get_request("/api/balance").await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}
