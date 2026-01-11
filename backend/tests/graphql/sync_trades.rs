use crate::common::{get_access_token_for_user, make_authenticated_graphql_request, register_user};
use crate::generate_email_from_fn;
use axum::body::Body;
use axum::http::{Request, StatusCode};
use http::Method;
use http_body_util::BodyExt;
use serde_json::{json, Value};
use tofustash_backend::router;
use tower::ServiceExt;

// ============================================================================
// Balance Query Tests
// ============================================================================

#[tokio::test]
async fn test_balance_starts_at_zero_for_new_user() {
    let email = generate_email_from_fn!(test_balance_starts_at_zero_for_new_user);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let query = json!({
        "query": "query Balance {
            balance {
                soyBalance
                tofuBalance
            }
        }"
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);
    assert!(json.get("data").is_some(), "Response: {:?}", json);

    let balance = json.get("data").unwrap().get("balance").unwrap();
    assert_eq!(balance.get("soyBalance").unwrap(), 0.0);
    assert_eq!(balance.get("tofuBalance").unwrap(), 0.0);
}

#[tokio::test]
async fn test_balance_requires_authentication() {
    let router = router::router().await;

    let query = json!({
        "query": "query Balance {
            balance {
                soyBalance
            }
        }"
    });

    let response = router
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/graphql")
                .header(http::header::CONTENT_TYPE, "application/json")
                .body(Body::from(query.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

// ============================================================================
// syncPushTrades Mutation Tests
// ============================================================================

#[tokio::test]
async fn test_sync_push_trades_creates_new_trade_and_updates_balance() {
    let email = generate_email_from_fn!(test_sync_push_trades_creates_new_trade_and_updates_balance);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    // First create a task
    let create_task_query = json!({
        "query": "mutation CreateTask($input: CreateTaskInput!) {
            createTask(input: $input) {
                id
            }
        }",
        "variables": {
            "input": {
                "name": "Test Task",
                "description": "A test task for trading"
            }
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, create_task_query).await;
    assert_eq!(status, StatusCode::OK);
    let task_id = json
        .get("data")
        .unwrap()
        .get("createTask")
        .unwrap()
        .get("id")
        .unwrap()
        .as_str()
        .unwrap();

    // Push a trade
    let trade_id = uuid::Uuid::new_v4().to_string();
    let query = json!({
        "query": "mutation SyncPushTrades($trades: [SyncTradeInput!]!) {
            syncPushTrades(trades: $trades) {
                trades {
                    id
                    taskId
                    amount
                    createdAt
                    updatedAt
                    deletedAt
                }
                serverTime
                newBalance
            }
        }",
        "variables": {
            "trades": [{
                "id": trade_id,
                "taskId": task_id,
                "amount": 500,
                "createdAt": "2025-01-01T10:00:00"
            }]
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);
    assert!(json.get("data").is_some(), "Response: {:?}", json);

    let sync_push = json.get("data").unwrap().get("syncPushTrades").unwrap();
    let trades = sync_push.get("trades").unwrap().as_array().unwrap();
    assert_eq!(trades.len(), 1);

    let trade = &trades[0];
    assert_eq!(trade.get("id").unwrap(), &trade_id);
    assert_eq!(trade.get("taskId").unwrap(), task_id);
    assert_eq!(trade.get("amount").unwrap(), 500);
    assert!(trade.get("createdAt").is_some());
    assert!(trade.get("updatedAt").is_some());
    assert_eq!(trade.get("deletedAt").unwrap(), &Value::Null);

    // Check balance was updated
    assert_eq!(sync_push.get("newBalance").unwrap(), 500.0);
    assert!(sync_push.get("serverTime").is_some());
}

#[tokio::test]
async fn test_sync_push_trades_with_frontend_calculated_amount() {
    let email = generate_email_from_fn!(test_sync_push_trades_with_frontend_calculated_amount);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    // Create a task
    let create_task_query = json!({
        "query": "mutation CreateTask($input: CreateTaskInput!) {
            createTask(input: $input) {
                id
            }
        }",
        "variables": {
            "input": {
                "name": "Difficult Task",
                "description": "High reward task"
            }
        }
    });

    let (_, json) = make_authenticated_graphql_request(&access_token, create_task_query).await;
    let task_id = json["data"]["createTask"]["id"].as_str().unwrap();

    // Push trade with a specific calculated amount (e.g., 850 soy based on difficulty)
    let trade_id = uuid::Uuid::new_v4().to_string();
    let query = json!({
        "query": "mutation SyncPushTrades($trades: [SyncTradeInput!]!) {
            syncPushTrades(trades: $trades) {
                trades {
                    id
                    amount
                }
                newBalance
            }
        }",
        "variables": {
            "trades": [{
                "id": trade_id,
                "taskId": task_id,
                "amount": 850,
                "createdAt": "2025-01-01T10:00:00"
            }]
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);

    let sync_push = json["data"]["syncPushTrades"].as_object().unwrap();
    let trades = sync_push["trades"].as_array().unwrap();
    assert_eq!(trades[0]["amount"], 850);
    assert_eq!(sync_push["newBalance"], 850.0);
}

#[tokio::test]
async fn test_sync_push_multiple_trades_accumulates_balance() {
    let email = generate_email_from_fn!(test_sync_push_multiple_trades_accumulates_balance);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    // Create a task
    let create_task_query = json!({
        "query": "mutation CreateTask($input: CreateTaskInput!) {
            createTask(input: $input) {
                id
            }
        }",
        "variables": {
            "input": {
                "name": "Repeatable Task",
                "description": "Can complete multiple times"
            }
        }
    });

    let (_, json) = make_authenticated_graphql_request(&access_token, create_task_query).await;
    let task_id = json["data"]["createTask"]["id"].as_str().unwrap();

    // Push three trades at once
    let trade_id_1 = uuid::Uuid::new_v4().to_string();
    let trade_id_2 = uuid::Uuid::new_v4().to_string();
    let trade_id_3 = uuid::Uuid::new_v4().to_string();

    let query = json!({
        "query": "mutation SyncPushTrades($trades: [SyncTradeInput!]!) {
            syncPushTrades(trades: $trades) {
                trades {
                    id
                    amount
                }
                newBalance
            }
        }",
        "variables": {
            "trades": [
                { "id": trade_id_1, "taskId": task_id, "amount": 100, "createdAt": "2025-01-01T10:00:00" },
                { "id": trade_id_2, "taskId": task_id, "amount": 200, "createdAt": "2025-01-01T11:00:00" },
                { "id": trade_id_3, "taskId": task_id, "amount": 300, "createdAt": "2025-01-01T12:00:00" }
            ]
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);

    let sync_push = json["data"]["syncPushTrades"].as_object().unwrap();
    let trades = sync_push["trades"].as_array().unwrap();
    assert_eq!(trades.len(), 3);

    // Balance should be sum of all amounts
    assert_eq!(sync_push["newBalance"], 600.0);
}

#[tokio::test]
async fn test_sync_push_trades_requires_valid_task() {
    let email = generate_email_from_fn!(test_sync_push_trades_requires_valid_task);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let trade_id = uuid::Uuid::new_v4().to_string();
    let fake_task_id = uuid::Uuid::new_v4().to_string();

    let query = json!({
        "query": "mutation SyncPushTrades($trades: [SyncTradeInput!]!) {
            syncPushTrades(trades: $trades) {
                trades {
                    id
                }
                newBalance
            }
        }",
        "variables": {
            "trades": [{
                "id": trade_id,
                "taskId": fake_task_id,
                "amount": 100,
                "createdAt": "2025-01-01T10:00:00"
            }]
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);
    assert!(json.get("errors").is_some(), "Should fail with non-existent task");
}

#[tokio::test]
async fn test_sync_push_trades_requires_authentication() {
    let router = router::router().await;

    let trade_id = uuid::Uuid::new_v4().to_string();
    let task_id = uuid::Uuid::new_v4().to_string();

    let query = json!({
        "query": "mutation SyncPushTrades($trades: [SyncTradeInput!]!) {
            syncPushTrades(trades: $trades) {
                trades {
                    id
                }
                newBalance
            }
        }",
        "variables": {
            "trades": [{
                "id": trade_id,
                "taskId": task_id,
                "amount": 100,
                "createdAt": "2025-01-01T10:00:00"
            }]
        }
    });

    let response = router
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/graphql")
                .header(http::header::CONTENT_TYPE, "application/json")
                .body(Body::from(query.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn test_sync_push_trades_idempotent_same_trade_id() {
    let email = generate_email_from_fn!(test_sync_push_trades_idempotent_same_trade_id);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    // Create a task
    let create_task_query = json!({
        "query": "mutation CreateTask($input: CreateTaskInput!) {
            createTask(input: $input) {
                id
            }
        }",
        "variables": {
            "input": {
                "name": "Test Task",
                "description": "For idempotency test"
            }
        }
    });

    let (_, json) = make_authenticated_graphql_request(&access_token, create_task_query).await;
    let task_id = json["data"]["createTask"]["id"].as_str().unwrap();

    let trade_id = uuid::Uuid::new_v4().to_string();

    // Push the same trade twice
    let query = json!({
        "query": "mutation SyncPushTrades($trades: [SyncTradeInput!]!) {
            syncPushTrades(trades: $trades) {
                trades {
                    id
                }
                newBalance
            }
        }",
        "variables": {
            "trades": [{
                "id": trade_id,
                "taskId": task_id,
                "amount": 100,
                "createdAt": "2025-01-01T10:00:00"
            }]
        }
    });

    // First push
    let (_, json1) = make_authenticated_graphql_request(&access_token, query.clone()).await;
    let balance1 = json1["data"]["syncPushTrades"]["newBalance"].as_f64().unwrap();

    // Second push with same trade ID - should be idempotent
    let (_, json2) = make_authenticated_graphql_request(&access_token, query).await;
    let balance2 = json2["data"]["syncPushTrades"]["newBalance"].as_f64().unwrap();

    // Balance should not double
    assert_eq!(balance1, balance2);
    assert_eq!(balance2, 100.0);
}

// ============================================================================
// syncPullTrades Query Tests
// ============================================================================

#[tokio::test]
async fn test_sync_pull_trades_returns_empty_for_new_user() {
    let email = generate_email_from_fn!(test_sync_pull_trades_returns_empty_for_new_user);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let query = json!({
        "query": "query SyncPullTrades($since: NaiveDateTime) {
            syncPullTrades(since: $since) {
                trades {
                    id
                    taskId
                    amount
                }
                serverTime
            }
        }",
        "variables": {
            "since": null
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);
    assert!(json.get("data").is_some(), "Response: {:?}", json);

    let sync_pull = json["data"]["syncPullTrades"].as_object().unwrap();
    let trades = sync_pull["trades"].as_array().unwrap();
    assert_eq!(trades.len(), 0);
    assert!(sync_pull.get("serverTime").is_some());
}

#[tokio::test]
async fn test_sync_pull_trades_returns_user_trades() {
    let email = generate_email_from_fn!(test_sync_pull_trades_returns_user_trades);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    // Create a task
    let create_task_query = json!({
        "query": "mutation CreateTask($input: CreateTaskInput!) {
            createTask(input: $input) {
                id
            }
        }",
        "variables": {
            "input": {
                "name": "Test Task",
                "description": "For pull test"
            }
        }
    });

    let (_, json) = make_authenticated_graphql_request(&access_token, create_task_query).await;
    let task_id = json["data"]["createTask"]["id"].as_str().unwrap();

    // Push a trade
    let trade_id = uuid::Uuid::new_v4().to_string();
    let push_query = json!({
        "query": "mutation SyncPushTrades($trades: [SyncTradeInput!]!) {
            syncPushTrades(trades: $trades) {
                trades { id }
                newBalance
            }
        }",
        "variables": {
            "trades": [{
                "id": trade_id,
                "taskId": task_id,
                "amount": 250,
                "createdAt": "2025-01-01T10:00:00"
            }]
        }
    });
    make_authenticated_graphql_request(&access_token, push_query).await;

    // Pull trades
    let pull_query = json!({
        "query": "query SyncPullTrades($since: NaiveDateTime) {
            syncPullTrades(since: $since) {
                trades {
                    id
                    taskId
                    amount
                    createdAt
                }
                serverTime
            }
        }",
        "variables": {
            "since": null
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, pull_query).await;
    assert_eq!(status, StatusCode::OK);

    let trades = json["data"]["syncPullTrades"]["trades"].as_array().unwrap();
    assert_eq!(trades.len(), 1);
    assert_eq!(trades[0]["id"], trade_id);
    assert_eq!(trades[0]["taskId"], task_id);
    assert_eq!(trades[0]["amount"], 250);
}

#[tokio::test]
async fn test_sync_pull_trades_since_timestamp() {
    let email = generate_email_from_fn!(test_sync_pull_trades_since_timestamp);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    // Create a task
    let create_task_query = json!({
        "query": "mutation CreateTask($input: CreateTaskInput!) {
            createTask(input: $input) {
                id
            }
        }",
        "variables": {
            "input": {
                "name": "Test Task",
                "description": "For timestamp test"
            }
        }
    });

    let (_, json) = make_authenticated_graphql_request(&access_token, create_task_query).await;
    let task_id = json["data"]["createTask"]["id"].as_str().unwrap();

    // Push first trade
    let trade_id_1 = uuid::Uuid::new_v4().to_string();
    let push_query = json!({
        "query": "mutation SyncPushTrades($trades: [SyncTradeInput!]!) {
            syncPushTrades(trades: $trades) {
                trades { id }
                serverTime
                newBalance
            }
        }",
        "variables": {
            "trades": [{
                "id": trade_id_1,
                "taskId": task_id,
                "amount": 100,
                "createdAt": "2025-01-01T10:00:00"
            }]
        }
    });
    let (_, json) = make_authenticated_graphql_request(&access_token, push_query).await;
    let server_time = json["data"]["syncPushTrades"]["serverTime"].as_str().unwrap();

    // Push second trade after getting server time
    let trade_id_2 = uuid::Uuid::new_v4().to_string();
    let push_query_2 = json!({
        "query": "mutation SyncPushTrades($trades: [SyncTradeInput!]!) {
            syncPushTrades(trades: $trades) {
                trades { id }
                newBalance
            }
        }",
        "variables": {
            "trades": [{
                "id": trade_id_2,
                "taskId": task_id,
                "amount": 200,
                "createdAt": "2025-01-02T10:00:00"
            }]
        }
    });
    make_authenticated_graphql_request(&access_token, push_query_2).await;

    // Pull trades since the first push - should only get second trade
    let pull_query = json!({
        "query": "query SyncPullTrades($since: NaiveDateTime) {
            syncPullTrades(since: $since) {
                trades {
                    id
                    amount
                }
                serverTime
            }
        }",
        "variables": {
            "since": server_time
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, pull_query).await;
    assert_eq!(status, StatusCode::OK);

    let trades = json["data"]["syncPullTrades"]["trades"].as_array().unwrap();
    assert_eq!(trades.len(), 1);
    assert_eq!(trades[0]["id"], trade_id_2);
    assert_eq!(trades[0]["amount"], 200);
}

#[tokio::test]
async fn test_sync_pull_trades_only_returns_own_trades() {
    let email1 = generate_email_from_fn!(test_sync_pull_trades_only_returns_own_trades);
    let email2 = format!("other_{}", email1);
    let password = "password123";

    register_user(&email1, password).await;
    register_user(&email2, password).await;

    let access_token1 = get_access_token_for_user(&email1, &password).await;
    let access_token2 = get_access_token_for_user(&email2, &password).await;

    // User 1 creates a task and trade
    let create_task_query = json!({
        "query": "mutation CreateTask($input: CreateTaskInput!) {
            createTask(input: $input) {
                id
            }
        }",
        "variables": {
            "input": {
                "name": "User 1 Task",
                "description": "Belongs to user 1"
            }
        }
    });

    let (_, json) = make_authenticated_graphql_request(&access_token1, create_task_query).await;
    let task_id = json["data"]["createTask"]["id"].as_str().unwrap();

    let trade_id = uuid::Uuid::new_v4().to_string();
    let push_query = json!({
        "query": "mutation SyncPushTrades($trades: [SyncTradeInput!]!) {
            syncPushTrades(trades: $trades) {
                trades { id }
                newBalance
            }
        }",
        "variables": {
            "trades": [{
                "id": trade_id,
                "taskId": task_id,
                "amount": 100,
                "createdAt": "2025-01-01T10:00:00"
            }]
        }
    });
    make_authenticated_graphql_request(&access_token1, push_query).await;

    // User 2 pulls trades - should see none
    let pull_query = json!({
        "query": "query SyncPullTrades($since: NaiveDateTime) {
            syncPullTrades(since: $since) {
                trades {
                    id
                }
                serverTime
            }
        }",
        "variables": {
            "since": null
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token2, pull_query).await;
    assert_eq!(status, StatusCode::OK);

    let trades = json["data"]["syncPullTrades"]["trades"].as_array().unwrap();
    assert_eq!(trades.len(), 0);
}

// ============================================================================
// Task Completion with completed_at Tests
// ============================================================================

#[tokio::test]
async fn test_sync_push_task_with_completed_at() {
    let email = generate_email_from_fn!(test_sync_push_task_with_completed_at);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let task_id = uuid::Uuid::new_v4().to_string();

    let query = json!({
        "query": "mutation SyncPush($tasks: [SyncTaskInput!]!) {
            syncPush(tasks: $tasks) {
                tasks {
                    id
                    name
                    completedAt
                }
                serverTime
            }
        }",
        "variables": {
            "tasks": [{
                "id": task_id,
                "name": "Completed Task",
                "description": "This task is done",
                "createdAt": "2025-01-01T10:00:00",
                "updatedAt": "2025-01-02T10:00:00",
                "completedAt": "2025-01-02T10:00:00"
            }]
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);
    assert!(json.get("data").is_some(), "Response: {:?}", json);

    let tasks = json["data"]["syncPush"]["tasks"].as_array().unwrap();
    assert_eq!(tasks.len(), 1);
    assert_eq!(tasks[0]["completedAt"], "2025-01-02T10:00:00");
}

#[tokio::test]
async fn test_sync_pull_includes_completed_at() {
    let email = generate_email_from_fn!(test_sync_pull_includes_completed_at);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    // Push a completed task
    let task_id = uuid::Uuid::new_v4().to_string();
    let push_query = json!({
        "query": "mutation SyncPush($tasks: [SyncTaskInput!]!) {
            syncPush(tasks: $tasks) {
                tasks { id }
                serverTime
            }
        }",
        "variables": {
            "tasks": [{
                "id": task_id,
                "name": "Completed Task",
                "description": "Done!",
                "createdAt": "2025-01-01T10:00:00",
                "updatedAt": "2025-01-02T10:00:00",
                "completedAt": "2025-01-02T09:30:00"
            }]
        }
    });
    make_authenticated_graphql_request(&access_token, push_query).await;

    // Pull and verify completed_at is present
    let pull_query = json!({
        "query": "query SyncPull($since: NaiveDateTime) {
            syncPull(since: $since) {
                tasks {
                    id
                    name
                    completedAt
                }
                serverTime
            }
        }",
        "variables": {
            "since": null
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, pull_query).await;
    assert_eq!(status, StatusCode::OK);

    let tasks = json["data"]["syncPull"]["tasks"].as_array().unwrap();
    assert_eq!(tasks.len(), 1);
    assert_eq!(tasks[0]["completedAt"], "2025-01-02T09:30:00");
}

#[tokio::test]
async fn test_habit_task_no_completed_at() {
    let email = generate_email_from_fn!(test_habit_task_no_completed_at);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    // Create a habit (task with minDailyFrequency) - should not have completedAt
    let task_id = uuid::Uuid::new_v4().to_string();
    let push_query = json!({
        "query": "mutation SyncPush($tasks: [SyncTaskInput!]!) {
            syncPush(tasks: $tasks) {
                tasks {
                    id
                    minDailyFrequency
                    completedAt
                }
                serverTime
            }
        }",
        "variables": {
            "tasks": [{
                "id": task_id,
                "name": "Daily Exercise",
                "description": "A habit",
                "createdAt": "2025-01-01T10:00:00",
                "updatedAt": "2025-01-01T10:00:00",
                "minDailyFrequency": 100.0
            }]
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, push_query).await;
    assert_eq!(status, StatusCode::OK);

    let tasks = json["data"]["syncPush"]["tasks"].as_array().unwrap();
    assert_eq!(tasks[0]["minDailyFrequency"], 100.0);
    assert_eq!(tasks[0]["completedAt"], Value::Null);
}

// ============================================================================
// Anonymous Account Merge Tests for Trades
// ============================================================================

/// Helper to call /auth/anonymous endpoint
async fn anonymous_auth(device_id: &str) -> (StatusCode, serde_json::Value) {
    let router = router::router().await;

    let request_body = json!({
        "deviceId": device_id
    });

    let response = router
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/auth/anonymous")
                .header(http::header::CONTENT_TYPE, "application/json")
                .body(Body::from(request_body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    let status = response.status();
    let response_body_bytes = response
        .into_body()
        .collect()
        .await
        .expect("Failed to read response body")
        .to_bytes();
    let json: serde_json::Value =
        serde_json::from_slice(&response_body_bytes).expect("Failed to parse JSON response body");

    (status, json)
}

/// Helper to claim an anonymous account
async fn claim_account(access_token: &str, email: &str, password: &str) -> (StatusCode, serde_json::Value) {
    let router = router::router().await;

    let request_body = json!({
        "email": email,
        "password": password
    });

    let response = router
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/auth/claim")
                .header(http::header::CONTENT_TYPE, "application/json")
                .header(http::header::AUTHORIZATION, format!("Bearer {}", access_token))
                .body(Body::from(request_body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    let status = response.status();
    let response_body_bytes = response
        .into_body()
        .collect()
        .await
        .expect("Failed to read response body")
        .to_bytes();
    let json: serde_json::Value =
        serde_json::from_slice(&response_body_bytes).expect("Failed to parse JSON response body");

    (status, json)
}

#[tokio::test]
async fn test_anonymous_user_can_create_trades_and_earn_balance() {
    let device_id = uuid::Uuid::new_v4().to_string();
    let (status, anon_json) = anonymous_auth(&device_id).await;
    assert_eq!(status, StatusCode::OK);

    let anon_access_token = anon_json["accessToken"].as_str().unwrap();

    // Create a task
    let task_id = uuid::Uuid::new_v4().to_string();
    let create_task_query = json!({
        "query": "mutation SyncPush($tasks: [SyncTaskInput!]!) {
            syncPush(tasks: $tasks) {
                tasks { id }
                serverTime
            }
        }",
        "variables": {
            "tasks": [{
                "id": task_id,
                "name": "Anonymous Task",
                "description": "Created anonymously",
                "createdAt": "2025-01-01T10:00:00",
                "updatedAt": "2025-01-01T10:00:00"
            }]
        }
    });
    make_authenticated_graphql_request(anon_access_token, create_task_query).await;

    // Create a trade
    let trade_id = uuid::Uuid::new_v4().to_string();
    let push_trade_query = json!({
        "query": "mutation SyncPushTrades($trades: [SyncTradeInput!]!) {
            syncPushTrades(trades: $trades) {
                trades { id }
                newBalance
            }
        }",
        "variables": {
            "trades": [{
                "id": trade_id,
                "taskId": task_id,
                "amount": 500,
                "createdAt": "2025-01-01T11:00:00"
            }]
        }
    });

    let (status, json) = make_authenticated_graphql_request(anon_access_token, push_trade_query).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["data"]["syncPushTrades"]["newBalance"], 500.0);

    // Verify balance query
    let balance_query = json!({
        "query": "query Balance {
            balance {
                soyBalance
            }
        }"
    });

    let (status, json) = make_authenticated_graphql_request(anon_access_token, balance_query).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["data"]["balance"]["soyBalance"], 500.0);
}

#[tokio::test]
async fn test_balance_preserved_after_claim_account() {
    let device_id = uuid::Uuid::new_v4().to_string();
    let (status, anon_json) = anonymous_auth(&device_id).await;
    assert_eq!(status, StatusCode::OK);

    let anon_access_token = anon_json["accessToken"].as_str().unwrap();

    // Create a task and trade as anonymous
    let task_id = uuid::Uuid::new_v4().to_string();
    let create_task_query = json!({
        "query": "mutation SyncPush($tasks: [SyncTaskInput!]!) {
            syncPush(tasks: $tasks) {
                tasks { id }
                serverTime
            }
        }",
        "variables": {
            "tasks": [{
                "id": task_id,
                "name": "Task before claim",
                "description": "Will keep after claim",
                "createdAt": "2025-01-01T10:00:00",
                "updatedAt": "2025-01-01T10:00:00"
            }]
        }
    });
    make_authenticated_graphql_request(anon_access_token, create_task_query).await;

    let trade_id = uuid::Uuid::new_v4().to_string();
    let push_trade_query = json!({
        "query": "mutation SyncPushTrades($trades: [SyncTradeInput!]!) {
            syncPushTrades(trades: $trades) {
                trades { id }
                newBalance
            }
        }",
        "variables": {
            "trades": [{
                "id": trade_id,
                "taskId": task_id,
                "amount": 750,
                "createdAt": "2025-01-01T11:00:00"
            }]
        }
    });
    make_authenticated_graphql_request(anon_access_token, push_trade_query).await;

    // Claim the account
    let email = generate_email_from_fn!(test_balance_preserved_after_claim_account);
    let password = "password123";
    let (status, claim_json) = claim_account(anon_access_token, &email, password).await;
    assert_eq!(status, StatusCode::OK);

    // Get new access token for claimed account
    let new_access_token = claim_json["accessToken"].as_str().unwrap();

    // Verify balance is preserved
    let balance_query = json!({
        "query": "query Balance {
            balance {
                soyBalance
            }
        }"
    });

    let (status, json) = make_authenticated_graphql_request(new_access_token, balance_query).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["data"]["balance"]["soyBalance"], 750.0);
}

