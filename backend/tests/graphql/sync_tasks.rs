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
// syncPull Query Tests
// ============================================================================

#[tokio::test]
async fn test_sync_pull_returns_empty_for_new_user() {
    let email = generate_email_from_fn!(test_sync_pull_returns_empty_for_new_user);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let query = json!({
        "query": "query SyncPull($since: NaiveDateTime) {
            syncPull(since: $since) {
                tasks {
                    id
                    name
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

    let sync_pull = json.get("data").unwrap().get("syncPull").unwrap();
    let tasks = sync_pull.get("tasks").unwrap().as_array().unwrap();
    assert_eq!(tasks.len(), 0);

    // Should return server time
    assert!(sync_pull.get("serverTime").is_some());
    assert!(sync_pull.get("serverTime").unwrap().is_string());
}

#[tokio::test]
async fn test_sync_pull_returns_all_tasks_when_since_is_null() {
    let email = generate_email_from_fn!(test_sync_pull_returns_all_tasks_when_since_is_null);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    // Create some tasks first
    let create_task_query = json!({
        "query": "mutation CreateTask($input: CreateTaskInput!) {
            createTask(input: $input) {
                id
                name
            }
        }",
        "variables": {
            "input": {
                "name": "Task 1",
                "description": "Description 1"
            }
        }
    });
    make_authenticated_graphql_request(&access_token, create_task_query.clone()).await;

    let create_task_query_2 = json!({
        "query": "mutation CreateTask($input: CreateTaskInput!) {
            createTask(input: $input) {
                id
                name
            }
        }",
        "variables": {
            "input": {
                "name": "Task 2",
                "description": "Description 2"
            }
        }
    });
    make_authenticated_graphql_request(&access_token, create_task_query_2).await;

    // Pull all tasks
    let query = json!({
        "query": "query SyncPull($since: NaiveDateTime) {
            syncPull(since: $since) {
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

    let sync_pull = json.get("data").unwrap().get("syncPull").unwrap();
    let tasks = sync_pull.get("tasks").unwrap().as_array().unwrap();
    assert_eq!(tasks.len(), 2);

    // Verify task fields are present
    let task = &tasks[0];
    assert!(task.get("id").is_some());
    assert!(task.get("name").is_some());
    assert!(task.get("description").is_some());
    assert!(task.get("createdAt").is_some());
    assert!(task.get("updatedAt").is_some());
}

#[tokio::test]
async fn test_sync_pull_returns_tasks_modified_since_timestamp() {
    let email = generate_email_from_fn!(test_sync_pull_returns_tasks_modified_since_timestamp);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    // Create a task
    let create_task_query = json!({
        "query": "mutation CreateTask($input: CreateTaskInput!) {
            createTask(input: $input) {
                id
                name
            }
        }",
        "variables": {
            "input": {
                "name": "Old Task",
                "description": "Created before timestamp"
            }
        }
    });
    make_authenticated_graphql_request(&access_token, create_task_query).await;

    // Get current server time to use as "since"
    let pull_query = json!({
        "query": "query SyncPull($since: NaiveDateTime) {
            syncPull(since: $since) {
                serverTime
            }
        }",
        "variables": {
            "since": null
        }
    });
    let (_, json) = make_authenticated_graphql_request(&access_token, pull_query).await;
    let server_time = json
        .get("data")
        .unwrap()
        .get("syncPull")
        .unwrap()
        .get("serverTime")
        .unwrap()
        .as_str()
        .unwrap();

    // Create another task after getting the timestamp
    let create_task_query_2 = json!({
        "query": "mutation CreateTask($input: CreateTaskInput!) {
            createTask(input: $input) {
                id
                name
            }
        }",
        "variables": {
            "input": {
                "name": "New Task",
                "description": "Created after timestamp"
            }
        }
    });
    make_authenticated_graphql_request(&access_token, create_task_query_2).await;

    // Pull tasks since the timestamp - should only get the new task
    let query = json!({
        "query": "query SyncPull($since: NaiveDateTime) {
            syncPull(since: $since) {
                tasks {
                    id
                    name
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
    assert!(json.get("data").is_some(), "Response: {:?}", json);

    let sync_pull = json.get("data").unwrap().get("syncPull").unwrap();
    let tasks = sync_pull.get("tasks").unwrap().as_array().unwrap();
    assert_eq!(tasks.len(), 1);
    assert_eq!(tasks[0].get("name").unwrap(), "New Task");
}

#[tokio::test]
async fn test_sync_pull_includes_soft_deleted_tasks() {
    let email = generate_email_from_fn!(test_sync_pull_includes_soft_deleted_tasks);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    // Create a task
    let create_task_query = json!({
        "query": "mutation CreateTask($input: CreateTaskInput!) {
            createTask(input: $input) {
                id
                name
            }
        }",
        "variables": {
            "input": {
                "name": "Task to delete",
                "description": "This will be soft deleted"
            }
        }
    });
    let (_, create_response) =
        make_authenticated_graphql_request(&access_token, create_task_query).await;
    let task_id = create_response
        .get("data")
        .unwrap()
        .get("createTask")
        .unwrap()
        .get("id")
        .unwrap()
        .as_str()
        .unwrap();

    // Soft delete via syncPush
    let push_query = json!({
        "query": "mutation SyncPush($tasks: [SyncTaskInput!]!) {
            syncPush(tasks: $tasks) {
                tasks {
                    id
                    deletedAt
                }
                serverTime
            }
        }",
        "variables": {
            "tasks": [{
                "id": task_id,
                "name": "Task to delete",
                "description": "This will be soft deleted",
                "createdAt": "2025-01-01T00:00:00",
                "updatedAt": "2025-01-01T00:00:00",
                "deletedAt": "2025-01-01T00:00:00"
            }]
        }
    });
    make_authenticated_graphql_request(&access_token, push_query).await;

    // Pull all tasks - should include the soft-deleted task
    let query = json!({
        "query": "query SyncPull($since: NaiveDateTime) {
            syncPull(since: $since) {
                tasks {
                    id
                    name
                    deletedAt
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

    let sync_pull = json.get("data").unwrap().get("syncPull").unwrap();
    let tasks = sync_pull.get("tasks").unwrap().as_array().unwrap();
    assert_eq!(tasks.len(), 1);

    let task = &tasks[0];
    assert_eq!(task.get("id").unwrap(), task_id);
    assert!(task.get("deletedAt").unwrap().is_string()); // Should have deletedAt set
}

#[tokio::test]
async fn test_sync_pull_only_returns_own_tasks() {
    let email1 = generate_email_from_fn!(test_sync_pull_only_returns_own_tasks);
    let email2 = format!("other_{}", email1);
    let password = "password123";

    // Register two users
    register_user(&email1, password).await;
    register_user(&email2, password).await;

    let access_token1 = get_access_token_for_user(&email1, &password).await;
    let access_token2 = get_access_token_for_user(&email2, &password).await;

    // User 1 creates a task
    let create_task_query = json!({
        "query": "mutation CreateTask($input: CreateTaskInput!) {
            createTask(input: $input) {
                id
                name
            }
        }",
        "variables": {
            "input": {
                "name": "User 1 Task",
                "description": "Belongs to user 1"
            }
        }
    });
    make_authenticated_graphql_request(&access_token1, create_task_query).await;

    // User 2 creates a task
    let create_task_query_2 = json!({
        "query": "mutation CreateTask($input: CreateTaskInput!) {
            createTask(input: $input) {
                id
                name
            }
        }",
        "variables": {
            "input": {
                "name": "User 2 Task",
                "description": "Belongs to user 2"
            }
        }
    });
    make_authenticated_graphql_request(&access_token2, create_task_query_2).await;

    // User 1 pulls - should only see their own task
    let query = json!({
        "query": "query SyncPull($since: NaiveDateTime) {
            syncPull(since: $since) {
                tasks {
                    id
                    name
                }
                serverTime
            }
        }",
        "variables": {
            "since": null
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token1, query).await;
    assert_eq!(status, StatusCode::OK);

    let sync_pull = json.get("data").unwrap().get("syncPull").unwrap();
    let tasks = sync_pull.get("tasks").unwrap().as_array().unwrap();
    assert_eq!(tasks.len(), 1);
    assert_eq!(tasks[0].get("name").unwrap(), "User 1 Task");
}

#[tokio::test]
async fn test_sync_pull_requires_authentication() {
    let router = router::router().await;

    let query = json!({
        "query": "query SyncPull($since: NaiveDateTime) {
            syncPull(since: $since) {
                tasks {
                    id
                }
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

#[tokio::test]
async fn test_sync_pull_with_invalid_auth_token() {
    let router = router::router().await;

    let query = json!({
        "query": "query SyncPull($since: NaiveDateTime) {
            syncPull(since: $since) {
                tasks {
                    id
                }
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
                .header(http::header::AUTHORIZATION, "Bearer invalid-token")
                .body(Body::from(query.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

// ============================================================================
// syncPush Mutation Tests
// ============================================================================

#[tokio::test]
async fn test_sync_push_creates_new_task() {
    let email = generate_email_from_fn!(test_sync_push_creates_new_task);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let new_task_id = uuid::Uuid::new_v4().to_string();

    let query = json!({
        "query": "mutation SyncPush($tasks: [SyncTaskInput!]!) {
            syncPush(tasks: $tasks) {
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
                }
                serverTime
            }
        }",
        "variables": {
            "tasks": [{
                "id": new_task_id,
                "name": "New Synced Task",
                "description": "Created via sync push",
                "createdAt": "2025-01-01T10:00:00",
                "updatedAt": "2025-01-01T10:00:00"
            }]
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);
    assert!(json.get("data").is_some(), "Response: {:?}", json);

    let sync_push = json.get("data").unwrap().get("syncPush").unwrap();
    let tasks = sync_push.get("tasks").unwrap().as_array().unwrap();
    assert_eq!(tasks.len(), 1);

    let task = &tasks[0];
    assert_eq!(task.get("id").unwrap(), &new_task_id);
    assert_eq!(task.get("name").unwrap(), "New Synced Task");
    assert_eq!(task.get("description").unwrap(), "Created via sync push");
    assert!(sync_push.get("serverTime").is_some());
}

#[tokio::test]
async fn test_sync_push_updates_existing_task() {
    let email = generate_email_from_fn!(test_sync_push_updates_existing_task);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    // Create a task first
    let create_task_query = json!({
        "query": "mutation CreateTask($input: CreateTaskInput!) {
            createTask(input: $input) {
                id
                name
                createdAt
            }
        }",
        "variables": {
            "input": {
                "name": "Original Name",
                "description": "Original Description"
            }
        }
    });
    let (_, create_response) =
        make_authenticated_graphql_request(&access_token, create_task_query).await;
    let task = create_response
        .get("data")
        .unwrap()
        .get("createTask")
        .unwrap();
    let task_id = task.get("id").unwrap().as_str().unwrap();
    let created_at = task.get("createdAt").unwrap().as_str().unwrap();

    // Update via syncPush
    let query = json!({
        "query": "mutation SyncPush($tasks: [SyncTaskInput!]!) {
            syncPush(tasks: $tasks) {
                tasks {
                    id
                    name
                    description
                    updatedAt
                }
                serverTime
            }
        }",
        "variables": {
            "tasks": [{
                "id": task_id,
                "name": "Updated Name",
                "description": "Updated Description",
                "createdAt": created_at,
                "updatedAt": "2030-01-01T12:00:00"
            }]
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);
    assert!(json.get("data").is_some(), "Response: {:?}", json);

    let sync_push = json.get("data").unwrap().get("syncPush").unwrap();
    let tasks = sync_push.get("tasks").unwrap().as_array().unwrap();
    assert_eq!(tasks.len(), 1);

    let updated_task = &tasks[0];
    assert_eq!(updated_task.get("id").unwrap(), task_id);
    assert_eq!(updated_task.get("name").unwrap(), "Updated Name");
    assert_eq!(
        updated_task.get("description").unwrap(),
        "Updated Description"
    );
}

#[tokio::test]
async fn test_sync_push_soft_deletes_task() {
    let email = generate_email_from_fn!(test_sync_push_soft_deletes_task);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    // Create a task first
    let create_task_query = json!({
        "query": "mutation CreateTask($input: CreateTaskInput!) {
            createTask(input: $input) {
                id
                name
                createdAt
            }
        }",
        "variables": {
            "input": {
                "name": "Task to Delete",
                "description": "Will be soft deleted"
            }
        }
    });
    let (_, create_response) =
        make_authenticated_graphql_request(&access_token, create_task_query).await;
    let task = create_response
        .get("data")
        .unwrap()
        .get("createTask")
        .unwrap();
    let task_id = task.get("id").unwrap().as_str().unwrap();
    let created_at = task.get("createdAt").unwrap().as_str().unwrap();

    // Soft delete via syncPush
    let query = json!({
        "query": "mutation SyncPush($tasks: [SyncTaskInput!]!) {
            syncPush(tasks: $tasks) {
                tasks {
                    id
                    name
                    deletedAt
                }
                serverTime
            }
        }",
        "variables": {
            "tasks": [{
                "id": task_id,
                "name": "Task to Delete",
                "description": "Will be soft deleted",
                "createdAt": created_at,
                "updatedAt": "2030-01-01T12:00:00",
                "deletedAt": "2030-01-01T12:00:00"
            }]
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);
    assert!(json.get("data").is_some(), "Response: {:?}", json);

    let sync_push = json.get("data").unwrap().get("syncPush").unwrap();
    let tasks = sync_push.get("tasks").unwrap().as_array().unwrap();
    assert_eq!(tasks.len(), 1);

    let deleted_task = &tasks[0];
    assert_eq!(deleted_task.get("id").unwrap(), task_id);
    assert!(deleted_task.get("deletedAt").unwrap().is_string());
}

#[tokio::test]
async fn test_sync_push_multiple_tasks() {
    let email = generate_email_from_fn!(test_sync_push_multiple_tasks);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let task_id_1 = uuid::Uuid::new_v4().to_string();
    let task_id_2 = uuid::Uuid::new_v4().to_string();
    let task_id_3 = uuid::Uuid::new_v4().to_string();

    let query = json!({
        "query": "mutation SyncPush($tasks: [SyncTaskInput!]!) {
            syncPush(tasks: $tasks) {
                tasks {
                    id
                    name
                }
                serverTime
            }
        }",
        "variables": {
            "tasks": [
                {
                    "id": task_id_1,
                    "name": "Task 1",
                    "description": "First task",
                    "createdAt": "2025-01-01T10:00:00",
                    "updatedAt": "2025-01-01T10:00:00"
                },
                {
                    "id": task_id_2,
                    "name": "Task 2",
                    "description": "Second task",
                    "createdAt": "2025-01-01T10:00:00",
                    "updatedAt": "2025-01-01T10:00:00"
                },
                {
                    "id": task_id_3,
                    "name": "Task 3",
                    "description": "Third task",
                    "createdAt": "2025-01-01T10:00:00",
                    "updatedAt": "2025-01-01T10:00:00"
                }
            ]
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);
    assert!(json.get("data").is_some(), "Response: {:?}", json);

    let sync_push = json.get("data").unwrap().get("syncPush").unwrap();
    let tasks = sync_push.get("tasks").unwrap().as_array().unwrap();
    assert_eq!(tasks.len(), 3);
}

#[tokio::test]
async fn test_sync_push_with_optional_fields() {
    let email = generate_email_from_fn!(test_sync_push_with_optional_fields);
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
                    hiddenUntil
                    dueBy
                    minDailyFrequency
                }
                serverTime
            }
        }",
        "variables": {
            "tasks": [{
                "id": task_id,
                "name": "Task with optional fields",
                "description": "Has all optional fields",
                "createdAt": "2025-01-01T10:00:00",
                "updatedAt": "2025-01-01T10:00:00",
                "hiddenUntil": "2030-06-01T00:00:00",
                "dueBy": "2030-12-31T23:59:59",
                "minDailyFrequency": null
            }]
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);
    assert!(json.get("data").is_some(), "Response: {:?}", json);

    let sync_push = json.get("data").unwrap().get("syncPush").unwrap();
    let tasks = sync_push.get("tasks").unwrap().as_array().unwrap();
    assert_eq!(tasks.len(), 1);

    let task = &tasks[0];
    assert_eq!(task.get("hiddenUntil").unwrap(), "2030-06-01T00:00:00");
    assert_eq!(task.get("dueBy").unwrap(), "2030-12-31T23:59:59");
}

#[tokio::test]
async fn test_sync_push_requires_authentication() {
    let router = router::router().await;

    let task_id = uuid::Uuid::new_v4().to_string();

    let query = json!({
        "query": "mutation SyncPush($tasks: [SyncTaskInput!]!) {
            syncPush(tasks: $tasks) {
                tasks {
                    id
                }
                serverTime
            }
        }",
        "variables": {
            "tasks": [{
                "id": task_id,
                "name": "Task",
                "description": "Description",
                "createdAt": "2025-01-01T10:00:00",
                "updatedAt": "2025-01-01T10:00:00"
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
async fn test_sync_push_with_invalid_auth_token() {
    let router = router::router().await;

    let task_id = uuid::Uuid::new_v4().to_string();

    let query = json!({
        "query": "mutation SyncPush($tasks: [SyncTaskInput!]!) {
            syncPush(tasks: $tasks) {
                tasks {
                    id
                }
                serverTime
            }
        }",
        "variables": {
            "tasks": [{
                "id": task_id,
                "name": "Task",
                "description": "Description",
                "createdAt": "2025-01-01T10:00:00",
                "updatedAt": "2025-01-01T10:00:00"
            }]
        }
    });

    let response = router
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/graphql")
                .header(http::header::CONTENT_TYPE, "application/json")
                .header(http::header::AUTHORIZATION, "Bearer invalid-token")
                .body(Body::from(query.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn test_sync_push_validates_name_too_long() {
    let email = generate_email_from_fn!(test_sync_push_validates_name_too_long);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let task_id = uuid::Uuid::new_v4().to_string();
    let long_name = "a".repeat(101);

    let query = json!({
        "query": "mutation SyncPush($tasks: [SyncTaskInput!]!) {
            syncPush(tasks: $tasks) {
                tasks {
                    id
                }
                serverTime
            }
        }",
        "variables": {
            "tasks": [{
                "id": task_id,
                "name": long_name,
                "description": "Description",
                "createdAt": "2025-01-01T10:00:00",
                "updatedAt": "2025-01-01T10:00:00"
            }]
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);
    assert!(json.get("errors").is_some());

    let errors = json.get("errors").unwrap().as_array().unwrap();
    assert!(!errors.is_empty());

    let error = errors.first().unwrap();
    let extensions = error.get("extensions").unwrap();
    assert_eq!(
        extensions.get("code").unwrap(),
        &Value::String("BAD_USER_INPUT".to_string())
    );
}

#[tokio::test]
async fn test_sync_push_validates_name_empty() {
    let email = generate_email_from_fn!(test_sync_push_validates_name_empty);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let task_id = uuid::Uuid::new_v4().to_string();

    let query = json!({
        "query": "mutation SyncPush($tasks: [SyncTaskInput!]!) {
            syncPush(tasks: $tasks) {
                tasks {
                    id
                }
                serverTime
            }
        }",
        "variables": {
            "tasks": [{
                "id": task_id,
                "name": "",
                "description": "Description",
                "createdAt": "2025-01-01T10:00:00",
                "updatedAt": "2025-01-01T10:00:00"
            }]
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);
    assert!(json.get("errors").is_some());

    let errors = json.get("errors").unwrap().as_array().unwrap();
    assert!(!errors.is_empty());

    let error = errors.first().unwrap();
    let extensions = error.get("extensions").unwrap();
    assert_eq!(
        extensions.get("code").unwrap(),
        &Value::String("BAD_USER_INPUT".to_string())
    );
}

#[tokio::test]
async fn test_sync_push_validates_description_too_long() {
    let email = generate_email_from_fn!(test_sync_push_validates_description_too_long);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let task_id = uuid::Uuid::new_v4().to_string();
    let long_description = "a".repeat(10001);

    let query = json!({
        "query": "mutation SyncPush($tasks: [SyncTaskInput!]!) {
            syncPush(tasks: $tasks) {
                tasks {
                    id
                }
                serverTime
            }
        }",
        "variables": {
            "tasks": [{
                "id": task_id,
                "name": "Task",
                "description": long_description,
                "createdAt": "2025-01-01T10:00:00",
                "updatedAt": "2025-01-01T10:00:00"
            }]
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);
    assert!(json.get("errors").is_some());

    let errors = json.get("errors").unwrap().as_array().unwrap();
    assert!(!errors.is_empty());

    let error = errors.first().unwrap();
    let extensions = error.get("extensions").unwrap();
    assert_eq!(
        extensions.get("code").unwrap(),
        &Value::String("BAD_USER_INPUT".to_string())
    );
}

#[tokio::test]
async fn test_sync_push_cannot_modify_other_users_tasks() {
    let email1 = generate_email_from_fn!(test_sync_push_cannot_modify_other_users_tasks);
    let email2 = format!("other_{}", email1);
    let password = "password123";

    // Register two users
    register_user(&email1, password).await;
    register_user(&email2, password).await;

    let access_token1 = get_access_token_for_user(&email1, &password).await;
    let access_token2 = get_access_token_for_user(&email2, &password).await;

    // User 1 creates a task
    let create_task_query = json!({
        "query": "mutation CreateTask($input: CreateTaskInput!) {
            createTask(input: $input) {
                id
                name
                createdAt
            }
        }",
        "variables": {
            "input": {
                "name": "User 1 Task",
                "description": "Belongs to user 1"
            }
        }
    });
    let (_, create_response) =
        make_authenticated_graphql_request(&access_token1, create_task_query).await;
    let task = create_response
        .get("data")
        .unwrap()
        .get("createTask")
        .unwrap();
    let task_id = task.get("id").unwrap().as_str().unwrap();
    let created_at = task.get("createdAt").unwrap().as_str().unwrap();

    // User 2 tries to modify User 1's task via syncPush
    let query = json!({
        "query": "mutation SyncPush($tasks: [SyncTaskInput!]!) {
            syncPush(tasks: $tasks) {
                tasks {
                    id
                    name
                }
                serverTime
            }
        }",
        "variables": {
            "tasks": [{
                "id": task_id,
                "name": "Hijacked Task",
                "description": "Trying to modify another user's task",
                "createdAt": created_at,
                "updatedAt": "2030-01-01T12:00:00"
            }]
        }
    });

    let (status, _) = make_authenticated_graphql_request(&access_token2, query).await;
    assert_eq!(status, StatusCode::OK);

    // The task should either be rejected or a new task created for user 2 (not modify user 1's task)
    // Verify user 1's task is unchanged
    let pull_query = json!({
        "query": "query SyncPull($since: NaiveDateTime) {
            syncPull(since: $since) {
                tasks {
                    id
                    name
                }
                serverTime
            }
        }",
        "variables": {
            "since": null
        }
    });

    let (_, user1_pull) = make_authenticated_graphql_request(&access_token1, pull_query).await;
    let user1_tasks = user1_pull
        .get("data")
        .unwrap()
        .get("syncPull")
        .unwrap()
        .get("tasks")
        .unwrap()
        .as_array()
        .unwrap();

    assert_eq!(user1_tasks.len(), 1);
    assert_eq!(user1_tasks[0].get("name").unwrap(), "User 1 Task"); // Should still be original name
}

#[tokio::test]
async fn test_sync_push_empty_array() {
    let email = generate_email_from_fn!(test_sync_push_empty_array);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let query = json!({
        "query": "mutation SyncPush($tasks: [SyncTaskInput!]!) {
            syncPush(tasks: $tasks) {
                tasks {
                    id
                }
                serverTime
            }
        }",
        "variables": {
            "tasks": []
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);
    assert!(json.get("data").is_some(), "Response: {:?}", json);

    let sync_push = json.get("data").unwrap().get("syncPush").unwrap();
    let tasks = sync_push.get("tasks").unwrap().as_array().unwrap();
    assert_eq!(tasks.len(), 0);
    assert!(sync_push.get("serverTime").is_some());
}

#[tokio::test]
async fn test_sync_push_invalid_uuid() {
    let email = generate_email_from_fn!(test_sync_push_invalid_uuid);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let query = json!({
        "query": "mutation SyncPush($tasks: [SyncTaskInput!]!) {
            syncPush(tasks: $tasks) {
                tasks {
                    id
                }
                serverTime
            }
        }",
        "variables": {
            "tasks": [{
                "id": "not-a-valid-uuid",
                "name": "Task",
                "description": "Description",
                "createdAt": "2025-01-01T10:00:00",
                "updatedAt": "2025-01-01T10:00:00"
            }]
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);
    assert!(json.get("errors").is_some());

    let errors = json.get("errors").unwrap().as_array().unwrap();
    assert!(!errors.is_empty());
}

#[tokio::test]
async fn test_sync_push_with_min_daily_frequency() {
    let email = generate_email_from_fn!(test_sync_push_with_min_daily_frequency);
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
                    minDailyFrequency
                }
                serverTime
            }
        }",
        "variables": {
            "tasks": [{
                "id": task_id,
                "name": "Recurring Task",
                "description": "Has min daily frequency",
                "createdAt": "2025-01-01T10:00:00",
                "updatedAt": "2025-01-01T10:00:00",
                "minDailyFrequency": 3.5
            }]
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);
    assert!(json.get("data").is_some(), "Response: {:?}", json);

    let sync_push = json.get("data").unwrap().get("syncPush").unwrap();
    let tasks = sync_push.get("tasks").unwrap().as_array().unwrap();
    assert_eq!(tasks.len(), 1);
    assert_eq!(tasks[0].get("minDailyFrequency").unwrap(), 3.5);
}

#[tokio::test]
async fn test_sync_push_validates_min_daily_frequency_too_large() {
    let email = generate_email_from_fn!(test_sync_push_validates_min_daily_frequency_too_large);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let task_id = uuid::Uuid::new_v4().to_string();

    let query = json!({
        "query": "mutation SyncPush($tasks: [SyncTaskInput!]!) {
            syncPush(tasks: $tasks) {
                tasks {
                    id
                }
                serverTime
            }
        }",
        "variables": {
            "tasks": [{
                "id": task_id,
                "name": "Task",
                "description": "Description",
                "createdAt": "2025-01-01T10:00:00",
                "updatedAt": "2025-01-01T10:00:00",
                "minDailyFrequency": 101.0
            }]
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);
    assert!(json.get("errors").is_some());

    let errors = json.get("errors").unwrap().as_array().unwrap();
    assert!(!errors.is_empty());

    let error = errors.first().unwrap();
    let extensions = error.get("extensions").unwrap();
    assert_eq!(
        extensions.get("code").unwrap(),
        &Value::String("BAD_USER_INPUT".to_string())
    );
}

#[tokio::test]
async fn test_sync_push_validates_min_daily_frequency_negative() {
    let email = generate_email_from_fn!(test_sync_push_validates_min_daily_frequency_negative);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let task_id = uuid::Uuid::new_v4().to_string();

    let query = json!({
        "query": "mutation SyncPush($tasks: [SyncTaskInput!]!) {
            syncPush(tasks: $tasks) {
                tasks {
                    id
                }
                serverTime
            }
        }",
        "variables": {
            "tasks": [{
                "id": task_id,
                "name": "Task",
                "description": "Description",
                "createdAt": "2025-01-01T10:00:00",
                "updatedAt": "2025-01-01T10:00:00",
                "minDailyFrequency": -1.0
            }]
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);
    assert!(json.get("errors").is_some());

    let errors = json.get("errors").unwrap().as_array().unwrap();
    assert!(!errors.is_empty());

    let error = errors.first().unwrap();
    let extensions = error.get("extensions").unwrap();
    assert_eq!(
        extensions.get("code").unwrap(),
        &Value::String("BAD_USER_INPUT".to_string())
    );
}

// ============================================================================
// Sync Round-trip Tests
// ============================================================================

#[tokio::test]
async fn test_sync_roundtrip_push_then_pull() {
    let email = generate_email_from_fn!(test_sync_roundtrip_push_then_pull);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let task_id = uuid::Uuid::new_v4().to_string();

    // Push a new task
    let push_query = json!({
        "query": "mutation SyncPush($tasks: [SyncTaskInput!]!) {
            syncPush(tasks: $tasks) {
                tasks {
                    id
                    name
                    description
                }
                serverTime
            }
        }",
        "variables": {
            "tasks": [{
                "id": task_id,
                "name": "Roundtrip Task",
                "description": "Test roundtrip",
                "createdAt": "2025-01-01T10:00:00",
                "updatedAt": "2025-01-01T10:00:00"
            }]
        }
    });

    let (status, _) = make_authenticated_graphql_request(&access_token, push_query).await;
    assert_eq!(status, StatusCode::OK);

    // Pull and verify
    let pull_query = json!({
        "query": "query SyncPull($since: NaiveDateTime) {
            syncPull(since: $since) {
                tasks {
                    id
                    name
                    description
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

    let sync_pull = json.get("data").unwrap().get("syncPull").unwrap();
    let tasks = sync_pull.get("tasks").unwrap().as_array().unwrap();
    assert_eq!(tasks.len(), 1);
    assert_eq!(tasks[0].get("id").unwrap(), &task_id);
    assert_eq!(tasks[0].get("name").unwrap(), "Roundtrip Task");
    assert_eq!(tasks[0].get("description").unwrap(), "Test roundtrip");
}

#[tokio::test]
async fn test_sync_incremental_pull_after_push() {
    let email = generate_email_from_fn!(test_sync_incremental_pull_after_push);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let task_id_1 = uuid::Uuid::new_v4().to_string();

    // Push first task
    let push_query_1 = json!({
        "query": "mutation SyncPush($tasks: [SyncTaskInput!]!) {
            syncPush(tasks: $tasks) {
                tasks { id }
                serverTime
            }
        }",
        "variables": {
            "tasks": [{
                "id": task_id_1,
                "name": "First Task",
                "description": "Created first",
                "createdAt": "2025-01-01T10:00:00",
                "updatedAt": "2025-01-01T10:00:00"
            }]
        }
    });
    let (_, push_response) = make_authenticated_graphql_request(&access_token, push_query_1).await;
    let server_time = push_response
        .get("data")
        .unwrap()
        .get("syncPush")
        .unwrap()
        .get("serverTime")
        .unwrap()
        .as_str()
        .unwrap();

    // Push second task
    let task_id_2 = uuid::Uuid::new_v4().to_string();
    let push_query_2 = json!({
        "query": "mutation SyncPush($tasks: [SyncTaskInput!]!) {
            syncPush(tasks: $tasks) {
                tasks { id }
                serverTime
            }
        }",
        "variables": {
            "tasks": [{
                "id": task_id_2,
                "name": "Second Task",
                "description": "Created second",
                "createdAt": "2025-01-02T10:00:00",
                "updatedAt": "2025-01-02T10:00:00"
            }]
        }
    });
    make_authenticated_graphql_request(&access_token, push_query_2).await;

    // Pull since first push - should only get the second task
    let pull_query = json!({
        "query": "query SyncPull($since: NaiveDateTime) {
            syncPull(since: $since) {
                tasks {
                    id
                    name
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

    let sync_pull = json.get("data").unwrap().get("syncPull").unwrap();
    let tasks = sync_pull.get("tasks").unwrap().as_array().unwrap();
    assert_eq!(tasks.len(), 1);
    assert_eq!(tasks[0].get("name").unwrap(), "Second Task");
}

// ============================================================================
// Anonymous Account Merge Tests
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

#[tokio::test]
async fn test_sync_push_can_transfer_task_from_anonymous_to_registered_user() {
    // Create an anonymous user
    let device_id = uuid::Uuid::new_v4().to_string();
    let (status, anon_json) = anonymous_auth(&device_id).await;
    assert_eq!(status, StatusCode::OK);

    let anon_access_token = anon_json["accessToken"].as_str().unwrap();

    // Anonymous user creates a task
    let task_id = uuid::Uuid::new_v4().to_string();
    let create_task_query = json!({
        "query": "mutation SyncPush($tasks: [SyncTaskInput!]!) {
            syncPush(tasks: $tasks) {
                tasks {
                    id
                    name
                }
                serverTime
            }
        }",
        "variables": {
            "tasks": [{
                "id": task_id,
                "name": "Anonymous Task",
                "description": "Created by anonymous user",
                "createdAt": "2025-01-01T10:00:00",
                "updatedAt": "2025-01-01T10:00:00"
            }]
        }
    });

    let (status, _) = make_authenticated_graphql_request(anon_access_token, create_task_query).await;
    assert_eq!(status, StatusCode::OK);

    // Verify anonymous user can see the task
    let pull_query = json!({
        "query": "query SyncPull($since: NaiveDateTime) {
            syncPull(since: $since) {
                tasks {
                    id
                    name
                }
                serverTime
            }
        }",
        "variables": {
            "since": null
        }
    });

    let (status, json) = make_authenticated_graphql_request(anon_access_token, pull_query.clone()).await;
    assert_eq!(status, StatusCode::OK);
    let tasks = json.get("data").unwrap().get("syncPull").unwrap().get("tasks").unwrap().as_array().unwrap();
    assert_eq!(tasks.len(), 1);
    assert_eq!(tasks[0].get("name").unwrap(), "Anonymous Task");

    // Now register a new user
    let email = generate_email_from_fn!(test_sync_push_can_transfer_task_from_anonymous_to_registered_user);
    let password = "password123";
    register_user(&email, password).await;
    let registered_access_token = get_access_token_for_user(&email, &password).await;

    // Registered user pushes the same task ID with the same name (simulating merge from client)
    let push_query = json!({
        "query": "mutation SyncPush($tasks: [SyncTaskInput!]!) {
            syncPush(tasks: $tasks) {
                tasks {
                    id
                    name
                }
                serverTime
            }
        }",
        "variables": {
            "tasks": [{
                "id": task_id,
                "name": "Anonymous Task",
                "description": "Created by anonymous user",
                "createdAt": "2025-01-01T10:00:00",
                "updatedAt": "2025-01-01T11:00:00"
            }]
        }
    });

    let (status, push_json) = make_authenticated_graphql_request(&registered_access_token, push_query).await;
    assert_eq!(status, StatusCode::OK);

    // The push should succeed and return the task (ownership transferred)
    let pushed_tasks = push_json.get("data").unwrap().get("syncPush").unwrap().get("tasks").unwrap().as_array().unwrap();
    assert_eq!(pushed_tasks.len(), 1);
    assert_eq!(pushed_tasks[0].get("id").unwrap(), &task_id);
    assert_eq!(pushed_tasks[0].get("name").unwrap(), "Anonymous Task");

    // Registered user should now see the task when pulling
    let (status, json) = make_authenticated_graphql_request(&registered_access_token, pull_query.clone()).await;
    assert_eq!(status, StatusCode::OK);

    let sync_pull = json.get("data").unwrap().get("syncPull").unwrap();
    let tasks = sync_pull.get("tasks").unwrap().as_array().unwrap();
    assert_eq!(tasks.len(), 1);
    assert_eq!(tasks[0].get("id").unwrap(), &task_id);
    assert_eq!(tasks[0].get("name").unwrap(), "Anonymous Task");
}

#[tokio::test]
async fn test_sync_push_registered_user_cannot_hijack_other_registered_users_task() {
    // This is a safety test to ensure that only anonymous tasks can be transferred,
    // not tasks from other registered users.

    // Create first registered user and their task
    let email1 = generate_email_from_fn!(test_sync_push_registered_user_cannot_hijack_other_registered_users_task);
    let email2 = format!("other_{}", email1);
    let password = "password123";

    register_user(&email1, password).await;
    register_user(&email2, password).await;

    let access_token1 = get_access_token_for_user(&email1, &password).await;
    let access_token2 = get_access_token_for_user(&email2, &password).await;

    // User 1 creates a task
    let task_id = uuid::Uuid::new_v4().to_string();
    let create_task_query = json!({
        "query": "mutation SyncPush($tasks: [SyncTaskInput!]!) {
            syncPush(tasks: $tasks) {
                tasks {
                    id
                    name
                }
                serverTime
            }
        }",
        "variables": {
            "tasks": [{
                "id": task_id,
                "name": "User 1 Task",
                "description": "Belongs to user 1",
                "createdAt": "2025-01-01T10:00:00",
                "updatedAt": "2025-01-01T10:00:00"
            }]
        }
    });

    let (status, _) = make_authenticated_graphql_request(&access_token1, create_task_query).await;
    assert_eq!(status, StatusCode::OK);

    // User 2 tries to take over user 1's task
    let hijack_query = json!({
        "query": "mutation SyncPush($tasks: [SyncTaskInput!]!) {
            syncPush(tasks: $tasks) {
                tasks {
                    id
                    name
                }
                serverTime
            }
        }",
        "variables": {
            "tasks": [{
                "id": task_id,
                "name": "Hijacked Task",
                "description": "Trying to steal",
                "createdAt": "2025-01-01T10:00:00",
                "updatedAt": "2025-01-02T10:00:00"
            }]
        }
    });

    let (status, _) = make_authenticated_graphql_request(&access_token2, hijack_query).await;
    assert_eq!(status, StatusCode::OK);

    // User 1's task should still have the original name
    let pull_query = json!({
        "query": "query SyncPull($since: NaiveDateTime) {
            syncPull(since: $since) {
                tasks {
                    id
                    name
                }
                serverTime
            }
        }",
        "variables": {
            "since": null
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token1, pull_query).await;
    assert_eq!(status, StatusCode::OK);

    let tasks = json.get("data").unwrap().get("syncPull").unwrap().get("tasks").unwrap().as_array().unwrap();
    assert_eq!(tasks.len(), 1);
    assert_eq!(tasks[0].get("name").unwrap(), "User 1 Task"); // Should still be original name
}
