use crate::common::{
    get_access_token_for_user, make_authenticated_get_request, make_authenticated_post_request,
    make_unauthenticated_get_request, make_unauthenticated_post_request, register_user,
};
use crate::generate_email_from_fn;
use axum::http::StatusCode;
use serde_json::json;

// ============================================================================
// Sync Pull (GET /api/sync) Tests
// ============================================================================

#[tokio::test]
async fn test_sync_pull_returns_all_entity_types() {
    let email = generate_email_from_fn!(test_sync_pull_returns_all_entity_types);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    // Create a task first
    let task_body = json!({
        "name": "Test Task",
        "description": "A test task",
        "habit": false
    });
    let (_, task_json) =
        make_authenticated_post_request(&access_token, "/api/tasks", task_body).await;
    let task_id = task_json.get("id").unwrap().as_str().unwrap();

    // Create a trade for that task using POST /api/sync
    let trade_id = uuid::Uuid::new_v4().to_string();
    let sync_body = json!({
        "trades": [{
            "id": trade_id,
            "taskId": task_id,
            "amount": 500,
            "createdAt": "2025-01-01T10:00:00"
        }]
    });
    make_authenticated_post_request(&access_token, "/api/sync", sync_body).await;

    // Now test GET /api/sync
    let (status, json) = make_authenticated_get_request(&access_token, "/api/sync").await;

    assert_eq!(status, StatusCode::OK);

    // Check tasks
    let tasks = json.get("tasks").unwrap().as_array().unwrap();
    assert_eq!(tasks.len(), 1);
    assert_eq!(tasks[0].get("id").unwrap(), task_id);
    assert_eq!(tasks[0].get("name").unwrap(), "Test Task");

    // Check trades
    let trades = json.get("trades").unwrap().as_array().unwrap();
    assert_eq!(trades.len(), 1);
    assert_eq!(trades[0].get("id").unwrap(), &trade_id);
    assert_eq!(trades[0].get("taskId").unwrap(), task_id);
    assert_eq!(trades[0].get("amount").unwrap(), 500);

    // Check balance
    let balance = json.get("balance").unwrap();
    assert_eq!(balance.get("soyBalance").unwrap(), 500.0);
    assert_eq!(balance.get("tofuBalance").unwrap(), 0.0);

    // Check serverTime
    assert!(json.get("serverTime").is_some());
    assert!(json.get("serverTime").unwrap().is_string());
}

#[tokio::test]
async fn test_sync_pull_with_since_filters_all_entities() {
    let email = generate_email_from_fn!(test_sync_pull_with_since_filters_all_entities);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    // Create first task
    let task_body = json!({
        "name": "Old Task",
        "description": "Created before timestamp",
        "habit": false
    });
    make_authenticated_post_request(&access_token, "/api/tasks", task_body).await;

    // Get current server time
    let (_, pull_json) = make_authenticated_get_request(&access_token, "/api/sync").await;
    let server_time = pull_json
        .get("serverTime")
        .unwrap()
        .as_str()
        .unwrap()
        .to_string();

    // Create a new task after getting the timestamp
    let task_body_2 = json!({
        "name": "New Task",
        "description": "Created after timestamp",
        "habit": false
    });
    let (_, new_task_json) =
        make_authenticated_post_request(&access_token, "/api/tasks", task_body_2).await;
    let new_task_id = new_task_json.get("id").unwrap().as_str().unwrap();

    // Pull since the timestamp - should only get the new task
    let url = format!("/api/sync?since={}", urlencoding::encode(&server_time));
    let (status, json) = make_authenticated_get_request(&access_token, &url).await;

    assert_eq!(status, StatusCode::OK);

    let tasks = json.get("tasks").unwrap().as_array().unwrap();
    assert_eq!(tasks.len(), 1);
    assert_eq!(tasks[0].get("id").unwrap(), new_task_id);
    assert_eq!(tasks[0].get("name").unwrap(), "New Task");

    // No new trades since timestamp
    let trades = json.get("trades").unwrap().as_array().unwrap();
    assert_eq!(trades.len(), 0);
}

