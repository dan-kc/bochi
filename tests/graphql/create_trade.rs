use crate::common::{get_access_token_for_user, make_authenticated_graphql_request, register_user};
use crate::generate_email_from_fn;
use axum::body::Body;
use axum::http::{Request, StatusCode};
use http::Method;
use serde_json::{json, Value};
use tofustash_backend::router;
use tower::ServiceExt;

#[tokio::test]
async fn test_create_trade_with_task_success() {
    let email = generate_email_from_fn!(test_create_trade_with_task_success);
    let password = "password123";

    // Register user
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
                "description": "A test task for trading",
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

    // Now create a trade with the task
    let query = json!({
        "query": "mutation CreateTrade($input: CreateTradeInput!) {
            createTrade(input: $input) {
                id
                amount
                createdAt
                tradableItem {
                    __typename
                    ... on TaskObject {
                        id
                        name
                        description
                        createdAt
                        deletedAt
                        hiddenUntil
                        dueBy
                    }
                    ... on RewardObject {
                        id
                        name
                        description
                        createdAt
                        deletedAt
                        hiddenUntil
                        maxDailyFrequency
                    }
                }
            }
        }",
        "variables": {
            "input": {
                "taskId": task_id,
            }
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);
    assert!(json.get("data").is_some());

    let trade = json.get("data").unwrap().get("createTrade").unwrap();
    assert!(trade.get("id").is_some());
    assert_eq!(trade.get("amount").unwrap(), 1000);
    assert!(trade.get("createdAt").is_some());

    let tradable_item = trade.get("tradableItem").unwrap();
    assert_eq!(tradable_item.get("__typename").unwrap(), "TaskObject");
    assert_eq!(tradable_item.get("id").unwrap(), task_id);
    assert_eq!(tradable_item.get("name").unwrap(), "Test Task");
    assert_eq!(
        tradable_item.get("description").unwrap(),
        "A test task for trading"
    );
    assert!(tradable_item.get("createdAt").is_some());
    assert_eq!(
        tradable_item.get("deletedAt").unwrap(),
        &serde_json::Value::Null
    );
    assert_eq!(
        tradable_item.get("hiddenUntil").unwrap(),
        &serde_json::Value::Null
    );
    assert_eq!(
        tradable_item.get("dueBy").unwrap(),
        &serde_json::Value::Null
    );
}

#[tokio::test]
async fn test_create_trade_with_reward_success() {
    let email = generate_email_from_fn!(test_create_trade_with_reward_success);
    let password = "password123";

    // Register user
    register_user(&email, password).await;

    let access_token = get_access_token_for_user(&email, &password).await;

    // First create a reward
    let create_reward_query = json!({
        "query": "mutation CreateReward($input: CreateRewardInput!) {
            createReward(input: $input) {
                id
            }
        }",
        "variables": {
            "input": {
                "name": "Test Reward",
                "description": "A test reward for trading",
                "maxDailyFrequency": 3.5,
            }
        }
    });

    let (status, json) =
        make_authenticated_graphql_request(&access_token, create_reward_query).await;
    assert_eq!(status, StatusCode::OK);
    let reward_id = json
        .get("data")
        .unwrap()
        .get("createReward")
        .unwrap()
        .get("id")
        .unwrap()
        .as_str()
        .unwrap();

    // Now create a trade with the reward
    let query = json!({
        "query": "mutation CreateTrade($input: CreateTradeInput!) {
            createTrade(input: $input) {
                id
                amount
                createdAt
                tradableItem {
                    __typename
                    ... on TaskObject {
                        id
                        name
                        description
                        createdAt
                        deletedAt
                        hiddenUntil
                        dueBy
                    }
                    ... on RewardObject {
                        id
                        name
                        description
                        createdAt
                        deletedAt
                        hiddenUntil
                        maxDailyFrequency
                    }
                }
            }
        }",
        "variables": {
            "input": {
                "rewardId": reward_id,
            }
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);
    assert!(json.get("data").is_some());

    let trade = json.get("data").unwrap().get("createTrade").unwrap();
    assert!(trade.get("id").is_some());
    assert_eq!(trade.get("amount").unwrap(), 1000);
    assert!(trade.get("createdAt").is_some());

    let tradable_item = trade.get("tradableItem").unwrap();
    assert_eq!(tradable_item.get("__typename").unwrap(), "RewardObject");
    assert_eq!(tradable_item.get("id").unwrap(), reward_id);
    assert_eq!(tradable_item.get("name").unwrap(), "Test Reward");
    assert_eq!(
        tradable_item.get("description").unwrap(),
        "A test reward for trading"
    );
    assert!(tradable_item.get("createdAt").is_some());
    assert_eq!(
        tradable_item.get("deletedAt").unwrap(),
        &serde_json::Value::Null
    );
    assert_eq!(
        tradable_item.get("hiddenUntil").unwrap(),
        &serde_json::Value::Null
    );
    assert_eq!(tradable_item.get("maxDailyFrequency").unwrap(), 3.5);
}

#[tokio::test]
async fn test_create_trade_with_both_task_and_reward() {
    let email = generate_email_from_fn!(test_create_trade_with_both_task_and_reward);
    let password = "password123";

    // Register user
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
                "description": "A test task",
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

    // Create a reward
    let create_reward_query = json!({
        "query": "mutation CreateReward($input: CreateRewardInput!) {
            createReward(input: $input) {
                id
            }
        }",
        "variables": {
            "input": {
                "name": "Test Reward",
                "description": "A test reward",
            }
        }
    });

    let (status, json) =
        make_authenticated_graphql_request(&access_token, create_reward_query).await;
    assert_eq!(status, StatusCode::OK);
    let reward_id = json
        .get("data")
        .unwrap()
        .get("createReward")
        .unwrap()
        .get("id")
        .unwrap()
        .as_str()
        .unwrap();

    // Try to create a trade with both
    let query = json!({
        "query": "mutation CreateTrade($input: CreateTradeInput!) {
            createTrade(input: $input) {
                id
            }
        }",
        "variables": {
            "input": {
                "taskId": task_id,
                "rewardId": reward_id,
            }
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);
    assert!(json.get("errors").is_some());

    let errors = json.get("errors").unwrap().as_array().unwrap();
    assert_eq!(errors.len(), 1);

    let error = errors.first().unwrap();
    assert_eq!(
        error.get("message").unwrap(),
        &Value::String(
            "Validation Error: Must have exactly one of either `task_id` or `reward_id`"
                .to_string()
        )
    );

    let extensions = error.get("extensions").unwrap();
    assert_eq!(
        extensions.get("code").unwrap(),
        &Value::String("BAD_USER_INPUT".to_string())
    );
    assert_eq!(
        extensions.get("details").unwrap(),
        &Value::String(
            "Validation Error: Must have exactly one of either `task_id` or `reward_id`"
                .to_string()
        )
    );
}

#[tokio::test]
async fn test_create_trade_with_neither_task_nor_reward() {
    let email = generate_email_from_fn!(test_create_trade_with_neither_task_nor_reward);
    let password = "password123";

    // Register user
    register_user(&email, password).await;

    let access_token = get_access_token_for_user(&email, &password).await;

    // Try to create a trade with neither task nor reward
    let query = json!({
        "query": "mutation CreateTrade($input: CreateTradeInput!) {
            createTrade(input: $input) {
                id
            }
        }",
        "variables": {
            "input": {}
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);
    assert!(json.get("errors").is_some());

    let errors = json.get("errors").unwrap().as_array().unwrap();
    assert_eq!(errors.len(), 1);

    let error = errors.first().unwrap();
    assert_eq!(
        error.get("message").unwrap(),
        &Value::String(
            "Validation Error: Must have exactly one of either `task_id` or `reward_id`"
                .to_string()
        )
    );

    let extensions = error.get("extensions").unwrap();
    assert_eq!(
        extensions.get("code").unwrap(),
        &Value::String("BAD_USER_INPUT".to_string())
    );
    assert_eq!(
        extensions.get("details").unwrap(),
        &Value::String(
            "Validation Error: Must have exactly one of either `task_id` or `reward_id`"
                .to_string()
        )
    );
}

#[tokio::test]
async fn test_create_trade_without_authentication() {
    let router = router::router().await;

    let query = json!({
        "query": "mutation CreateTrade($input: CreateTradeInput!) {
            createTrade(input: $input) {
                id
            }
        }",
        "variables": {
            "input": {
                "taskId": "079d9887-79f9-4bdf-a341-2d5990a694e1",
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
async fn test_create_trade_with_invalid_auth_token() {
    let router = router::router().await;

    let query = json!({
        "query": "mutation CreateTrade($input: CreateTradeInput!) {
            createTrade(input: $input) {
                id
            }
        }",
        "variables": {
            "input": {
                "taskId": "1d85a35e-f39f-4f60-9015-f449d3f97ed2",
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
async fn test_create_trade_with_nonexistent_task() {
    let email = generate_email_from_fn!(test_create_trade_with_nonexistent_task);
    let password = "password123";

    // Register user
    register_user(&email, password).await;

    let access_token = get_access_token_for_user(&email, &password).await;

    // Try to create a trade with a nonexistent task ID
    let query = json!({
        "query": "mutation CreateTrade($input: CreateTradeInput!) {
            createTrade(input: $input) {
                id
            }
        }",
        "variables": {
            "input": {
                "taskId": "2d452d8f-f87a-4d6b-b16a-acdfcbea1fff",
            }
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);
    assert!(json.get("errors").is_some());

    let errors = json.get("errors").unwrap().as_array().unwrap();
    assert_eq!(errors.len(), 1);

    let error = errors.first().unwrap();
    assert_eq!(
        error.get("message").unwrap(),
        &Value::String("An unexpected internal server error occurred.".to_string())
    );

    let extensions = error.get("extensions").unwrap();
    assert_eq!(
        extensions.get("code").unwrap(),
        &Value::String("INTERNAL_SERVER_ERROR".to_string())
    );
}

#[tokio::test]
async fn test_create_trade_with_nonexistent_reward() {
    let email = generate_email_from_fn!(test_create_trade_with_nonexistent_reward);
    let password = "password123";

    // Register user
    register_user(&email, password).await;

    let access_token = get_access_token_for_user(&email, &password).await;

    // Try to create a trade with a nonexistent reward ID
    let query = json!({
        "query": "mutation CreateTrade($input: CreateTradeInput!) {
            createTrade(input: $input) {
                id
            }
        }",
        "variables": {
            "input": {
                "rewardId": "e1633515-d8b9-4ae2-bc93-5f2b3b0956fc",
            }
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);
    assert!(json.get("errors").is_some());

    let errors = json.get("errors").unwrap().as_array().unwrap();
    assert_eq!(errors.len(), 1);

    let error = errors.first().unwrap();
    assert_eq!(
        error.get("message").unwrap(),
        &Value::String("An unexpected internal server error occurred.".to_string())
    );

    let extensions = error.get("extensions").unwrap();
    assert_eq!(
        extensions.get("code").unwrap(),
        &Value::String("INTERNAL_SERVER_ERROR".to_string())
    );
}

#[tokio::test]
async fn test_create_trade_interface_fields() {
    let email = generate_email_from_fn!(test_create_trade_interface_fields);
    let password = "password123";

    // Register user
    register_user(&email, password).await;

    let access_token = get_access_token_for_user(&email, &password).await;

    // Create a task with dates
    let create_task_query = json!({
        "query": "mutation CreateTask($input: CreateTaskInput!) {
            createTask(input: $input) {
                id
            }
        }",
        "variables": {
            "input": {
                "name": "Test Task with Dates",
                "description": "A test task with optional dates",
                "hiddenUntil": "2028-12-16T00:33:08",
                "dueBy": "2028-12-25T23:59:59",
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

    // Query for interface fields only
    let query = json!({
        "query": "mutation CreateTrade($input: CreateTradeInput!) {
            createTrade(input: $input) {
                id
                amount
                tradableItem {
                    id
                    name
                    description
                    createdAt
                    deletedAt
                    hiddenUntil
                }
            }
        }",
        "variables": {
            "input": {
                "taskId": task_id,
            }
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);
    assert!(json.get("data").is_some());

    let trade = json.get("data").unwrap().get("createTrade").unwrap();
    assert!(trade.get("id").is_some());
    assert_eq!(trade.get("amount").unwrap(), 1000);

    let tradable_item = trade.get("tradableItem").unwrap();
    assert_eq!(tradable_item.get("id").unwrap().as_str().unwrap(), task_id);
    assert_eq!(tradable_item.get("name").unwrap(), "Test Task with Dates");
    assert_eq!(
        tradable_item.get("description").unwrap(),
        "A test task with optional dates"
    );
    assert!(tradable_item.get("createdAt").is_some());
    assert_eq!(
        tradable_item.get("deletedAt").unwrap(),
        &serde_json::Value::Null
    );
    assert_eq!(
        tradable_item.get("hiddenUntil").unwrap(),
        "2028-12-16T00:33:08"
    );
}

#[tokio::test]
async fn test_create_trade_query_specific_type_fields() {
    let email = generate_email_from_fn!(test_create_trade_query_specific_type_fields);
    let password = "password123";

    // Register user
    register_user(&email, password).await;

    let access_token = get_access_token_for_user(&email, &password).await;

    // Create a reward with specific fields
    let create_reward_query = json!({
        "query": "mutation CreateReward($input: CreateRewardInput!) {
            createReward(input: $input) {
                id
            }
        }",
        "variables": {
            "input": {
                "name": "Test Reward with Frequency",
                "description": "A test reward with max frequency",
                "maxDailyFrequency": 10.0,
                "hiddenUntil": "2028-01-01T00:00:00",
            }
        }
    });

    let (status, json) =
        make_authenticated_graphql_request(&access_token, create_reward_query).await;
    assert_eq!(status, StatusCode::OK);
    let reward_id = json
        .get("data")
        .unwrap()
        .get("createReward")
        .unwrap()
        .get("id")
        .unwrap()
        .as_str()
        .unwrap();

    // Query with inline fragments to get type-specific fields
    let query = json!({
        "query": "mutation CreateTrade($input: CreateTradeInput!) {
            createTrade(input: $input) {
                id
                tradableItem {
                    id
                    name
                    ... on RewardObject {
                        maxDailyFrequency
                    }
                    ... on TaskObject {
                        dueBy
                    }
                }
            }
        }",
        "variables": {
            "input": {
                "rewardId": reward_id,
            }
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);
    assert!(json.get("data").is_some());

    let trade = json.get("data").unwrap().get("createTrade").unwrap();
    let tradable_item = trade.get("tradableItem").unwrap();
    assert_eq!(tradable_item.get("id").unwrap(), reward_id);
    assert_eq!(
        tradable_item.get("name").unwrap(),
        "Test Reward with Frequency"
    );
    assert_eq!(tradable_item.get("maxDailyFrequency").unwrap(), 10.0);
    // dueBy shouldn't be present since it's a Reward
    assert!(tradable_item.get("dueBy").is_none());
}
