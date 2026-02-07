use crate::common::{
    get_access_token_for_user, make_authenticated_get_request, make_unauthenticated_get_request,
    register_user,
};
use crate::generate_email_from_fn;
use axum::http::StatusCode;

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
async fn test_get_balance_without_authentication() {
    let (status, _) = make_unauthenticated_get_request("/api/balance").await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}
