use crate::common::{get_access_token_for_user, make_authenticated_graphql_request, register_user};
use crate::generate_email_from_fn;
use axum::body::Body;
use axum::http::{Request, StatusCode};
use http::Method;
use serde_json::json;
use tofustash_backend::router;
use tower::ServiceExt;

// ============================================================================
// Unified Sync Pull Query Tests
// ============================================================================

#[tokio::test]
async fn test_sync_pull_returns_all_entity_types() {
    let email = generate_email_from_fn!(test_sync_pull_returns_all_entity_types);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    // Create a task first
    let create_task_query = json!({
        "query": "mutation CreateTask($input: CreateTaskInput!) {
            createTask(input: $input) {
                id
            }
        }",
        "variables": {
            "input": {
                "name": "Test Task",
                "description": "A test task",
                "habit": false
            }
        }
    });
    let (_, task_json) = make_authenticated_graphql_request(&access_token, create_task_query).await;
    let task_id = task_json["data"]["createTask"]["id"].as_str().unwrap();

    // Create a trade for that task using the unified sync mutation
    let trade_id = uuid::Uuid::new_v4().to_string();
    let create_trade_query = json!({
        "query": "mutation Sync($input: SyncInput!) {
            sync(input: $input) {
                trades { id }
            }
        }",
        "variables": {
            "input": {
                "trades": [{
                    "id": trade_id,
                    "taskId": task_id,
                    "amount": 500,
                    "createdAt": "2025-01-01T10:00:00"
                }]
            }
        }
    });
    make_authenticated_graphql_request(&access_token, create_trade_query).await;

    // Now test the unified sync query
    let query = json!({
        "query": "query Sync($since: NaiveDateTime) {
            sync(since: $since) {
                tasks {
                    id
                    name
                    description
                    createdAt
                    updatedAt
                    deletedAt
                    hiddenUntil
                    dueBy
                    minDailyFrequency
                    difficultyRank
                    completedAt
                    habit
                }
                trades {
                    id
                    taskId
                    rewardId
                    amount
                    createdAt
                    updatedAt
                    deletedAt
                }
                balance {
                    soyBalance
                    tofuBalance
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

    let sync = json.get("data").unwrap().get("sync").unwrap();

    // Check tasks
    let tasks = sync.get("tasks").unwrap().as_array().unwrap();
    assert_eq!(tasks.len(), 1);
    assert_eq!(tasks[0].get("id").unwrap(), task_id);
    assert_eq!(tasks[0].get("name").unwrap(), "Test Task");

    // Check trades
    let trades = sync.get("trades").unwrap().as_array().unwrap();
    assert_eq!(trades.len(), 1);
    assert_eq!(trades[0].get("id").unwrap(), &trade_id);
    assert_eq!(trades[0].get("taskId").unwrap(), task_id);
    assert_eq!(trades[0].get("amount").unwrap(), 500);

    // Check balance
    let balance = sync.get("balance").unwrap();
    assert_eq!(balance.get("soyBalance").unwrap(), 500.0);
    assert_eq!(balance.get("tofuBalance").unwrap(), 0.0);

    // Check serverTime
    assert!(sync.get("serverTime").is_some());
    assert!(sync.get("serverTime").unwrap().is_string());
}

#[tokio::test]
async fn test_sync_pull_with_since_filters_all_entities() {
    let email = generate_email_from_fn!(test_sync_pull_with_since_filters_all_entities);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    // Create first task
    let create_task_query = json!({
        "query": "mutation CreateTask($input: CreateTaskInput!) {
            createTask(input: $input) {
                id
            }
        }",
        "variables": {
            "input": {
                "name": "Old Task",
                "description": "Created before timestamp",
                "habit": false
            }
        }
    });
    make_authenticated_graphql_request(&access_token, create_task_query).await;

    // Get current server time
    let pull_query = json!({
        "query": "query Sync($since: NaiveDateTime) {
            sync(since: $since) {
                serverTime
            }
        }",
        "variables": {
            "since": null
        }
    });
    let (_, json) = make_authenticated_graphql_request(&access_token, pull_query).await;
    let server_time = json["data"]["sync"]["serverTime"].as_str().unwrap();

    // Create a new task after getting the timestamp
    let create_task_query_2 = json!({
        "query": "mutation CreateTask($input: CreateTaskInput!) {
            createTask(input: $input) {
                id
            }
        }",
        "variables": {
            "input": {
                "name": "New Task",
                "description": "Created after timestamp",
                "habit": false
            }
        }
    });
    let (_, new_task_json) =
        make_authenticated_graphql_request(&access_token, create_task_query_2).await;
    let new_task_id = new_task_json["data"]["createTask"]["id"].as_str().unwrap();

    // Pull since the timestamp - should only get the new task
    let query = json!({
        "query": "query Sync($since: NaiveDateTime) {
            sync(since: $since) {
                tasks {
                    id
                    name
                }
                trades {
                    id
                }
                serverTime
            }
        }",
        "variables": {
            "since": server_time
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);

    let sync = json["data"]["sync"].as_object().unwrap();
    let tasks = sync["tasks"].as_array().unwrap();
    assert_eq!(tasks.len(), 1);
    assert_eq!(tasks[0]["id"], new_task_id);
    assert_eq!(tasks[0]["name"], "New Task");

    // No new trades since timestamp
    let trades = sync["trades"].as_array().unwrap();
    assert_eq!(trades.len(), 0);
}

#[tokio::test]
async fn test_sync_pull_empty_for_new_user() {
    let email = generate_email_from_fn!(test_sync_pull_empty_for_new_user);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let query = json!({
        "query": "query Sync($since: NaiveDateTime) {
            sync(since: $since) {
                tasks {
                    id
                }
                trades {
                    id
                }
                balance {
                    soyBalance
                    tofuBalance
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

    let sync = json["data"]["sync"].as_object().unwrap();
    assert_eq!(sync["tasks"].as_array().unwrap().len(), 0);
    assert_eq!(sync["trades"].as_array().unwrap().len(), 0);
    assert_eq!(sync["balance"]["soyBalance"], 0.0);
    assert_eq!(sync["balance"]["tofuBalance"], 0.0);
    assert!(sync["serverTime"].is_string());
}

#[tokio::test]
async fn test_sync_pull_requires_authentication() {
    let router = router::router().await;

    let query = json!({
        "query": "query Sync($since: NaiveDateTime) {
            sync(since: $since) {
                tasks { id }
                serverTime
            }
        }",
        "variables": {
            "since": null
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

// ============================================================================
// Unified Sync Push Mutation Tests
// ============================================================================

#[tokio::test]
async fn test_sync_push_creates_task_and_trade_atomically() {
    let email = generate_email_from_fn!(test_sync_push_creates_task_and_trade_atomically);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let task_id = uuid::Uuid::new_v4().to_string();
    let trade_id = uuid::Uuid::new_v4().to_string();

    let query = json!({
        "query": "mutation Sync($input: SyncInput!) {
            sync(input: $input) {
                tasks {
                    id
                    name
                }
                trades {
                    id
                    taskId
                    amount
                }
                balance {
                    soyBalance
                }
                serverTime
            }
        }",
        "variables": {
            "input": {
                "tasks": [{
                    "id": task_id,
                    "name": "New Task",
                    "description": "Created atomically",
                    "createdAt": "2025-01-01T10:00:00",
                    "updatedAt": "2025-01-01T10:00:00",
                    "habit": false
                }],
                "trades": [{
                    "id": trade_id,
                    "taskId": task_id,
                    "amount": 500,
                    "createdAt": "2025-01-01T10:00:00"
                }]
            }
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);
    assert!(json.get("data").is_some(), "Response: {:?}", json);

    let sync = json["data"]["sync"].as_object().unwrap();

    // Check task was created
    let tasks = sync["tasks"].as_array().unwrap();
    assert_eq!(tasks.len(), 1);
    assert_eq!(tasks[0]["id"], task_id);
    assert_eq!(tasks[0]["name"], "New Task");

    // Check trade was created
    let trades = sync["trades"].as_array().unwrap();
    assert_eq!(trades.len(), 1);
    assert_eq!(trades[0]["id"], trade_id);
    assert_eq!(trades[0]["taskId"], task_id);
    assert_eq!(trades[0]["amount"], 500);

    // Check balance updated
    assert_eq!(sync["balance"]["soyBalance"], 500.0);
}

#[tokio::test]
async fn test_sync_push_ordering_task_before_trade() {
    // This test verifies that even if the trade references a task
    // that is being created in the same sync push, it works because
    // the server processes tasks before trades
    let email = generate_email_from_fn!(test_sync_push_ordering_task_before_trade);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let task_id = uuid::Uuid::new_v4().to_string();
    let trade_id = uuid::Uuid::new_v4().to_string();

    // Send trade that references a task that will be created in the same request
    let query = json!({
        "query": "mutation Sync($input: SyncInput!) {
            sync(input: $input) {
                tasks { id }
                trades { id taskId }
                balance { soyBalance }
                serverTime
            }
        }",
        "variables": {
            "input": {
                "tasks": [{
                    "id": task_id,
                    "name": "Task Created First",
                    "description": "Even though trade references it",
                    "createdAt": "2025-01-01T10:00:00",
                    "updatedAt": "2025-01-01T10:00:00",
                    "habit": false
                }],
                "trades": [{
                    "id": trade_id,
                    "taskId": task_id,
                    "amount": 300,
                    "createdAt": "2025-01-01T10:00:00"
                }]
            }
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);
    assert!(
        json.get("errors").is_none(),
        "Should not have errors: {:?}",
        json
    );

    let sync = json["data"]["sync"].as_object().unwrap();
    assert_eq!(sync["tasks"].as_array().unwrap().len(), 1);
    assert_eq!(sync["trades"].as_array().unwrap().len(), 1);
    assert_eq!(sync["balance"]["soyBalance"], 300.0);
}

#[tokio::test]
async fn test_sync_push_partial_failure_rolls_back() {
    // If a trade fails validation, the task should not be persisted
    let email = generate_email_from_fn!(test_sync_push_partial_failure_rolls_back);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let task_id = uuid::Uuid::new_v4().to_string();
    let trade_id = uuid::Uuid::new_v4().to_string();
    let non_existent_task_id = uuid::Uuid::new_v4().to_string();

    // Try to create a task and a trade that references a non-existent task
    let query = json!({
        "query": "mutation Sync($input: SyncInput!) {
            sync(input: $input) {
                tasks { id }
                trades { id }
                serverTime
            }
        }",
        "variables": {
            "input": {
                "tasks": [{
                    "id": task_id,
                    "name": "This Should Not Be Saved",
                    "description": "Because trade will fail",
                    "createdAt": "2025-01-01T10:00:00",
                    "updatedAt": "2025-01-01T10:00:00",
                    "habit": false
                }],
                "trades": [{
                    "id": trade_id,
                    "taskId": non_existent_task_id,
                    "amount": 500,
                    "createdAt": "2025-01-01T10:00:00"
                }]
            }
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);
    // Should have a GraphQL error
    assert!(json.get("errors").is_some(), "Should have errors: {:?}", json);

    // Now verify the task was NOT saved by pulling
    let pull_query = json!({
        "query": "query Sync($since: NaiveDateTime) {
            sync(since: $since) {
                tasks { id }
            }
        }",
        "variables": {
            "since": null
        }
    });

    let (_, pull_json) = make_authenticated_graphql_request(&access_token, pull_query).await;
    let tasks = pull_json["data"]["sync"]["tasks"].as_array().unwrap();
    assert_eq!(tasks.len(), 0, "Task should not have been saved due to rollback");
}

#[tokio::test]
async fn test_sync_push_empty_input_succeeds() {
    let email = generate_email_from_fn!(test_sync_push_empty_input_succeeds);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    // Push with empty/null arrays
    let query = json!({
        "query": "mutation Sync($input: SyncInput!) {
            sync(input: $input) {
                tasks { id }
                trades { id }
                balance { soyBalance }
                serverTime
            }
        }",
        "variables": {
            "input": {}
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);
    assert!(json.get("errors").is_none(), "Should not have errors: {:?}", json);

    let sync = json["data"]["sync"].as_object().unwrap();
    assert_eq!(sync["tasks"].as_array().unwrap().len(), 0);
    assert_eq!(sync["trades"].as_array().unwrap().len(), 0);
    assert!(sync["serverTime"].is_string());
}

#[tokio::test]
async fn test_sync_push_updates_balance_correctly() {
    let email = generate_email_from_fn!(test_sync_push_updates_balance_correctly);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let task_id = uuid::Uuid::new_v4().to_string();
    let trade1_id = uuid::Uuid::new_v4().to_string();
    let trade2_id = uuid::Uuid::new_v4().to_string();

    // Create task and two trades in one sync
    let query = json!({
        "query": "mutation Sync($input: SyncInput!) {
            sync(input: $input) {
                trades { id amount }
                balance { soyBalance }
                serverTime
            }
        }",
        "variables": {
            "input": {
                "tasks": [{
                    "id": task_id,
                    "name": "Task",
                    "description": "For balance test",
                    "createdAt": "2025-01-01T10:00:00",
                    "updatedAt": "2025-01-01T10:00:00",
                    "habit": false
                }],
                "trades": [
                    {
                        "id": trade1_id,
                        "taskId": task_id,
                        "amount": 500,
                        "createdAt": "2025-01-01T10:00:00"
                    },
                    {
                        "id": trade2_id,
                        "taskId": task_id,
                        "amount": 300,
                        "createdAt": "2025-01-01T10:01:00"
                    }
                ]
            }
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);
    assert!(json.get("errors").is_none(), "Response: {:?}", json);

    let sync = json["data"]["sync"].as_object().unwrap();
    assert_eq!(sync["trades"].as_array().unwrap().len(), 2);
    // Balance should be sum of both trades: 500 + 300 = 800
    assert_eq!(sync["balance"]["soyBalance"], 800.0);
}

#[tokio::test]
async fn test_sync_push_requires_authentication() {
    let router = router::router().await;

    let query = json!({
        "query": "mutation Sync($input: SyncInput!) {
            sync(input: $input) {
                tasks { id }
                serverTime
            }
        }",
        "variables": {
            "input": {
                "tasks": [{
                    "id": uuid::Uuid::new_v4().to_string(),
                    "name": "Test",
                    "description": "Test",
                    "createdAt": "2025-01-01T10:00:00",
                    "updatedAt": "2025-01-01T10:00:00",
                    "habit": false
                }]
            }
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
async fn test_sync_push_trade_invalid_task_reference_fails() {
    let email = generate_email_from_fn!(test_sync_push_trade_invalid_task_reference_fails);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let trade_id = uuid::Uuid::new_v4().to_string();
    let non_existent_task_id = uuid::Uuid::new_v4().to_string();

    let query = json!({
        "query": "mutation Sync($input: SyncInput!) {
            sync(input: $input) {
                trades { id }
                serverTime
            }
        }",
        "variables": {
            "input": {
                "trades": [{
                    "id": trade_id,
                    "taskId": non_existent_task_id,
                    "amount": 500,
                    "createdAt": "2025-01-01T10:00:00"
                }]
            }
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);
    assert!(json.get("errors").is_some(), "Should have errors for invalid task reference");
}

#[tokio::test]
async fn test_sync_push_validates_task_fields() {
    let email = generate_email_from_fn!(test_sync_push_validates_task_fields);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let task_id = uuid::Uuid::new_v4().to_string();
    // Name too long (>100 chars)
    let long_name = "a".repeat(101);

    let query = json!({
        "query": "mutation Sync($input: SyncInput!) {
            sync(input: $input) {
                tasks { id }
                serverTime
            }
        }",
        "variables": {
            "input": {
                "tasks": [{
                    "id": task_id,
                    "name": long_name,
                    "description": "Valid description",
                    "createdAt": "2025-01-01T10:00:00",
                    "updatedAt": "2025-01-01T10:00:00",
                    "habit": false
                }]
            }
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);
    assert!(json.get("errors").is_some(), "Should have validation error for long name");

    let errors = json["errors"].as_array().unwrap();
    let error = &errors[0];
    assert!(error["extensions"]["code"].as_str().unwrap() == "BAD_USER_INPUT");
}

#[tokio::test]
async fn test_sync_push_idempotent_same_ids() {
    let email = generate_email_from_fn!(test_sync_push_idempotent_same_ids);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let task_id = uuid::Uuid::new_v4().to_string();
    let trade_id = uuid::Uuid::new_v4().to_string();

    // First push
    let query = json!({
        "query": "mutation Sync($input: SyncInput!) {
            sync(input: $input) {
                tasks { id name }
                trades { id amount }
                balance { soyBalance }
                serverTime
            }
        }",
        "variables": {
            "input": {
                "tasks": [{
                    "id": task_id,
                    "name": "Original Name",
                    "description": "Original",
                    "createdAt": "2025-01-01T10:00:00",
                    "updatedAt": "2025-01-01T10:00:00",
                    "habit": false
                }],
                "trades": [{
                    "id": trade_id,
                    "taskId": task_id,
                    "amount": 500,
                    "createdAt": "2025-01-01T10:00:00"
                }]
            }
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query.clone()).await;
    assert_eq!(status, StatusCode::OK);
    assert!(json.get("errors").is_none());
    assert_eq!(json["data"]["sync"]["balance"]["soyBalance"], 500.0);

    // Push same data again - should be idempotent
    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);
    assert!(json.get("errors").is_none());
    // Balance should still be 500 (not 1000)
    assert_eq!(json["data"]["sync"]["balance"]["soyBalance"], 500.0);

    // Verify only one task and one trade exist
    let pull_query = json!({
        "query": "query Sync($since: NaiveDateTime) {
            sync(since: $since) {
                tasks { id }
                trades { id }
            }
        }",
        "variables": {
            "since": null
        }
    });

    let (_, pull_json) = make_authenticated_graphql_request(&access_token, pull_query).await;
    assert_eq!(pull_json["data"]["sync"]["tasks"].as_array().unwrap().len(), 1);
    assert_eq!(pull_json["data"]["sync"]["trades"].as_array().unwrap().len(), 1);
}

// ============================================================================
// Roundtrip and Incremental Sync Tests
// ============================================================================

#[tokio::test]
async fn test_unified_sync_roundtrip_push_then_pull() {
    let email = generate_email_from_fn!(test_unified_sync_roundtrip_push_then_pull);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let task_id = uuid::Uuid::new_v4().to_string();
    let trade_id = uuid::Uuid::new_v4().to_string();

    // Push
    let push_query = json!({
        "query": "mutation Sync($input: SyncInput!) {
            sync(input: $input) {
                tasks {
                    id
                    name
                    description
                }
                trades {
                    id
                    taskId
                    amount
                }
                serverTime
            }
        }",
        "variables": {
            "input": {
                "tasks": [{
                    "id": task_id,
                    "name": "Roundtrip Task",
                    "description": "Testing roundtrip",
                    "createdAt": "2025-01-01T10:00:00",
                    "updatedAt": "2025-01-01T10:00:00",
                    "habit": false
                }],
                "trades": [{
                    "id": trade_id,
                    "taskId": task_id,
                    "amount": 750,
                    "createdAt": "2025-01-01T10:00:00"
                }]
            }
        }
    });

    let (status, _) = make_authenticated_graphql_request(&access_token, push_query).await;
    assert_eq!(status, StatusCode::OK);

    // Pull and verify
    let pull_query = json!({
        "query": "query Sync($since: NaiveDateTime) {
            sync(since: $since) {
                tasks {
                    id
                    name
                    description
                }
                trades {
                    id
                    taskId
                    amount
                }
                balance {
                    soyBalance
                }
            }
        }",
        "variables": {
            "since": null
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, pull_query).await;
    assert_eq!(status, StatusCode::OK);

    let sync = json["data"]["sync"].as_object().unwrap();

    let tasks = sync["tasks"].as_array().unwrap();
    assert_eq!(tasks.len(), 1);
    assert_eq!(tasks[0]["id"], task_id);
    assert_eq!(tasks[0]["name"], "Roundtrip Task");
    assert_eq!(tasks[0]["description"], "Testing roundtrip");

    let trades = sync["trades"].as_array().unwrap();
    assert_eq!(trades.len(), 1);
    assert_eq!(trades[0]["id"], trade_id);
    assert_eq!(trades[0]["taskId"], task_id);
    assert_eq!(trades[0]["amount"], 750);

    assert_eq!(sync["balance"]["soyBalance"], 750.0);
}

#[tokio::test]
async fn test_sync_incremental_after_push() {
    let email = generate_email_from_fn!(test_sync_incremental_after_push);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    // First push
    let task1_id = uuid::Uuid::new_v4().to_string();
    let push1_query = json!({
        "query": "mutation Sync($input: SyncInput!) {
            sync(input: $input) {
                tasks { id }
                serverTime
            }
        }",
        "variables": {
            "input": {
                "tasks": [{
                    "id": task1_id,
                    "name": "First Task",
                    "description": "Created first",
                    "createdAt": "2025-01-01T10:00:00",
                    "updatedAt": "2025-01-01T10:00:00",
                    "habit": false
                }]
            }
        }
    });

    let (_, json1) = make_authenticated_graphql_request(&access_token, push1_query).await;
    let server_time = json1["data"]["sync"]["serverTime"].as_str().unwrap();

    // Second push with new task
    let task2_id = uuid::Uuid::new_v4().to_string();
    let push2_query = json!({
        "query": "mutation Sync($input: SyncInput!) {
            sync(input: $input) {
                tasks { id }
                serverTime
            }
        }",
        "variables": {
            "input": {
                "tasks": [{
                    "id": task2_id,
                    "name": "Second Task",
                    "description": "Created second",
                    "createdAt": "2025-01-01T11:00:00",
                    "updatedAt": "2025-01-01T11:00:00",
                    "habit": false
                }]
            }
        }
    });

    make_authenticated_graphql_request(&access_token, push2_query).await;

    // Incremental pull using server_time from first push
    let pull_query = json!({
        "query": "query Sync($since: NaiveDateTime) {
            sync(since: $since) {
                tasks {
                    id
                    name
                }
            }
        }",
        "variables": {
            "since": server_time
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, pull_query).await;
    assert_eq!(status, StatusCode::OK);

    let tasks = json["data"]["sync"]["tasks"].as_array().unwrap();
    // Should only get the second task (created after server_time)
    assert_eq!(tasks.len(), 1);
    assert_eq!(tasks[0]["id"], task2_id);
    assert_eq!(tasks[0]["name"], "Second Task");
}

// ============================================================================
// Data Isolation Tests
// ============================================================================

#[tokio::test]
async fn test_sync_only_returns_own_data() {
    let email1 = "test_sync_only_returns_own_data_user1@test.com".to_string();
    let email2 = "test_sync_only_returns_own_data_user2@test.com".to_string();
    let password = "password123";

    register_user(&email1, password).await;
    register_user(&email2, password).await;
    let token1 = get_access_token_for_user(&email1, &password).await;
    let token2 = get_access_token_for_user(&email2, &password).await;

    // User 1 creates data
    let task_id = uuid::Uuid::new_v4().to_string();
    let trade_id = uuid::Uuid::new_v4().to_string();

    let push_query = json!({
        "query": "mutation Sync($input: SyncInput!) {
            sync(input: $input) {
                tasks { id }
                trades { id }
                serverTime
            }
        }",
        "variables": {
            "input": {
                "tasks": [{
                    "id": task_id,
                    "name": "User 1's Task",
                    "description": "Private",
                    "createdAt": "2025-01-01T10:00:00",
                    "updatedAt": "2025-01-01T10:00:00",
                    "habit": false
                }],
                "trades": [{
                    "id": trade_id,
                    "taskId": task_id,
                    "amount": 500,
                    "createdAt": "2025-01-01T10:00:00"
                }]
            }
        }
    });

    let (status, _) = make_authenticated_graphql_request(&token1, push_query).await;
    assert_eq!(status, StatusCode::OK);

    // User 2 tries to pull
    let pull_query = json!({
        "query": "query Sync($since: NaiveDateTime) {
            sync(since: $since) {
                tasks { id }
                trades { id }
                balance { soyBalance }
            }
        }",
        "variables": {
            "since": null
        }
    });

    let (status, json) = make_authenticated_graphql_request(&token2, pull_query).await;
    assert_eq!(status, StatusCode::OK);

    let sync = json["data"]["sync"].as_object().unwrap();
    // User 2 should see nothing
    assert_eq!(sync["tasks"].as_array().unwrap().len(), 0);
    assert_eq!(sync["trades"].as_array().unwrap().len(), 0);
    assert_eq!(sync["balance"]["soyBalance"], 0.0);
}
