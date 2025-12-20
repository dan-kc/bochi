use crate::common::{get_access_token_for_user, make_authenticated_graphql_request, register_user};
use crate::generate_email_from_fn;
use axum::body::Body;
use axum::http::{Request, StatusCode};
use tofustash_backend::router;
use http::Method;
use serde_json::{json, Value};
use tower::ServiceExt;

#[tokio::test]
async fn test_create_reward_success() {
    let email = generate_email_from_fn!(test_create_reward_success);
    let password = "password123";

    // Register user
    register_user(&email, password).await;

    let access_token = get_access_token_for_user(&email, &password).await;

    let query = json!({
        "query": "mutation CreateReward($input: CreateRewardInput!) {
            createReward(input: $input) {
                id
                name
                createdAt
                deletedAt
                description
                hiddenUntil
                maxDailyFrequency
            }
        }",
        "variables": {
            "input": {
                "name": "Test Reward",
                "description": "A test reward description",
            }
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);
    assert!(json.get("data").is_some());

    let reward = json.get("data").unwrap().get("createReward").unwrap();
    assert!(reward.get("id").is_some());
    assert_eq!(reward.get("name").unwrap().as_str().unwrap(), "Test Reward");
    assert!(reward.get("createdAt").is_some());
    assert_eq!(reward.get("deletedAt").unwrap(), &serde_json::Value::Null);
    assert_eq!(
        reward.get("description").unwrap().as_str().unwrap(),
        "A test reward description"
    );
    assert_eq!(reward.get("hiddenUntil").unwrap(), &serde_json::Value::Null);
    assert_eq!(
        reward.get("maxDailyFrequency").unwrap(),
        &serde_json::Value::Null
    );
}

#[tokio::test]
async fn test_create_reward_with_max_daily_frequency() {
    let email = generate_email_from_fn!(test_create_reward_with_max_daily_frequency);
    let password = "password123";

    // Register user
    register_user(&email, password).await;

    let access_token = get_access_token_for_user(&email, &password).await;

    let query = json!({
        "query": "mutation CreateReward($input: CreateRewardInput!) {
            createReward(input: $input) {
                maxDailyFrequency
            }
        }",
        "variables": {
            "input": {
                "name": "Test Reward",
                "description": "A test reward description",
                "maxDailyFrequency": 5.5,
            }
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);

    let reward = json.get("data").unwrap().get("createReward").unwrap();
    assert_eq!(reward.get("maxDailyFrequency").unwrap(), 5.5);
}

#[tokio::test]
async fn test_create_reward_with_optional_fields() {
    let email = generate_email_from_fn!(test_create_reward_with_optional_fields);
    let password = "password123";

    // Register user
    register_user(&email, password).await;

    let access_token = get_access_token_for_user(&email, &password).await;

    let query = json!({
        "query": "mutation CreateReward($input: CreateRewardInput!) {
            createReward(input: $input) {
                hiddenUntil
                maxDailyFrequency
            }
        }",
        "variables": {
            "input": {
                "name": "Reward with optional fields",
                "description": "Reward with optional fields",
                "hiddenUntil": "2028-12-16T00:33:08",
                "maxDailyFrequency": 10.0,
            }
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);

    let reward = json.get("data").unwrap().get("createReward").unwrap();
    assert_eq!(reward.get("hiddenUntil").unwrap(), "2028-12-16T00:33:08");
    assert_eq!(reward.get("maxDailyFrequency").unwrap(), 10.0);
}

#[tokio::test]
async fn test_create_reward_validation_name_too_long() {
    let email = generate_email_from_fn!(test_create_reward_validation_name_too_long);
    let password = "password123";

    // Register user
    register_user(&email, password).await;

    let access_token = get_access_token_for_user(&email, &password).await;

    let long_name = "a".repeat(101);
    let query = json!({
        "query": "mutation CreateReward($input: CreateRewardInput!) {
            createReward(input: $input) {
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
    assert!(json.get("errors").is_some(),);

    let errors = json.get("errors").unwrap().as_array().unwrap();
    assert_eq!(errors.len(), 1);

    let error = errors.first().unwrap();
    assert_eq!(error.get("message").unwrap(), &Value::String("Validation Error: Please provide a name between 1 and 100 characters long. Your current name is 101 characters.".to_string()));

    let extensions = error.get("extensions").unwrap();
    assert_eq!(
        extensions.get("code").unwrap(),
        &Value::String("BAD_USER_INPUT".to_string())
    );
    assert_eq!(extensions.get("details").unwrap(), &Value::String("Validation Error: Please provide a name between 1 and 100 characters long. Your current name is 101 characters.".to_string()));
}

#[tokio::test]
async fn test_create_reward_validation_description_too_long() {
    let email = generate_email_from_fn!(test_create_reward_validation_description_too_long);
    let password = "password123";

    // Register user
    register_user(&email, password).await;

    let access_token = get_access_token_for_user(&email, &password).await;

    let long_description = "a".repeat(16385);
    let query = json!({
        "query": "mutation CreateReward($input: CreateRewardInput!) {
            createReward(input: $input) {
                name
            }
        }",
        "variables": {
            "input": {
                "name": "Test Reward",
                "description": long_description,
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
            "Validation Error: Description is too long (16385 characters), max 16384.".to_string()
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
            "Validation Error: Description is too long (16385 characters), max 16384.".to_string()
        )
    );
}

#[tokio::test]
async fn test_create_reward_without_authentication() {
    let router = router::router().await;

    let query = json!({
        "query": "mutation CreateReward($input: CreateRewardInput!) {
            createReward(input: $input) {
                id
            }
        }",
        "variables": {
            "input": {
                "name": "Test Reward",
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
async fn test_create_reward_with_invalid_auth_token() {
    let router = router::router().await;

    let query = json!({
        "query": "mutation CreateReward($input: CreateRewardInput!) {
            createReward(input: $input) {
                id
            }
        }",
        "variables": {
            "input": {
                "name": "Test Reward",
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
async fn test_create_reward_minimum_valid_input() {
    let email = generate_email_from_fn!(test_create_reward_minimum_valid_input);
    let password = "password123";

    // Register user
    register_user(&email, password).await;

    let access_token = get_access_token_for_user(&email, &password).await;

    let query = json!({
        "query": "mutation CreateReward($input: CreateRewardInput!) {
            createReward(input: $input) {
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
    assert!(json.get("data").is_some());

    let reward = json.get("data").unwrap().get("createReward").unwrap();
    assert_eq!(reward.get("name").unwrap().as_str().unwrap(), "T");
    assert_eq!(reward.get("description").unwrap().as_str().unwrap(), "");
}

#[tokio::test]
async fn test_create_reward_maximum_valid_input() {
    let email = generate_email_from_fn!(test_create_reward_maximum_valid_input);
    let password = "password123";

    // Register user
    register_user(&email, password).await;

    let access_token = get_access_token_for_user(&email, &password).await;

    let max_name = "a".repeat(100);
    let max_description = "b".repeat(16384);

    let query = json!({
        "query": "mutation CreateReward($input: CreateRewardInput!) {
            createReward(input: $input) {
                name
                description
                maxDailyFrequency
            }
        }",
        "variables": {
            "input": {
                "name": max_name,
                "description": max_description,
                "maxDailyFrequency": 100.0,
            }
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);
    assert!(json.get("data").is_some());

    let reward = json.get("data").unwrap().get("createReward").unwrap();
    assert_eq!(reward.get("name").unwrap(), &Value::String(max_name));
    assert_eq!(
        reward.get("description").unwrap(),
        &Value::String(max_description)
    );
    assert_eq!(reward.get("maxDailyFrequency").unwrap(), 100.0);
}

#[tokio::test]
async fn test_create_reward_hidden_until_in_past() {
    let email = generate_email_from_fn!(test_create_reward_hidden_until_in_past);
    let password = "password123";

    // Register user
    register_user(&email, password).await;

    let access_token = get_access_token_for_user(&email, &password).await;

    let query = json!({
        "query": "mutation CreateReward($input: CreateRewardInput!) {
            createReward(input: $input) {
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

    assert!(json.get("errors").is_some(),);

    let errors = json.get("errors").unwrap().as_array().unwrap();
    assert_eq!(errors.len(), 1);

    let error = errors.first().unwrap();
    assert_eq!(
        error.get("message").unwrap(),
        &Value::String("Validation Error: The 'hidden until' date (2022-12-25 23:59:59) has already passed or is the current moment. Please select a future date.".to_string())
    );

    let extensions = error.get("extensions").unwrap();
    assert_eq!(
        extensions.get("code").unwrap(),
        &Value::String("BAD_USER_INPUT".to_string())
    );
    assert_eq!(
        extensions.get("details").unwrap(),
        &Value::String(
            "Validation Error: The 'hidden until' date (2022-12-25 23:59:59) has already passed or is the current moment. Please select a future date.".to_string()
        )
    );
}

#[tokio::test]
async fn test_create_reward_max_daily_frequency_negative() {
    let email = generate_email_from_fn!(test_create_reward_max_daily_frequency_negative);
    let password = "password123";

    // Register user
    register_user(&email, password).await;

    let access_token = get_access_token_for_user(&email, &password).await;

    let query = json!({
        "query": "mutation CreateReward($input: CreateRewardInput!) {
            createReward(input: $input) {
                maxDailyFrequency
            }
        }",
        "variables": {
            "input": {
                "name": "test name",
                "description": "test description",
                "maxDailyFrequency": -1.0
            }
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);

    let errors = json.get("errors").unwrap().as_array().unwrap();
    assert_eq!(errors.len(), 1);

    let error = errors.first().unwrap();
    assert_eq!(
        error.get("message").unwrap(),
        &Value::String(
            "Validation Error: The 'max_daily_frequency must be between 0 and 100. You sent -1."
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
            "Validation Error: The 'max_daily_frequency must be between 0 and 100. You sent -1."
                .to_string()
        )
    );
}

#[tokio::test]
async fn test_create_reward_max_daily_frequency_too_large() {
    let email = generate_email_from_fn!(test_create_reward_max_daily_frequency_too_large);
    let password = "password123";

    // Register user
    register_user(&email, password).await;

    let access_token = get_access_token_for_user(&email, &password).await;

    let query = json!({
        "query": "mutation CreateReward($input: CreateRewardInput!) {
            createReward(input: $input) {
                maxDailyFrequency
            }
        }",
        "variables": {
            "input": {
                "name": "test name",
                "description": "test description",
                "maxDailyFrequency": 101.0
            }
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);

    let errors = json.get("errors").unwrap().as_array().unwrap();
    assert_eq!(errors.len(), 1);

    let error = errors.first().unwrap();
    assert_eq!(
        error.get("message").unwrap(),
        &Value::String(
            "Validation Error: The 'max_daily_frequency must be between 0 and 100. You sent 101."
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
            "Validation Error: The 'max_daily_frequency must be between 0 and 100. You sent 101."
                .to_string()
        )
    );
}

#[tokio::test]
async fn test_create_reward_no_name() {
    let email = generate_email_from_fn!(test_create_reward_no_name);
    let password = "password123";

    // Register user
    register_user(&email, password).await;

    let access_token = get_access_token_for_user(&email, &password).await;

    let query = json!({
        "query": "mutation CreateReward($input: CreateRewardInput!) {
            createReward(input: $input) {
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

    let errors: Vec<&Value> = json
        .get("errors")
        .expect("Response should contain validation errors")
        .as_array()
        .expect("errors field should be an array")
        .iter()
        .map(|x| {
            x.get("message")
                .expect("each entry in errors should have a 'message' field")
        })
        .collect();

    assert!(errors.contains(&&Value::String("Invalid value for argument \"input\", field \"name\" of type \"String!\" is required but not provided".to_string())))
}

#[tokio::test]
async fn test_create_reward_no_description() {
    let email = generate_email_from_fn!(test_create_reward_no_description);
    let password = "password123";

    // Register user
    register_user(&email, password).await;

    let access_token = get_access_token_for_user(&email, &password).await;

    let query = json!({
        "query": "mutation CreateReward($input: CreateRewardInput!) {
            createReward(input: $input) {
                name
            }
        }",
        "variables": {
            "input": {
                "name": "Test Reward",
            }
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);

    let errors: Vec<&Value> = json
        .get("errors")
        .unwrap()
        .as_array()
        .unwrap()
        .into_iter()
        .map(|x| x.get("message").unwrap())
        .collect();

    assert!(errors.contains(&&Value::String("Invalid value for argument \"input\", field \"description\" of type \"String!\" is required but not provided".to_string())));
}

#[tokio::test]
async fn test_create_reward_name_empty_string() {
    let email = generate_email_from_fn!(test_create_reward_name_empty_string);
    let password = "password123";

    // Register user
    register_user(&email, password).await;

    let access_token = get_access_token_for_user(&email, &password).await;

    let query = json!({
        "query": "mutation CreateReward($input: CreateRewardInput!) {
            createReward(input: $input) {
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

    let errors = json.get("errors").unwrap().as_array().unwrap();
    assert_eq!(errors.len(), 1);

    let error = errors.first().unwrap();
    assert_eq!(
        error.get("message").unwrap(),
        &Value::String("Validation Error: Please provide a name between 1 and 100 characters long. Your current name is 0 characters.".to_string())
    );

    let extensions = error.get("extensions").unwrap();
    assert_eq!(
        extensions.get("code").unwrap(),
        &Value::String("BAD_USER_INPUT".to_string())
    );
    assert_eq!(
        extensions.get("details").unwrap(),
        &Value::String(
            "Validation Error: Please provide a name between 1 and 100 characters long. Your current name is 0 characters.".to_string()
        )
    );
}

#[tokio::test]
async fn test_create_reward_max_daily_frequency_zero() {
    let email = generate_email_from_fn!(test_create_reward_max_daily_frequency_zero);
    let password = "password123";

    // Register user
    register_user(&email, password).await;

    let access_token = get_access_token_for_user(&email, &password).await;

    let query = json!({
        "query": "mutation CreateReward($input: CreateRewardInput!) {
            createReward(input: $input) {
                maxDailyFrequency
            }
        }",
        "variables": {
            "input": {
                "name": "Test Reward",
                "description": "Test description",
                "maxDailyFrequency": 0.0,
            }
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);
    assert!(json.get("data").is_some());

    let reward = json.get("data").unwrap().get("createReward").unwrap();
    assert_eq!(reward.get("maxDailyFrequency").unwrap(), 0.0);
}

#[tokio::test]
async fn test_create_reward_max_daily_frequency_boundary() {
    let email = generate_email_from_fn!(test_create_reward_max_daily_frequency_boundary);
    let password = "password123";

    // Register user
    register_user(&email, password).await;

    let access_token = get_access_token_for_user(&email, &password).await;

    let query = json!({
        "query": "mutation CreateReward($input: CreateRewardInput!) {
            createReward(input: $input) {
                maxDailyFrequency
            }
        }",
        "variables": {
            "input": {
                "name": "Test Reward",
                "description": "Test description",
                "maxDailyFrequency": 100.0,
            }
        }
    });

    let (status, json) = make_authenticated_graphql_request(&access_token, query).await;
    assert_eq!(status, StatusCode::OK);
    assert!(json.get("data").is_some());

    let reward = json.get("data").unwrap().get("createReward").unwrap();
    assert_eq!(reward.get("maxDailyFrequency").unwrap(), 100.0);
}
