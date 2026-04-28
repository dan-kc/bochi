use crate::common::{
    get_access_token_for_user, make_authenticated_post_request, make_unauthenticated_post_request,
    register_user,
};
use crate::generate_email_from_fn;
use axum::http::StatusCode;
use serde_json::{json, Value};

#[tokio::test]
async fn test_create_trade_with_task_success() {
    let email = generate_email_from_fn!(test_create_trade_with_task_success);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let task_body = json!({
        "name": "File taxes",
        "description": "Finish and submit",
        "difficultyTier": "trivial"
    });

    let (status, task_json) =
        make_authenticated_post_request(&access_token, "/api/tasks", task_body).await;
    assert_eq!(status, StatusCode::CREATED);
    let task_id = task_json.get("id").unwrap().as_str().unwrap();

    let trade_body = json!({
        "taskId": task_id
    });

    let (status, json) =
        make_authenticated_post_request(&access_token, "/api/trades", trade_body).await;

    assert_eq!(status, StatusCode::CREATED);
    assert!(json.get("id").is_some());
    assert_eq!(json.get("amount").unwrap(), 20);
    assert!(json.get("createdAt").is_some());

    let tradable_item = json.get("tradableItem").unwrap();
    assert_eq!(tradable_item.get("type").unwrap(), "Task");
    assert_eq!(tradable_item.get("id").unwrap(), task_id);
    assert_eq!(tradable_item.get("name").unwrap(), "File taxes");
    assert_eq!(tradable_item.get("completedAt").unwrap().is_string(), true);
}

#[tokio::test]
async fn test_create_trade_with_habit_success() {
    let email = generate_email_from_fn!(test_create_trade_with_habit_success);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    // First create a habit
    let habit_body = json!({
        "name": "Test Habit",
        "description": "A test habit for trading"
    });

    let (status, habit_json) =
        make_authenticated_post_request(&access_token, "/api/habits", habit_body).await;
    assert_eq!(status, StatusCode::CREATED);
    let habit_id = habit_json.get("id").unwrap().as_str().unwrap();

    // Now create a trade with the habit
    let trade_body = json!({
        "habitId": habit_id
    });

    let (status, json) =
        make_authenticated_post_request(&access_token, "/api/trades", trade_body).await;

    assert_eq!(status, StatusCode::CREATED);
    assert!(json.get("id").is_some());
    assert_eq!(json.get("amount").unwrap(), 1000);
    assert!(json.get("createdAt").is_some());

    let tradable_item = json.get("tradableItem").unwrap();
    assert_eq!(tradable_item.get("type").unwrap(), "Habit");
    assert_eq!(tradable_item.get("id").unwrap(), habit_id);
    assert_eq!(tradable_item.get("name").unwrap(), "Test Habit");
    assert_eq!(
        tradable_item.get("description").unwrap(),
        "A test habit for trading"
    );
}

#[tokio::test]
async fn test_create_trade_with_reward_success() {
    let email = generate_email_from_fn!(test_create_trade_with_reward_success);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    // First create a reward
    let reward_body = json!({
        "name": "Test Reward",
        "description": "A test reward for trading",
        "maxDailyFrequency": 3.5
    });

    let (status, reward_json) =
        make_authenticated_post_request(&access_token, "/api/rewards", reward_body).await;
    assert_eq!(status, StatusCode::CREATED);
    let reward_id = reward_json.get("id").unwrap().as_str().unwrap();

    // Now create a trade with the reward
    let trade_body = json!({
        "rewardId": reward_id
    });

    let (status, json) =
        make_authenticated_post_request(&access_token, "/api/trades", trade_body).await;

    assert_eq!(status, StatusCode::CREATED);
    assert!(json.get("id").is_some());
    assert_eq!(json.get("amount").unwrap(), 1000);
    assert!(json.get("createdAt").is_some());

    let tradable_item = json.get("tradableItem").unwrap();
    assert_eq!(tradable_item.get("type").unwrap(), "Reward");
    assert_eq!(tradable_item.get("id").unwrap(), reward_id);
    assert_eq!(tradable_item.get("name").unwrap(), "Test Reward");
    assert_eq!(
        tradable_item.get("description").unwrap(),
        "A test reward for trading"
    );
    assert_eq!(tradable_item.get("maxDailyFrequency").unwrap(), 3.5);
}

