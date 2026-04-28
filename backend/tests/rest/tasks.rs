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
        "name": "Submit invoice",
        "description": "Send the April invoice"
    });

    let (status, json) = make_authenticated_post_request(&access_token, "/api/tasks", body).await;

    assert_eq!(status, StatusCode::CREATED);
    assert!(json.get("id").is_some());
    assert_eq!(
        json.get("name").unwrap().as_str().unwrap(),
        "Submit invoice"
    );
    assert_eq!(
        json.get("description").unwrap().as_str().unwrap(),
        "Send the April invoice"
    );
    assert!(json.get("createdAt").unwrap().is_string());
    assert!(json.get("updatedAt").unwrap().is_string());
    assert_eq!(json.get("deletedAt").unwrap(), &Value::Null);
    assert_eq!(json.get("completedAt").unwrap(), &Value::Null);
    assert_eq!(json.get("difficultyTier").unwrap(), &Value::Null);
    assert_eq!(json.get("durationSeconds").unwrap(), &Value::Null);
    assert_eq!(json.get("skipConsequence").unwrap(), &Value::Null);
    assert_eq!(json.get("dueDate").unwrap(), &Value::Null);
}

#[tokio::test]
async fn test_create_task_with_optional_fields() {
    let email = generate_email_from_fn!(test_create_task_with_optional_fields);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let body = json!({
        "name": "Deep clean kitchen",
        "description": "Finish everything in one pass",
        "difficultyTier": "hard",
        "durationSeconds": 3600,
        "skipConsequence": 4,
        "dueDate": "2026-05-01T09:30:00"
    });

    let (status, json) = make_authenticated_post_request(&access_token, "/api/tasks", body).await;

    assert_eq!(status, StatusCode::CREATED);
    assert_eq!(json.get("difficultyTier").unwrap(), "hard");
    assert_eq!(json.get("durationSeconds").unwrap(), 3600);
    assert_eq!(json.get("skipConsequence").unwrap(), 4);
    assert_eq!(json.get("dueDate").unwrap(), "2026-05-01T09:30:00");
}

#[tokio::test]
async fn test_create_task_validation_skip_consequence_too_high() {
    let email = generate_email_from_fn!(test_create_task_validation_skip_consequence_too_high);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let body = json!({
        "name": "Bad task",
        "description": "",
        "skipConsequence": 6
    });

    let (status, json) = make_authenticated_post_request(&access_token, "/api/tasks", body).await;

    assert_eq!(status, StatusCode::BAD_REQUEST);
    let errors = json.get("errors").unwrap().as_array().unwrap();
    assert_eq!(errors.len(), 1);
    assert_eq!(
        errors[0].get("message").unwrap(),
        &Value::String(
            "Validation Error: The 'skip_consequence' must be between 1 and 5. You sent 6."
                .to_string()
        )
    );
}

#[tokio::test]
async fn test_create_task_without_authentication() {
    let body = json!({
        "name": "Submit invoice",
        "description": "Send the April invoice"
    });

    let (status, _) = make_unauthenticated_post_request("/api/tasks", body).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}