#[tokio::test]
async fn test_sync_pull_empty_for_new_user() {
    let email = generate_email_from_fn!(test_sync_pull_empty_for_new_user);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let (status, json) = make_authenticated_get_request(&access_token, "/api/sync").await;

    assert_eq!(status, StatusCode::OK);
    assert_eq!(json.get("tasks").unwrap().as_array().unwrap().len(), 0);
    assert_eq!(json.get("trades").unwrap().as_array().unwrap().len(), 0);
    assert_eq!(json.get("balance").unwrap().get("soyBalance").unwrap(), 0.0);
    assert_eq!(
        json.get("balance").unwrap().get("tofuBalance").unwrap(),
        0.0
    );
    assert!(json.get("serverTime").unwrap().is_string());
}

#[tokio::test]
async fn test_sync_pull_requires_authentication() {
    let (status, _) = make_unauthenticated_get_request("/api/sync").await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

// ============================================================================
// Sync Push (POST /api/sync) Tests
// ============================================================================

#[tokio::test]
async fn test_sync_push_creates_task_and_trade_atomically() {
    let email = generate_email_from_fn!(test_sync_push_creates_task_and_trade_atomically);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let task_id = uuid::Uuid::new_v4().to_string();
    let trade_id = uuid::Uuid::new_v4().to_string();

    let body = json!({
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
    });

    let (status, json) = make_authenticated_post_request(&access_token, "/api/sync", body).await;

    assert_eq!(status, StatusCode::OK);

    // Check task was created
    let tasks = json.get("tasks").unwrap().as_array().unwrap();
    assert_eq!(tasks.len(), 1);
    assert_eq!(tasks[0].get("id").unwrap(), &task_id);
    assert_eq!(tasks[0].get("name").unwrap(), "New Task");

    // Check trade was created
    let trades = json.get("trades").unwrap().as_array().unwrap();
    assert_eq!(trades.len(), 1);
    assert_eq!(trades[0].get("id").unwrap(), &trade_id);
    assert_eq!(trades[0].get("taskId").unwrap(), &task_id);
    assert_eq!(trades[0].get("amount").unwrap(), 500);

    // Check balance updated
    assert_eq!(json.get("balance").unwrap().get("soyBalance").unwrap(), 500.0);
}

#[tokio::test]
async fn test_sync_push_ordering_task_before_trade() {
    let email = generate_email_from_fn!(test_sync_push_ordering_task_before_trade);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let task_id = uuid::Uuid::new_v4().to_string();
    let trade_id = uuid::Uuid::new_v4().to_string();

    // Send trade that references a task that will be created in the same request
    let body = json!({
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
    });

    let (status, json) = make_authenticated_post_request(&access_token, "/api/sync", body).await;

    assert_eq!(status, StatusCode::OK);
    assert!(
        json.get("errors").is_none(),
        "Should not have errors: {:?}",
        json
    );

    assert_eq!(json.get("tasks").unwrap().as_array().unwrap().len(), 1);
    assert_eq!(json.get("trades").unwrap().as_array().unwrap().len(), 1);
    assert_eq!(json.get("balance").unwrap().get("soyBalance").unwrap(), 300.0);
}

#[tokio::test]
async fn test_sync_push_partial_failure_rolls_back() {
    let email = generate_email_from_fn!(test_sync_push_partial_failure_rolls_back);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let task_id = uuid::Uuid::new_v4().to_string();
    let trade_id = uuid::Uuid::new_v4().to_string();
    let non_existent_task_id = uuid::Uuid::new_v4().to_string();

    // Try to create a task and a trade that references a non-existent task
    let body = json!({
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
    });

    let (status, json) = make_authenticated_post_request(&access_token, "/api/sync", body).await;

    // Should have an error
    assert!(
        status == StatusCode::BAD_REQUEST || status == StatusCode::INTERNAL_SERVER_ERROR,
        "Expected error status, got: {} with body: {:?}",
        status,
        json
    );

    // Now verify the task was NOT saved by pulling
    let (_, pull_json) = make_authenticated_get_request(&access_token, "/api/sync").await;
    let tasks = pull_json.get("tasks").unwrap().as_array().unwrap();
    assert_eq!(
        tasks.len(),
        0,
        "Task should not have been saved due to rollback"
    );
}

#[tokio::test]
async fn test_sync_push_empty_input_succeeds() {
    let email = generate_email_from_fn!(test_sync_push_empty_input_succeeds);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    // Push with empty input
    let body = json!({});

    let (status, json) = make_authenticated_post_request(&access_token, "/api/sync", body).await;

    assert_eq!(status, StatusCode::OK);
    assert!(
        json.get("errors").is_none(),
        "Should not have errors: {:?}",
        json
    );

    assert_eq!(json.get("tasks").unwrap().as_array().unwrap().len(), 0);
    assert_eq!(json.get("trades").unwrap().as_array().unwrap().len(), 0);
    assert!(json.get("serverTime").unwrap().is_string());
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
    let body = json!({
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
    });

    let (status, json) = make_authenticated_post_request(&access_token, "/api/sync", body).await;

    assert_eq!(status, StatusCode::OK);
    assert!(json.get("errors").is_none(), "Response: {:?}", json);

    assert_eq!(json.get("trades").unwrap().as_array().unwrap().len(), 2);
    // Balance should be sum of both trades: 500 + 300 = 800
    assert_eq!(json.get("balance").unwrap().get("soyBalance").unwrap(), 800.0);
}

#[tokio::test]
async fn test_sync_push_requires_authentication() {
    let body = json!({
        "tasks": [{
            "id": uuid::Uuid::new_v4().to_string(),
            "name": "Test",
            "description": "Test",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00",
            "habit": false
        }]
    });

    let (status, _) = make_unauthenticated_post_request("/api/sync", body).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn test_sync_push_trade_invalid_task_reference_fails() {
    let email = generate_email_from_fn!(test_sync_push_trade_invalid_task_reference_fails);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let trade_id = uuid::Uuid::new_v4().to_string();
    let non_existent_task_id = uuid::Uuid::new_v4().to_string();

    let body = json!({
        "trades": [{
            "id": trade_id,
            "taskId": non_existent_task_id,
            "amount": 500,
            "createdAt": "2025-01-01T10:00:00"
        }]
    });

    let (status, json) = make_authenticated_post_request(&access_token, "/api/sync", body).await;

    assert!(
        status == StatusCode::BAD_REQUEST || status == StatusCode::INTERNAL_SERVER_ERROR,
        "Should have error for invalid task reference"
    );
    assert!(
        json.get("errors").is_some(),
        "Should have errors for invalid task reference"
    );
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

    let body = json!({
        "tasks": [{
            "id": task_id,
            "name": long_name,
            "description": "Valid description",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00",
            "habit": false
        }]
    });

    let (status, json) = make_authenticated_post_request(&access_token, "/api/sync", body).await;

    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert!(
        json.get("errors").is_some(),
        "Should have validation error for long name"
    );

    let errors = json.get("errors").unwrap().as_array().unwrap();
    let error = &errors[0];
    assert_eq!(error.get("code").unwrap().as_str().unwrap(), "BAD_USER_INPUT");
}

#[tokio::test]
async fn test_sync_push_idempotent_same_ids() {
    let email = generate_email_from_fn!(test_sync_push_idempotent_same_ids);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let task_id = uuid::Uuid::new_v4().to_string();
    let trade_id = uuid::Uuid::new_v4().to_string();

    let body = json!({
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
    });

    // First push
    let (status, json) =
        make_authenticated_post_request(&access_token, "/api/sync", body.clone()).await;
    assert_eq!(status, StatusCode::OK);
    assert!(json.get("errors").is_none());
    assert_eq!(json.get("balance").unwrap().get("soyBalance").unwrap(), 500.0);

    // Push same data again - should be idempotent
    let (status, json) = make_authenticated_post_request(&access_token, "/api/sync", body).await;
    assert_eq!(status, StatusCode::OK);
    assert!(json.get("errors").is_none());
    // Balance should still be 500 (not 1000)
    assert_eq!(json.get("balance").unwrap().get("soyBalance").unwrap(), 500.0);

    // Verify only one task and one trade exist
    let (_, pull_json) = make_authenticated_get_request(&access_token, "/api/sync").await;
    assert_eq!(pull_json.get("tasks").unwrap().as_array().unwrap().len(), 1);
    assert_eq!(
        pull_json.get("trades").unwrap().as_array().unwrap().len(),
        1
    );
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
    let push_body = json!({
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
    });

    let (status, _) = make_authenticated_post_request(&access_token, "/api/sync", push_body).await;
    assert_eq!(status, StatusCode::OK);

    // Pull and verify
    let (status, json) = make_authenticated_get_request(&access_token, "/api/sync").await;
    assert_eq!(status, StatusCode::OK);

    let tasks = json.get("tasks").unwrap().as_array().unwrap();
    assert_eq!(tasks.len(), 1);
    assert_eq!(tasks[0].get("id").unwrap(), &task_id);
    assert_eq!(tasks[0].get("name").unwrap(), "Roundtrip Task");
    assert_eq!(tasks[0].get("description").unwrap(), "Testing roundtrip");

    let trades = json.get("trades").unwrap().as_array().unwrap();
    assert_eq!(trades.len(), 1);
    assert_eq!(trades[0].get("id").unwrap(), &trade_id);
    assert_eq!(trades[0].get("taskId").unwrap(), &task_id);
    assert_eq!(trades[0].get("amount").unwrap(), 750);

    assert_eq!(json.get("balance").unwrap().get("soyBalance").unwrap(), 750.0);
}

#[tokio::test]
async fn test_sync_incremental_after_push() {
    let email = generate_email_from_fn!(test_sync_incremental_after_push);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    // First push
    let task1_id = uuid::Uuid::new_v4().to_string();
    let push1_body = json!({
        "tasks": [{
            "id": task1_id,
            "name": "First Task",
            "description": "Created first",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00",
            "habit": false
        }]
    });

    let (_, json1) =
        make_authenticated_post_request(&access_token, "/api/sync", push1_body).await;
    let server_time = json1
        .get("serverTime")
        .unwrap()
        .as_str()
        .unwrap()
        .to_string();

    // Second push with new task
    let task2_id = uuid::Uuid::new_v4().to_string();
    let push2_body = json!({
        "tasks": [{
            "id": task2_id,
            "name": "Second Task",
            "description": "Created second",
            "createdAt": "2025-01-01T11:00:00",
            "updatedAt": "2025-01-01T11:00:00",
            "habit": false
        }]
    });

    make_authenticated_post_request(&access_token, "/api/sync", push2_body).await;

    // Incremental pull using server_time from first push
    let url = format!("/api/sync?since={}", urlencoding::encode(&server_time));
    let (status, json) = make_authenticated_get_request(&access_token, &url).await;
    assert_eq!(status, StatusCode::OK);

    let tasks = json.get("tasks").unwrap().as_array().unwrap();
    // Should only get the second task (created after server_time)
    assert_eq!(tasks.len(), 1);
    assert_eq!(tasks[0].get("id").unwrap(), &task2_id);
    assert_eq!(tasks[0].get("name").unwrap(), "Second Task");
}

// ============================================================================
// Data Isolation Tests
// ============================================================================

#[tokio::test]
async fn test_sync_only_returns_own_data() {
    let email1 = "test_sync_only_returns_own_data_user1_rest@test.com".to_string();
    let email2 = "test_sync_only_returns_own_data_user2_rest@test.com".to_string();
    let password = "password123";

    register_user(&email1, password).await;
    register_user(&email2, password).await;
    let token1 = get_access_token_for_user(&email1, &password).await;
    let token2 = get_access_token_for_user(&email2, &password).await;

    // User 1 creates data
    let task_id = uuid::Uuid::new_v4().to_string();
    let trade_id = uuid::Uuid::new_v4().to_string();

    let push_body = json!({
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
    });

    let (status, _) = make_authenticated_post_request(&token1, "/api/sync", push_body).await;
    assert_eq!(status, StatusCode::OK);

    // User 2 tries to pull
    let (status, json) = make_authenticated_get_request(&token2, "/api/sync").await;
    assert_eq!(status, StatusCode::OK);

    // User 2 should see nothing
    assert_eq!(json.get("tasks").unwrap().as_array().unwrap().len(), 0);
    assert_eq!(json.get("trades").unwrap().as_array().unwrap().len(), 0);
    assert_eq!(json.get("balance").unwrap().get("soyBalance").unwrap(), 0.0);
}
