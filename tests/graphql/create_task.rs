use crate::common::{get_access_token_for_user, make_authenticated_graphql_request, register_user};
use crate::generate_email_from_fn;
use axum::body::Body;
use axum::http::{Request, StatusCode};
use habit_market_backend::router;
use http::Method;
use serde_json::{json, Value};
use tower::ServiceExt;

#[tokio::test]
async fn test_create_task_success() {
    let email = generate_email_from_fn!(test_create_task_success);
    let password = "password123";

    // Register user
    register_user(&email, password).await;

    let access_token = get_access_token_for_user(&email, &password).await;

    let query = json!({
        "query": "mutation CreateTask($input: CreateTaskInput!) {
            createTask(input: $input) {
                id
                name
                createdAt
                deletedAt
                description
                hiddenUntil
                dueBy
            }
        }",
        "variables": {
            "input": {
                "name": "Test Task",
                "description": "A test task description",
            }
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;

    assert_eq!(status, StatusCode::OK);
    assert!(json.get("data").is_some(), "Response should have data");

    let data = json.get("data").unwrap();
    let task = data.get("createTask").unwrap();

    assert!(task.get("id").is_some());
    assert_eq!(task.get("name").unwrap().as_str().unwrap(), "Test Task");
    assert!(task.get("createdAt").is_some());
    assert_eq!(task.get("deletedAt").unwrap(), &serde_json::Value::Null);
    assert_eq!(
        task.get("description").unwrap().as_str().unwrap(),
        "A test task description"
    );
    assert_eq!(task.get("hiddenUntil").unwrap(), &serde_json::Value::Null);
    assert_eq!(task.get("dueBy").unwrap(), &serde_json::Value::Null);
}

#[tokio::test]
async fn test_create_due_task_success() {
    let email = generate_email_from_fn!(test_create_task_success);
    let password = "password123";

    // Register user
    register_user(&email, password).await;

    let access_token = get_access_token_for_user(&email, &password).await;

    let query = json!({
        "query": "mutation CreateTask($input: CreateTaskInput!) {
            createTask(input: $input) {
                dueBy
            }
        }",
        "variables": {
            "input": {
                "name": "Test Task",
                "description": "A test task description",
                "dueBy": "2028-12-25T23:59:59",
            }
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);
    let task = json.get("data").unwrap().get("createTask").unwrap();

    assert_eq!(task.get("dueBy").unwrap(), "2028-12-25T23:59:59");
}

#[tokio::test]
async fn test_create_task_with_optional_fields() {
    let email = generate_email_from_fn!(test_create_task_with_optional_fields);
    let password = "password123";

    // Register user
    register_user(&email, password).await;

    let access_token = get_access_token_for_user(&email, &password).await;

    let query = json!({
        "query": "mutation CreateTask($input: CreateTaskInput!) {
            createTask(input: $input) {
                hiddenUntil
                dueBy
            }
        }",
        "variables": {
            "input": {
                "name": "Task with dates",
                "description": "Task with optional dates",
                "hiddenUntil": "2028-12-16T00:33:08",
                "dueBy": "2028-12-25T23:59:59",
            }
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);

    let task = json.get("data").unwrap().get("createTask").unwrap();
    assert_eq!(task.get("hiddenUntil").unwrap(), "2028-12-16T00:33:08");
    assert_eq!(task.get("dueBy").unwrap(), "2028-12-25T23:59:59");
}

#[tokio::test]
async fn test_create_task_validation_name_too_long() {
    let email = generate_email_from_fn!(test_create_task_validation_name_too_long);
    let password = "password123";

    // Register user
    register_user(&email, password).await;

    let access_token = get_access_token_for_user(&email, &password).await;

    let long_name = "a".repeat(101);
    let query = json!({
        "query": "mutation CreateTask($input: CreateTaskInput!) {
            createTask(input: $input) {
                name
            }
        }",
        "variables": {
            "input": {
                "name": long_name,
                "description": "Test description",
            }
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);

    assert!(
        json.get("errors").is_some(),
        "Response should contain validation errors"
    );
    let errors = json.get("errors").unwrap().as_array().unwrap();
    assert!(!errors.contains(&Value::String("Should have validation errors".to_string())),);
}

#[tokio::test]
async fn test_create_task_validation_description_too_long() {
    let email = generate_email_from_fn!(test_create_task_validation_description_too_long);
    let password = "password123";

    // Register user
    register_user(&email, password).await;

    let access_token = get_access_token_for_user(&email, &password).await;

    let long_description = "a".repeat(16385);
    let query = json!({
        "query": "mutation CreateTask($input: CreateTaskInput!) {
            createTask(input: $input) {
                name
            }
        }",
        "variables": {
            "input": {
                "name": "Test Task",
                "description": long_description,
            }
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);

    assert!(
        json.get("errors").is_some(),
        "Response should contain validation errors"
    );
    let errors = json.get("errors").unwrap().as_array().unwrap();
    assert!(!errors.contains(&Value::String("Should have validation errors".to_string())),);
}

#[tokio::test]
async fn test_create_task_without_authentication() {
    let router = router::router().await;

    let query = json!({
        "query": "mutation CreateTask($input: CreateTaskInput!) {
            createTask(input: $input) {
                id
            }
        }",
        "variables": {
            "input": {
                "name": "Test Task",
                "description": "Test description",
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
async fn test_create_task_with_invalid_auth_token() {
    let router = router::router().await;

    let query = json!({
        "query": "mutation CreateTask($input: CreateTaskInput!) {
            createTask(input: $input) {
                id
            }
        }",
        "variables": {
            "input": {
                "name": "Test Task",
                "description": "Test description",
            }
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
async fn test_create_task_minimum_valid_input() {
    let email = generate_email_from_fn!(test_create_task_minimum_valid_input);
    let password = "password123";

    // Register user
    register_user(&email, password).await;

    let access_token = get_access_token_for_user(&email, &password).await;

    let query = json!({
        "query": "mutation CreateTask($input: CreateTaskInput!) {
            createTask(input: $input) {
                name
                description
            }
        }",
        "variables": {
            "input": {
                "name": "T",
                "description": "",
            }
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);

    assert!(json.get("data").is_some(), "Response should have data");
    let task = json.get("data").unwrap().get("createTask").unwrap();
    assert_eq!(task.get("name").unwrap().as_str().unwrap(), "T");
    assert_eq!(task.get("description").unwrap().as_str().unwrap(), "");
}

#[tokio::test]
async fn test_create_task_maximum_valid_input() {
    let email = generate_email_from_fn!(test_create_task_maximum_valid_input);
    let password = "password123";

    // Register user
    register_user(&email, password).await;

    let access_token = get_access_token_for_user(&email, &password).await;

    let max_name = "a".repeat(100);
    let max_description = "b".repeat(16384);

    let query = json!({
        "query": "mutation CreateTask($input: CreateTaskInput!) {
            createTask(input: $input) {
                name
                description
            }
        }",
        "variables": {
            "input": {
                "name": max_name,
                "description": max_description,
            }
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);

    assert!(json.get("data").is_some(), "Response should have data");
    let task = json.get("data").unwrap().get("createTask").unwrap();
    assert_eq!(task.get("name").unwrap(), &Value::String(max_name));
    assert_eq!(
        task.get("description").unwrap(),
        &Value::String(max_description)
    );
}

#[tokio::test]
async fn test_create_task_hidden_until_in_past() {
    let email = generate_email_from_fn!(test_create_task_maximum_valid_input);
    let password = "password123";

    // Register user
    register_user(&email, password).await;

    let access_token = get_access_token_for_user(&email, &password).await;

    let query = json!({
        "query": "mutation CreateTask($input: CreateTaskInput!) {
            createTask(input: $input) {
                hiddenUntil
            }
        }",
        "variables": {
            "input": {
                "name": "test name",
                "description": "test description",
                "hiddenUntil": "2022-12-25T23:59:59"
            }
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);

    assert!(
        json.get("errors").is_some(),
        "Response should contain validation errors"
    );
    let errors = json.get("errors").unwrap().as_array().unwrap();
    assert!(!errors.contains(&Value::String(
        "`hidden_until` must be in the future.".to_string()
    )),);
}

#[tokio::test]
async fn test_create_task_due_by_in_past() {
    let email = generate_email_from_fn!(test_create_task_maximum_valid_input);
    let password = "password123";

    // Register user
    register_user(&email, password).await;

    let access_token = get_access_token_for_user(&email, &password).await;

    let query = json!({
        "query": "mutation CreateTask($input: CreateTaskInput!) {
            createTask(input: $input) {
                dueBy
            }
        }",
        "variables": {
            "input": {
                "name": "test name",
                "description": "test description",
                "dueBy": "2022-12-25T23:59:59"
            }
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);

    assert!(
        json.get("errors").is_some(),
        "Response should contain validation errors"
    );
    let errors = json.get("errors").unwrap().as_array().unwrap();
    assert!(!errors.contains(&Value::String("`dueBy` must be in the future.".to_string())),);
}

#[tokio::test]
async fn test_create_task_no_name() {
    let email = generate_email_from_fn!(test_create_task_no_name);
    let password = "password123";

    // Register user
    register_user(&email, password).await;

    let access_token = get_access_token_for_user(&email, &password).await;

    let query = json!({
        "query": "mutation CreateTask($input: CreateTaskInput!) {
            createTask(input: $input) {
                name
            }
        }",
        "variables": {
            "input": {
                "description": "Test description",
            }
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);

    assert!(
        json.get("errors").is_some(),
        "Response should contain validation errors"
    );
}

#[tokio::test]
async fn test_create_task_no_description() {
    let email = generate_email_from_fn!(test_create_task_no_description);
    let password = "password123";

    // Register user
    register_user(&email, password).await;

    let access_token = get_access_token_for_user(&email, &password).await;

    let query = json!({
        "query": "mutation CreateTask($input: CreateTaskInput!) {
            createTask(input: $input) {
                name
            }
        }",
        "variables": {
            "input": {
                "name": "Test Task",
            }
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);

    assert!(
        json.get("errors").is_some(),
        "Response should contain validation errors"
    );
}

#[tokio::test]
async fn test_create_task_name_empty_string() {
    let email = generate_email_from_fn!(test_create_task_name_empty_string);
    let password = "password123";

    // Register user
    register_user(&email, password).await;

    let access_token = get_access_token_for_user(&email, &password).await;

    let query = json!({
        "query": "mutation CreateTask($input: CreateTaskInput!) {
            createTask(input: $input) {
                name
            }
        }",
        "variables": {
            "input": {
                "name": "",
                "description": "Test description",
            }
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);

    assert!(
        json.get("errors").is_some(),
        "Response should contain validation errors"
    );
}