#[tokio::test]
async fn test_create_trade_with_multiple_sources() {
    let email = generate_email_from_fn!(test_create_trade_with_multiple_sources);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let task_body = json!({
        "name": "Test Task",
        "description": "A test task"
    });
    let (_, task_json) =
        make_authenticated_post_request(&access_token, "/api/tasks", task_body).await;
    let task_id = task_json.get("id").unwrap().as_str().unwrap();

    // Create a habit
    let habit_body = json!({
        "name": "Test Habit",
        "description": "A test habit"
    });
    let (_, habit_json) =
        make_authenticated_post_request(&access_token, "/api/habits", habit_body).await;
    let habit_id = habit_json.get("id").unwrap().as_str().unwrap();

    // Create a reward
    let reward_body = json!({
        "name": "Test Reward",
        "description": "A test reward"
    });
    let (_, reward_json) =
        make_authenticated_post_request(&access_token, "/api/rewards", reward_body).await;
    let reward_id = reward_json.get("id").unwrap().as_str().unwrap();

    // Try to create a trade with multiple sources
    let trade_body = json!({
        "taskId": task_id,
        "habitId": habit_id,
        "rewardId": reward_id
    });

    let (status, json) =
        make_authenticated_post_request(&access_token, "/api/trades", trade_body).await;

    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert!(json.get("errors").is_some());

    let errors = json.get("errors").unwrap().as_array().unwrap();
    assert_eq!(errors.len(), 1);

    let error = errors.first().unwrap();
    assert_eq!(
        error.get("message").unwrap(),
        &Value::String(
            "Validation Error: Must have exactly one of `task_id`, `habit_id`, or `reward_id`"
                .to_string()
        )
    );
    assert_eq!(
        error.get("code").unwrap(),
        &Value::String("BAD_USER_INPUT".to_string())
    );
}

#[tokio::test]
async fn test_create_trade_with_neither_habit_nor_reward() {
    let email = generate_email_from_fn!(test_create_trade_with_neither_habit_nor_reward);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    // Try to create a trade with neither habit nor reward
    let trade_body = json!({});

    let (status, json) =
        make_authenticated_post_request(&access_token, "/api/trades", trade_body).await;

    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert!(json.get("errors").is_some());

    let errors = json.get("errors").unwrap().as_array().unwrap();
    assert_eq!(errors.len(), 1);

    let error = errors.first().unwrap();
    assert_eq!(
        error.get("message").unwrap(),
        &Value::String(
            "Validation Error: Must have exactly one of `task_id`, `habit_id`, or `reward_id`"
                .to_string()
        )
    );
    assert_eq!(
        error.get("code").unwrap(),
        &Value::String("BAD_USER_INPUT".to_string())
    );
}

#[tokio::test]
async fn test_create_trade_without_authentication() {
    let trade_body = json!({
        "habitId": "079d9887-79f9-4bdf-a341-2d5990a694e1"
    });

    let (status, _) = make_unauthenticated_post_request("/api/trades", trade_body).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn test_create_trade_with_nonexistent_task() {
    let email = generate_email_from_fn!(test_create_trade_with_nonexistent_task);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let trade_body = json!({
        "taskId": "2d452d8f-f87a-4d6b-b16a-acdfcbea1aaa"
    });

    let (status, json) =
        make_authenticated_post_request(&access_token, "/api/trades", trade_body).await;

    assert_eq!(status, StatusCode::INTERNAL_SERVER_ERROR);
    let errors = json.get("errors").unwrap().as_array().unwrap();
    assert_eq!(errors.len(), 1);
    assert_eq!(
        errors[0].get("message").unwrap(),
        &Value::String("An unexpected internal server error occurred.".to_string())
    );
}

#[tokio::test]
async fn test_create_trade_with_nonexistent_habit() {
    let email = generate_email_from_fn!(test_create_trade_with_nonexistent_habit);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    // Try to create a trade with a nonexistent habit ID
    let trade_body = json!({
        "habitId": "2d452d8f-f87a-4d6b-b16a-acdfcbea1fff"
    });

    let (status, json) =
        make_authenticated_post_request(&access_token, "/api/trades", trade_body).await;

    assert_eq!(status, StatusCode::INTERNAL_SERVER_ERROR);
    assert!(json.get("errors").is_some());

    let errors = json.get("errors").unwrap().as_array().unwrap();
    assert_eq!(errors.len(), 1);

    let error = errors.first().unwrap();
    assert_eq!(
        error.get("message").unwrap(),
        &Value::String("An unexpected internal server error occurred.".to_string())
    );
    assert_eq!(
        error.get("code").unwrap(),
        &Value::String("INTERNAL_SERVER_ERROR".to_string())
    );
}

#[tokio::test]
async fn test_create_trade_with_nonexistent_reward() {
    let email = generate_email_from_fn!(test_create_trade_with_nonexistent_reward);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    // Try to create a trade with a nonexistent reward ID
    let trade_body = json!({
        "rewardId": "e1633515-d8b9-4ae2-bc93-5f2b3b0956fc"
    });

    let (status, json) =
        make_authenticated_post_request(&access_token, "/api/trades", trade_body).await;

    assert_eq!(status, StatusCode::INTERNAL_SERVER_ERROR);
    assert!(json.get("errors").is_some());

    let errors = json.get("errors").unwrap().as_array().unwrap();
    assert_eq!(errors.len(), 1);

    let error = errors.first().unwrap();
    assert_eq!(
        error.get("message").unwrap(),
        &Value::String("An unexpected internal server error occurred.".to_string())
    );
    assert_eq!(
        error.get("code").unwrap(),
        &Value::String("INTERNAL_SERVER_ERROR".to_string())
    );
}