#[tokio::test]
async fn test_trades_preserved_after_claim_account() {
    let device_id = uuid::Uuid::new_v4().to_string();
    let (status, anon_json) = anonymous_auth(&device_id).await;
    assert_eq!(status, StatusCode::OK);

    let anon_access_token = anon_json["accessToken"].as_str().unwrap();

    // Create task and trade as anonymous
    let task_id = uuid::Uuid::new_v4().to_string();
    let create_task_query = json!({
        "query": "mutation SyncPush($tasks: [SyncTaskInput!]!) {
            syncPush(tasks: $tasks) {
                tasks { id }
                serverTime
            }
        }",
        "variables": {
            "tasks": [{
                "id": task_id,
                "name": "Task",
                "description": "Desc",
                "createdAt": "2025-01-01T10:00:00",
                "updatedAt": "2025-01-01T10:00:00"
            }]
        }
    });
    make_authenticated_graphql_request(anon_access_token, create_task_query).await;

    let trade_id = uuid::Uuid::new_v4().to_string();
    let push_trade_query = json!({
        "query": "mutation SyncPushTrades($trades: [SyncTradeInput!]!) {
            syncPushTrades(trades: $trades) {
                trades { id }
                newBalance
            }
        }",
        "variables": {
            "trades": [{
                "id": trade_id,
                "taskId": task_id,
                "amount": 300,
                "createdAt": "2025-01-01T11:00:00"
            }]
        }
    });
    make_authenticated_graphql_request(anon_access_token, push_trade_query).await;

    // Claim the account
    let email = generate_email_from_fn!(test_trades_preserved_after_claim_account);
    let password = "password123";
    let (status, claim_json) = claim_account(anon_access_token, &email, password).await;
    assert_eq!(status, StatusCode::OK);

    let new_access_token = claim_json["accessToken"].as_str().unwrap();

    // Verify trades are preserved
    let pull_query = json!({
        "query": "query SyncPullTrades($since: NaiveDateTime) {
            syncPullTrades(since: $since) {
                trades {
                    id
                    amount
                }
                serverTime
            }
        }",
        "variables": {
            "since": null
        }
    });

    let (status, json) = make_authenticated_graphql_request(new_access_token, pull_query).await;
    assert_eq!(status, StatusCode::OK);

    let trades = json["data"]["syncPullTrades"]["trades"].as_array().unwrap();
    assert_eq!(trades.len(), 1);
    assert_eq!(trades[0]["id"], trade_id);
    assert_eq!(trades[0]["amount"], 300);
}
