use crate::common::{
    get_access_token_for_user, make_authenticated_post_request, make_unauthenticated_post_request,
    register_user,
};
use crate::generate_email_from_fn;
use axum::http::StatusCode;
use serde_json::{json, Value};

#[tokio::test]
async fn test_create_task_success() {
    let email = generate_email_from_fn!(test_create_task_success);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let body = json!({
        "name": "Test Task",
        "description": "A test task description",
        "habit": false
    });

    let (status, json) = make_authenticated_post_request(&access_token, "/api/tasks", body).await;

    assert_eq!(status, StatusCode::CREATED);
    assert!(json.get("id").is_some());
    assert_eq!(json.get("name").unwrap().as_str().unwrap(), "Test Task");
    assert!(json.get("createdAt").is_some());
    assert_eq!(json.get("deletedAt").unwrap(), &Value::Null);
    assert_eq!(
        json.get("description").unwrap().as_str().unwrap(),
        "A test task description"
    );
    assert_eq!(json.get("hiddenUntil").unwrap(), &Value::Null);
    assert_eq!(json.get("dueBy").unwrap(), &Value::Null);
    assert_eq!(json.get("minDailyFrequency").unwrap(), &Value::Null);
    assert_eq!(json.get("habit").unwrap(), false);
}

#[tokio::test]
async fn test_create_due_task_success() {
    let email = generate_email_from_fn!(test_create_due_task_success);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let body = json!({
        "name": "Test Task",
        "description": "A test task description",
        "dueBy": "2028-12-25T23:59:59",
        "habit": false
    });

    let (status, json) = make_authenticated_post_request(&access_token, "/api/tasks", body).await;

    assert_eq!(status, StatusCode::CREATED);
    assert_eq!(json.get("dueBy").unwrap(), "2028-12-25T23:59:59");
}

#[tokio::test]
async fn test_create_task_with_optional_fields() {
    let email = generate_email_from_fn!(test_create_task_with_optional_fields);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let body = json!({
        "name": "Task with dates",
        "description": "Task with optional dates",
        "hiddenUntil": "2028-12-16T00:33:08",
        "dueBy": "2028-12-25T23:59:59",
        "habit": false
    });

    let (status, json) = make_authenticated_post_request(&access_token, "/api/tasks", body).await;

    assert_eq!(status, StatusCode::CREATED);
    assert_eq!(json.get("hiddenUntil").unwrap(), "2028-12-16T00:33:08");
    assert_eq!(json.get("dueBy").unwrap(), "2028-12-25T23:59:59");
}

#[tokio::test]
async fn test_create_task_validation_name_too_long() {
    let email = generate_email_from_fn!(test_create_task_validation_name_too_long);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let long_name = "a".repeat(101);
    let body = json!({
        "name": long_name,
        "description": "Test description",
        "habit": false
    });

    let (status, json) = make_authenticated_post_request(&access_token, "/api/tasks", body).await;

    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert!(json.get("errors").is_some());

    let errors = json.get("errors").unwrap().as_array().unwrap();
    assert_eq!(errors.len(), 1);

    let error = errors.first().unwrap();
    assert_eq!(
        error.get("message").unwrap(),
        &Value::String(
            "Validation Error: Please provide a name between 1 and 100 characters long. Your current name is 101 characters.".to_string()
        )
    );
    assert_eq!(
        error.get("code").unwrap(),
        &Value::String("BAD_USER_INPUT".to_string())
    );
}

#[tokio::test]
async fn test_create_task_validation_description_too_long() {
    let email = generate_email_from_fn!(test_create_task_validation_description_too_long);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let long_description = "a".repeat(10001);
    let body = json!({
        "name": "Test Task",
        "description": long_description,
        "habit": false
    });

    let (status, json) = make_authenticated_post_request(&access_token, "/api/tasks", body).await;

    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert!(json.get("errors").is_some());

    let errors = json.get("errors").unwrap().as_array().unwrap();
    assert_eq!(errors.len(), 1);

    let error = errors.first().unwrap();
    assert_eq!(
        error.get("message").unwrap(),
        &Value::String(
            "Validation Error: Description is too long (10001 characters), max 10,000.".to_string()
        )
    );
    assert_eq!(
        error.get("code").unwrap(),
        &Value::String("BAD_USER_INPUT".to_string())
    );
}

