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
                hiddenUntil
                dueBy
                description
                difficultyRank
                dailyFrequency
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

    assert!(task.get("id").is_some(), "Task should have id");
    assert_eq!(task.get("name").unwrap().as_str().unwrap(), "Test Task");
    assert_eq!(
        task.get("description").unwrap().as_str().unwrap(),
        "A test task description"
    );
    assert_eq!(task.get("difficultyRank").unwrap().as_i64().unwrap(), 5);
    assert!(
        task.get("createdAt").is_some(),
        "Task should have createdAt"
    );
    assert!(task.get("dueBy").is_none());
    assert!(task.get("dailyFrequency").is_none());
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
                id
                name
                createdAt
                deletedAt
                hiddenUntil
                dueBy
                description
                difficultyRank
                dailyFrequency
            }
        }",
        "variables": {
            "input": {
                "name": "Test Task",
                "description": "A test task description",
                "difficultyRank": 5,
                "dueBy": "2028-12-25T23:59:59",
            }
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);

    assert!(json.get("data").is_some(), "Response should have data");
    let data = json.get("data").unwrap();
    let task = data.get("createTask").unwrap();

    assert!(task.get("id").is_some(), "Task should have id");
    assert_eq!(task.get("name").unwrap().as_str().unwrap(), "Test Task");
    assert_eq!(
        task.get("description").unwrap().as_str().unwrap(),
        "A test task description"
    );
    assert_eq!(task.get("difficultyRank").unwrap().as_i64().unwrap(), 5);
    assert!(
        task.get("createdAt").is_some(),
        "Task should have createdAt"
    );
    assert_eq!(task.get("dueBy").unwrap(), "2028-12-25T23:59:59");
}

#[tokio::test]
async fn test_create_recurring_task_success() {
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
                hiddenUntil
                dueBy
                description
                difficultyRank
                dailyFrequency
            }
        }",
        "variables": {
            "input": {
                "name": "Test Task",
                "description": "A test task description",
                "difficultyRank": 5,
                "dailyFrequency": 10,
            }
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);

    assert!(json.get("data").is_some(), "Response should have data");
    let data = json.get("data").unwrap();
    let task = data.get("createTask").unwrap();

    assert!(task.get("id").is_some(), "Task should have id");
    assert_eq!(task.get("name").unwrap().as_str().unwrap(), "Test Task");
    assert!(task.get("createdAt").is_some());
    assert!(task.get("hiddenUntil").is_none());
    assert_eq!(
        task.get("description").unwrap().as_str().unwrap(),
        "A test task description"
    );
    assert_eq!(task.get("difficultyRank").unwrap().as_i64().unwrap(), 5);
    assert_eq!(task.get("dailyFrequency").unwrap(), 10);
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
                id
                name
                hiddenUntil
                dueBy
                description
                difficultyRank
            }
        }",
        "variables": {
            "input": {
                "name": "Task with dates",
                "description": "Task with optional dates",
                "difficultyRank": 3,
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
async fn test_create_due_by_and_daily_freq() {
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
                hiddenUntil
                dueBy
                description
                difficultyRank
                dailyFrequency
            }
        }",
        "variables": {
            "input": {
                "name": "Test Task",
                "description": "A test task description",
                "difficultyRank": 5,
                "dailyFrequency": 10,
                "dueBy": "2028-12-25T23:59:59",
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
        "A task cannot have both a dueBy and a dailyFreqency.".to_string()
    )));
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
                id
                name
            }
        }",
        "variables": {
            "input": {
                "name": long_name,
                "description": "Test description",
                "difficultyRank": 5
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
                id
                name
            }
        }",
        "variables": {
            "input": {
                "name": "Test Task",
                "description": long_description,
                "difficultyRank": 5
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
async fn test_create_task_validation_difficulty_rank_negative() {
    let email = generate_email_from_fn!(test_create_task_validation_difficulty_rank_negative);
    let password = "password123";

    // Register user
    register_user(&email, password).await;

    let access_token = get_access_token_for_user(&email, &password).await;

    let query = json!({
        "query": "mutation CreateTask($input: CreateTaskInput!) {
            createTask(input: $input) {
                id
                name
            }
        }",
        "variables": {
            "input": {
                "name": "Test Task",
                "description": "Test description",
                "difficultyRank": -1
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
                name
            }
        }",
        "variables": {
            "input": {
                "name": "Test Task",
                "description": "Test description",
                "difficultyRank": 5
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
                name
            }
        }",
        "variables": {
            "input": {
                "name": "Test Task",
                "description": "Test description",
                "difficultyRank": 5
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
                id
                name
                description
                difficultyRank
            }
        }",
        "variables": {
            "input": {
                "name": "T",
                "description": "",
                "difficultyRank": 0
            }
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);

    assert!(json.get("data").is_some(), "Response should have data");
    let task = json.get("data").unwrap().get("createTask").unwrap();
    assert_eq!(task.get("name").unwrap().as_str().unwrap(), "T");
    assert_eq!(task.get("description").unwrap().as_str().unwrap(), "");
    assert_eq!(task.get("difficultyRank").unwrap().as_i64().unwrap(), 0);
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
                id
                name
                description
                difficultyRank
            }
        }",
        "variables": {
            "input": {
                "name": max_name,
                "description": max_description,
                "difficultyRank": 2147483647
            }
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);

    assert!(json.get("data").is_some(), "Response should have data");
    let task = json.get("data").unwrap().get("createTask").unwrap();
    assert!(
        task.get("id").is_some(),
        "Task should be created with valid max inputs"
    );
}
