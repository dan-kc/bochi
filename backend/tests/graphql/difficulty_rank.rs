use crate::common::{get_access_token_for_user, make_authenticated_graphql_request, register_user};
use crate::generate_email_from_fn;
use axum::http::StatusCode;
use serde_json::json;

// ============================================================================
// syncPush with difficulty_rank Tests
// ============================================================================

#[tokio::test]
async fn test_sync_push_with_difficulty_rank() {
    let email = generate_email_from_fn!(test_sync_push_with_difficulty_rank);
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
                    difficultyRank
                }
                serverTime
            }
        }",
        "variables": {
            "tasks": [{
                "id": task_id,
                "name": "Hard Task",
                "description": "A difficult task",
                "createdAt": "2025-01-01T10:00:00",
                "updatedAt": "2025-01-01T10:00:00",
                "difficultyRank": "a0"
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
    assert_eq!(task.get("id").unwrap(), &task_id);
    assert_eq!(task.get("difficultyRank").unwrap(), "a0");
}

#[tokio::test]
async fn test_sync_push_without_difficulty_rank() {
    let email = generate_email_from_fn!(test_sync_push_without_difficulty_rank);
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
                    difficultyRank
                }
                serverTime
            }
        }",
        "variables": {
            "tasks": [{
                "id": task_id,
                "name": "Unranked Task",
                "description": "Task without difficulty rank",
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
    assert_eq!(task.get("id").unwrap(), &task_id);
    assert!(task.get("difficultyRank").unwrap().is_null());
}

#[tokio::test]
async fn test_sync_push_update_difficulty_rank() {
    let email = generate_email_from_fn!(test_sync_push_update_difficulty_rank);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let task_id = uuid::Uuid::new_v4().to_string();

    // Create task without difficulty rank
    let create_query = json!({
        "query": "mutation SyncPush($tasks: [SyncTaskInput!]!) {
            syncPush(tasks: $tasks) {
                tasks {
                    id
                    difficultyRank
                }
                serverTime
            }
        }",
        "variables": {
            "tasks": [{
                "id": task_id,
                "name": "Task to Rank",
                "description": "Will be ranked later",
                "createdAt": "2025-01-01T10:00:00",
                "updatedAt": "2025-01-01T10:00:00"
            }]
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, create_query).await;
    assert_eq!(status, StatusCode::OK);
    let task = &json["data"]["syncPush"]["tasks"][0];
    assert!(task["difficultyRank"].is_null());

    // Update with difficulty rank
    let update_query = json!({
        "query": "mutation SyncPush($tasks: [SyncTaskInput!]!) {
            syncPush(tasks: $tasks) {
                tasks {
                    id
                    difficultyRank
                }
                serverTime
            }
        }",
        "variables": {
            "tasks": [{
                "id": task_id,
                "name": "Task to Rank",
                "description": "Will be ranked later",
                "createdAt": "2025-01-01T10:00:00",
                "updatedAt": "2025-01-02T10:00:00",
                "difficultyRank": "b5"
            }]
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, update_query).await;
    assert_eq!(status, StatusCode::OK);

    let task = &json["data"]["syncPush"]["tasks"][0];
    assert_eq!(task["difficultyRank"], "b5");
}

#[tokio::test]
async fn test_sync_push_clear_difficulty_rank() {
    let email = generate_email_from_fn!(test_sync_push_clear_difficulty_rank);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let task_id = uuid::Uuid::new_v4().to_string();

    // Create task with difficulty rank
    let create_query = json!({
        "query": "mutation SyncPush($tasks: [SyncTaskInput!]!) {
            syncPush(tasks: $tasks) {
                tasks {
                    id
                    difficultyRank
                }
                serverTime
            }
        }",
        "variables": {
            "tasks": [{
                "id": task_id,
                "name": "Ranked Task",
                "description": "Has a rank",
                "createdAt": "2025-01-01T10:00:00",
                "updatedAt": "2025-01-01T10:00:00",
                "difficultyRank": "c3"
            }]
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, create_query).await;
    assert_eq!(status, StatusCode::OK);
    let task = &json["data"]["syncPush"]["tasks"][0];
    assert_eq!(task["difficultyRank"], "c3");

    // Clear difficulty rank by setting to null
    let clear_query = json!({
        "query": "mutation SyncPush($tasks: [SyncTaskInput!]!) {
            syncPush(tasks: $tasks) {
                tasks {
                    id
                    difficultyRank
                }
                serverTime
            }
        }",
        "variables": {
            "tasks": [{
                "id": task_id,
                "name": "Ranked Task",
                "description": "Has a rank",
                "createdAt": "2025-01-01T10:00:00",
                "updatedAt": "2025-01-02T10:00:00",
                "difficultyRank": null
            }]
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, clear_query).await;
    assert_eq!(status, StatusCode::OK);

    let task = &json["data"]["syncPush"]["tasks"][0];
    assert!(task["difficultyRank"].is_null());
}

// ============================================================================
// syncPull with difficulty_rank Tests
// ============================================================================

#[tokio::test]
async fn test_sync_pull_includes_difficulty_rank() {
    let email = generate_email_from_fn!(test_sync_pull_includes_difficulty_rank);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let task_id = uuid::Uuid::new_v4().to_string();

    // Create task with difficulty rank
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
                "name": "Ranked Task",
                "description": "For pull test",
                "createdAt": "2025-01-01T10:00:00",
                "updatedAt": "2025-01-01T10:00:00",
                "difficultyRank": "d7"
            }]
        }
    });

    make_authenticated_graphql_request(&access_token, push_query).await;

    // Pull and verify difficulty_rank is included
    let pull_query = json!({
        "query": "query SyncPull($since: NaiveDateTime) {
            syncPull(since: $since) {
                tasks {
                    id
                    name
                    difficultyRank
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

    let task = &tasks[0];
    assert_eq!(task.get("id").unwrap(), &task_id);
    assert_eq!(task.get("difficultyRank").unwrap(), "d7");
}

#[tokio::test]
async fn test_sync_pull_includes_null_difficulty_rank() {
    let email = generate_email_from_fn!(test_sync_pull_includes_null_difficulty_rank);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let task_id = uuid::Uuid::new_v4().to_string();

    // Create task without difficulty rank
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
                "name": "Unranked Task",
                "description": "No difficulty rank",
                "createdAt": "2025-01-01T10:00:00",
                "updatedAt": "2025-01-01T10:00:00"
            }]
        }
    });

    make_authenticated_graphql_request(&access_token, push_query).await;

    // Pull and verify difficulty_rank is null
    let pull_query = json!({
        "query": "query SyncPull($since: NaiveDateTime) {
            syncPull(since: $since) {
                tasks {
                    id
                    name
                    difficultyRank
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

    let task = &tasks[0];
    assert_eq!(task.get("id").unwrap(), &task_id);
    assert!(task.get("difficultyRank").unwrap().is_null());
}

// ============================================================================
// createTask with difficulty_rank Tests
// ============================================================================

#[tokio::test]
async fn test_create_task_with_difficulty_rank() {
    let email = generate_email_from_fn!(test_create_task_with_difficulty_rank);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let query = json!({
        "query": "mutation CreateTask($input: CreateTaskInput!) {
            createTask(input: $input) {
                id
                name
                difficultyRank
            }
        }",
        "variables": {
            "input": {
                "name": "New Ranked Task",
                "description": "Created with difficulty",
                "difficultyRank": "e9"
            }
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);
    assert!(json.get("data").is_some(), "Response: {:?}", json);

    let task = json.get("data").unwrap().get("createTask").unwrap();
    assert!(task.get("id").is_some());
    assert_eq!(task.get("name").unwrap(), "New Ranked Task");
    assert_eq!(task.get("difficultyRank").unwrap(), "e9");
}

#[tokio::test]
async fn test_create_task_without_difficulty_rank() {
    let email = generate_email_from_fn!(test_create_task_without_difficulty_rank);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let query = json!({
        "query": "mutation CreateTask($input: CreateTaskInput!) {
            createTask(input: $input) {
                id
                name
                difficultyRank
            }
        }",
        "variables": {
            "input": {
                "name": "Unranked New Task",
                "description": "No difficulty set"
            }
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);
    assert!(json.get("data").is_some(), "Response: {:?}", json);

    let task = json.get("data").unwrap().get("createTask").unwrap();
    assert!(task.get("id").is_some());
    assert_eq!(task.get("name").unwrap(), "Unranked New Task");
    assert!(task.get("difficultyRank").unwrap().is_null());
}