#[tokio::test]
async fn test_create_task_without_authentication() {
    let body = json!({
        "name": "Test Task",
        "description": "Test description",
        "habit": false
    });

    let (status, _) = make_unauthenticated_post_request("/api/tasks", body).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn test_create_task_minimum_valid_input() {
    let email = generate_email_from_fn!(test_create_task_minimum_valid_input);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let body = json!({
        "name": "T",
        "description": "",
        "habit": false
    });

    let (status, json) = make_authenticated_post_request(&access_token, "/api/tasks", body).await;

    assert_eq!(status, StatusCode::CREATED);
    assert_eq!(json.get("name").unwrap().as_str().unwrap(), "T");
    assert_eq!(json.get("description").unwrap().as_str().unwrap(), "");
}

#[tokio::test]
async fn test_create_task_maximum_valid_input() {
    let email = generate_email_from_fn!(test_create_task_maximum_valid_input);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let max_name = "a".repeat(100);
    let max_description = "b".repeat(10000);

    let body = json!({
        "name": max_name,
        "description": max_description,
        "minDailyFrequency": 100.0,
        "habit": true
    });

    let (status, json) = make_authenticated_post_request(&access_token, "/api/tasks", body).await;

    assert_eq!(status, StatusCode::CREATED);
    assert_eq!(json.get("name").unwrap(), &Value::String(max_name));
    assert_eq!(
        json.get("description").unwrap(),
        &Value::String(max_description)
    );
    assert_eq!(json.get("minDailyFrequency").unwrap(), 100.0);
    assert_eq!(json.get("habit").unwrap(), true);
}

#[tokio::test]
async fn test_create_task_hidden_until_in_past() {
    let email = generate_email_from_fn!(test_create_task_hidden_until_in_past);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let body = json!({
        "name": "test name",
        "description": "test description",
        "hiddenUntil": "2022-12-25T23:59:59",
        "habit": false
    });

    let (status, json) = make_authenticated_post_request(&access_token, "/api/tasks", body).await;

    assert_eq!(status, StatusCode::BAD_REQUEST);
    let errors = json.get("errors").unwrap().as_array().unwrap();
    assert_eq!(errors.len(), 1);

    let error = errors.first().unwrap();
    assert_eq!(
        error.get("message").unwrap(),
        &Value::String(
            "Validation Error: The 'hidden until' date (2022-12-25 23:59:59) has already passed or is the current moment. Please select a future date.".to_string()
        )
    );
    assert_eq!(
        error.get("code").unwrap(),
        &Value::String("BAD_USER_INPUT".to_string())
    );
}

#[tokio::test]
async fn test_create_task_due_by_in_past() {
    let email = generate_email_from_fn!(test_create_task_due_by_in_past);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let body = json!({
        "name": "test name",
        "description": "test description",
        "dueBy": "2022-12-25T23:59:59",
        "habit": false
    });

    let (status, json) = make_authenticated_post_request(&access_token, "/api/tasks", body).await;

    assert_eq!(status, StatusCode::BAD_REQUEST);
    let errors = json.get("errors").unwrap().as_array().unwrap();
    assert_eq!(errors.len(), 1);

    let error = errors.first().unwrap();
    assert_eq!(
        error.get("message").unwrap(),
        &Value::String(
            "Validation Error: The 'due_by' date (2022-12-25 23:59:59) has already passed or is the current moment. Please select a future date.".to_string()
        )
    );
    assert_eq!(
        error.get("code").unwrap(),
        &Value::String("BAD_USER_INPUT".to_string())
    );
}

#[tokio::test]
async fn test_create_task_name_empty_string() {
    let email = generate_email_from_fn!(test_create_task_name_empty_string);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let body = json!({
        "name": "",
        "description": "Test description",
        "habit": false
    });

    let (status, json) = make_authenticated_post_request(&access_token, "/api/tasks", body).await;

    assert_eq!(status, StatusCode::BAD_REQUEST);
    let errors = json.get("errors").unwrap().as_array().unwrap();
    assert_eq!(errors.len(), 1);

    let error = errors.first().unwrap();
    assert_eq!(
        error.get("message").unwrap(),
        &Value::String(
            "Validation Error: Please provide a name between 1 and 100 characters long. Your current name is 0 characters.".to_string()
        )
    );
    assert_eq!(
        error.get("code").unwrap(),
        &Value::String("BAD_USER_INPUT".to_string())
    );
}

#[tokio::test]
async fn test_create_task_with_min_daily_frequency() {
    let email = generate_email_from_fn!(test_create_task_with_min_daily_frequency);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let body = json!({
        "name": "Test Task",
        "description": "A test task description",
        "minDailyFrequency": 5.5,
        "habit": true
    });

    let (status, json) = make_authenticated_post_request(&access_token, "/api/tasks", body).await;

    assert_eq!(status, StatusCode::CREATED);
    assert_eq!(json.get("minDailyFrequency").unwrap(), 5.5);
    assert_eq!(json.get("habit").unwrap(), true);
}

#[tokio::test]
async fn test_create_task_min_daily_frequency_negative() {
    let email = generate_email_from_fn!(test_create_task_min_daily_frequency_negative);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let body = json!({
        "name": "test name",
        "description": "test description",
        "minDailyFrequency": -1.0,
        "habit": true
    });

    let (status, json) = make_authenticated_post_request(&access_token, "/api/tasks", body).await;

    assert_eq!(status, StatusCode::BAD_REQUEST);
    let errors = json.get("errors").unwrap().as_array().unwrap();
    assert_eq!(errors.len(), 1);

    let error = errors.first().unwrap();
    assert_eq!(
        error.get("message").unwrap(),
        &Value::String(
            "Validation Error: The 'min_daily_frequency must be between 0 and 100. You sent -1."
                .to_string()
        )
    );
    assert_eq!(
        error.get("code").unwrap(),
        &Value::String("BAD_USER_INPUT".to_string())
    );
}

#[tokio::test]
async fn test_create_task_min_daily_frequency_too_large() {
    let email = generate_email_from_fn!(test_create_task_min_daily_frequency_too_large);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let body = json!({
        "name": "test name",
        "description": "test description",
        "minDailyFrequency": 101.0,
        "habit": true
    });

    let (status, json) = make_authenticated_post_request(&access_token, "/api/tasks", body).await;

    assert_eq!(status, StatusCode::BAD_REQUEST);
    let errors = json.get("errors").unwrap().as_array().unwrap();
    assert_eq!(errors.len(), 1);

    let error = errors.first().unwrap();
    assert_eq!(
        error.get("message").unwrap(),
        &Value::String(
            "Validation Error: The 'min_daily_frequency must be between 0 and 100. You sent 101."
                .to_string()
        )
    );
    assert_eq!(
        error.get("code").unwrap(),
        &Value::String("BAD_USER_INPUT".to_string())
    );
}

#[tokio::test]
async fn test_create_task_min_daily_frequency_zero() {
    let email = generate_email_from_fn!(test_create_task_min_daily_frequency_zero);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let body = json!({
        "name": "Test Task",
        "description": "Test description",
        "minDailyFrequency": 0.0,
        "habit": true
    });

    let (status, json) = make_authenticated_post_request(&access_token, "/api/tasks", body).await;

    assert_eq!(status, StatusCode::CREATED);
    assert_eq!(json.get("minDailyFrequency").unwrap(), 0.0);
}

#[tokio::test]
async fn test_create_task_min_daily_frequency_boundary() {
    let email = generate_email_from_fn!(test_create_task_min_daily_frequency_boundary);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let body = json!({
        "name": "Test Task",
        "description": "Test description",
        "minDailyFrequency": 100.0,
        "habit": true
    });

    let (status, json) = make_authenticated_post_request(&access_token, "/api/tasks", body).await;

    assert_eq!(status, StatusCode::CREATED);
    assert_eq!(json.get("minDailyFrequency").unwrap(), 100.0);
}

#[tokio::test]
async fn test_create_habit_with_both_due_by_and_min_daily_frequency() {
    let email = generate_email_from_fn!(test_create_habit_with_both_due_by_and_min_daily_frequency);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let body = json!({
        "name": "Test Habit",
        "description": "Test description",
        "dueBy": "2028-12-25T23:59:59",
        "minDailyFrequency": 5.0,
        "habit": true
    });

    let (status, json) = make_authenticated_post_request(&access_token, "/api/tasks", body).await;

    assert_eq!(status, StatusCode::CREATED);
    assert_eq!(json.get("dueBy").unwrap(), "2028-12-25T23:59:59");
    assert_eq!(json.get("minDailyFrequency").unwrap(), 5.0);
    assert_eq!(json.get("habit").unwrap(), true);
}

#[tokio::test]
async fn test_create_task_with_hidden_until_and_min_daily_frequency() {
    let email = generate_email_from_fn!(test_create_task_with_hidden_until_and_min_daily_frequency);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let body = json!({
        "name": "Task with hidden and frequency",
        "description": "Task with hidden_until and min_daily_frequency",
        "hiddenUntil": "2028-12-16T00:33:08",
        "minDailyFrequency": 10.0,
        "habit": true
    });

    let (status, json) = make_authenticated_post_request(&access_token, "/api/tasks", body).await;

    assert_eq!(status, StatusCode::CREATED);
    assert_eq!(json.get("hiddenUntil").unwrap(), "2028-12-16T00:33:08");
    assert_eq!(json.get("minDailyFrequency").unwrap(), 10.0);
}

#[tokio::test]
async fn test_create_habit_task_success() {
    let email = generate_email_from_fn!(test_create_habit_task_success);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let body = json!({
        "name": "Daily Exercise",
        "description": "Do 30 minutes of exercise",
        "habit": true
    });

    let (status, json) = make_authenticated_post_request(&access_token, "/api/tasks", body).await;

    assert_eq!(status, StatusCode::CREATED);
    assert!(json.get("id").is_some());
    assert_eq!(json.get("name").unwrap().as_str().unwrap(), "Daily Exercise");
    assert_eq!(json.get("habit").unwrap(), true);
    assert_eq!(json.get("minDailyFrequency").unwrap(), &Value::Null);
}

#[tokio::test]
async fn test_create_habit_task_with_frequency() {
    let email = generate_email_from_fn!(test_create_habit_task_with_frequency);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let body = json!({
        "name": "Drink Water",
        "description": "Stay hydrated",
        "habit": true,
        "minDailyFrequency": 8.0
    });

    let (status, json) = make_authenticated_post_request(&access_token, "/api/tasks", body).await;

    assert_eq!(status, StatusCode::CREATED);
    assert_eq!(json.get("habit").unwrap(), true);
    assert_eq!(json.get("minDailyFrequency").unwrap(), 8.0);
}

#[tokio::test]
async fn test_create_non_habit_task_with_frequency_fails() {
    let email = generate_email_from_fn!(test_create_non_habit_task_with_frequency_fails);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let body = json!({
        "name": "Regular Task",
        "description": "Not a habit",
        "habit": false,
        "minDailyFrequency": 5.0
    });

    let (status, json) = make_authenticated_post_request(&access_token, "/api/tasks", body).await;

    assert_eq!(status, StatusCode::BAD_REQUEST);
    let errors = json.get("errors").unwrap().as_array().unwrap();
    assert_eq!(errors.len(), 1);

    let error = errors.first().unwrap();
    assert_eq!(
        error.get("message").unwrap(),
        &Value::String(
            "Validation Error: Non-habit tasks cannot have 'min_daily_frequency'. Either set 'habit' to true or remove 'min_daily_frequency'."
                .to_string()
        )
    );
    assert_eq!(
        error.get("code").unwrap(),
        &Value::String("BAD_USER_INPUT".to_string())
    );
}
