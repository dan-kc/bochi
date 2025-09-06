use crate::common::{unique_email, SharedTestServer};
use serde_json::json;

fn make_authenticated_graphql_request(
    server: &SharedTestServer,
    access_token: &str,
    query: serde_json::Value,
) -> Result<ureq::Response, ureq::Error> {
    ureq::post(&format!("{}/graphql", server.base_url))
        .set("Content-Type", "application/json")
        .set("Authorization", access_token)
        .send_string(&query.to_string())
}

fn get_access_token_for_user(server: &SharedTestServer, email: &str, password: &str) -> String {
    let login_response = server
        .post_json(
            "/auth/login",
            json!({
                "email": email,
                "password": password
            }),
        )
        .expect("Login should succeed");

    let body = login_response
        .into_string()
        .expect("Failed to read login response");
    let json: serde_json::Value = serde_json::from_str(&body).expect("Failed to parse login JSON");

    json.get("accessToken")
        .and_then(|v| v.as_str())
        .expect("Login response should contain accessToken")
        .to_string()
}

#[test]
fn test_create_task_success() {
    let server = SharedTestServer::get();
    let email = unique_email("task");
    let password = "password123";

    // Register user
    let _ = server
        .post_json(
            "/auth/register",
            json!({
                "email": email,
                "password": password
            }),
        )
        .expect("Registration should succeed");

    let access_token = get_access_token_for_user(&server, &email, &password);

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
            }
        }",
        "variables": {
            "input": {
                "name": "Test Task",
                "description": "A test task description",
                "difficultyRank": 5
            }
        }
    });

    let response = make_authenticated_graphql_request(&server, &access_token, query);
    assert!(response.is_ok(), "CreateTask mutation should succeed");

    let response = response.unwrap();
    assert_eq!(response.status(), 200);

    let body = response
        .into_string()
        .expect("Failed to read response body");
    let json: serde_json::Value = serde_json::from_str(&body).expect("Failed to parse JSON");

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
}

#[test]
fn test_create_task_with_optional_fields() {
    let server = SharedTestServer::get();
    let email = unique_email("task_opt");
    let password = "password123";

    // Register user
    let _ = server
        .post_json(
            "/auth/register",
            json!({
                "email": email,
                "password": password
            }),
        )
        .expect("Registration should succeed");

    let access_token = get_access_token_for_user(&server, &email, &password);

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
                "hiddenUntil": "2024-12-16T00:33:08",
                "dueBy": "2024-12-25T23:59:59"
            }
        }
    });

    let response = make_authenticated_graphql_request(&server, &access_token, query);
    assert!(
        response.is_ok(),
        "CreateTask with optional fields should succeed"
    );

    let response = response.unwrap();
    assert_eq!(response.status(), 200);

    let body = response
        .into_string()
        .expect("Failed to read response body");
    let json: serde_json::Value = serde_json::from_str(&body).expect("Failed to parse JSON");

    let task = json.get("data").unwrap().get("createTask").unwrap();
    assert!(task.get("hiddenUntil").is_some());
    assert!(task.get("dueBy").is_some());
}

#[test]
fn test_create_task_validation_name_too_long() {
    let server = SharedTestServer::get();
    let email = unique_email("task_long");
    let password = "password123";

    // Register user
    let _ = server
        .post_json(
            "/auth/register",
            json!({
                "email": email,
                "password": password
            }),
        )
        .expect("Registration should succeed");

    let access_token = get_access_token_for_user(&server, &email, &password);

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

    let response = make_authenticated_graphql_request(&server, &access_token, query);
    assert!(response.is_ok(), "Request should be sent successfully");

    let response = response.unwrap();
    assert_eq!(response.status(), 200);

    let body = response
        .into_string()
        .expect("Failed to read response body");
    let json: serde_json::Value = serde_json::from_str(&body).expect("Failed to parse JSON");

    assert!(
        json.get("errors").is_some(),
        "Response should contain validation errors"
    );
    let errors = json.get("errors").unwrap().as_array().unwrap();
    assert!(!errors.is_empty(), "Should have validation errors");
}

#[test]
fn test_create_task_validation_description_too_long() {
    let server = SharedTestServer::get();
    let email = unique_email("task_desc");
    let password = "password123";

    // Register user
    let _ = server
        .post_json(
            "/auth/register",
            json!({
                "email": email,
                "password": password
            }),
        )
        .expect("Registration should succeed");

    let access_token = get_access_token_for_user(&server, &email, &password);

    let long_description = "a".repeat(3001);
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

    let response = make_authenticated_graphql_request(&server, &access_token, query);
    assert!(response.is_ok(), "Request should be sent successfully");

    let response = response.unwrap();
    assert_eq!(response.status(), 200);

    let body = response
        .into_string()
        .expect("Failed to read response body");
    let json: serde_json::Value = serde_json::from_str(&body).expect("Failed to parse JSON");

    assert!(
        json.get("errors").is_some(),
        "Response should contain validation errors"
    );
}

#[test]
fn test_create_task_validation_difficulty_rank_negative() {
    let server = SharedTestServer::get();
    let email = unique_email("task_neg");
    let password = "password123";

    // Register user
    let _ = server
        .post_json(
            "/auth/register",
            json!({
                "email": email,
                "password": password
            }),
        )
        .expect("Registration should succeed");

    let access_token = get_access_token_for_user(&server, &email, &password);

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

    let response = make_authenticated_graphql_request(&server, &access_token, query);
    assert!(response.is_ok(), "Request should be sent successfully");

    let response = response.unwrap();
    assert_eq!(response.status(), 200);

    let body = response
        .into_string()
        .expect("Failed to read response body");
    let json: serde_json::Value = serde_json::from_str(&body).expect("Failed to parse JSON");

    assert!(
        json.get("errors").is_some(),
        "Response should contain validation errors"
    );
    let errors = json.get("errors").unwrap().as_array().unwrap();
    assert!(
        !errors.is_empty(),
        "Should have validation errors for negative difficulty_rank"
    );
}

#[test]
fn test_create_task_without_authentication() {
    let server = SharedTestServer::get();

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

    let response = ureq::post(&format!("{}/graphql", server.base_url))
        .set("Content-Type", "application/json")
        .send_string(&query.to_string());

    assert!(response.is_err(), "Request without auth should fail");

    if let Err(ureq::Error::Status(code, _)) = response {
        assert_eq!(code, 401, "Should return 401 Unauthorized");
    } else {
        panic!("Expected 401 error");
    }
}

#[test]
fn test_create_task_with_invalid_auth_token() {
    let server = SharedTestServer::get();

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

    let response = ureq::post(&format!("{}/graphql", server.base_url))
        .set("Content-Type", "application/json")
        .set("Authorization", "Bearer invalid-token")
        .send_string(&query.to_string());

    assert!(response.is_err(), "Request with invalid auth should fail");

    if let Err(ureq::Error::Status(code, _)) = response {
        assert_eq!(code, 401, "Should return 401 Unauthorized");
    } else {
        panic!("Expected 401 error");
    }
}

#[test]
fn test_create_task_minimum_valid_input() {
    let server = SharedTestServer::get();
    let email = unique_email("task_min");
    let password = "password123";

    // Register user
    let _ = server
        .post_json(
            "/auth/register",
            json!({
                "email": email,
                "password": password
            }),
        )
        .expect("Registration should succeed");

    let access_token = get_access_token_for_user(&server, &email, &password);

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

    let response = make_authenticated_graphql_request(&server, &access_token, query);
    assert!(response.is_ok(), "Minimal valid input should succeed");

    let response = response.unwrap();
    assert_eq!(response.status(), 200);

    let body = response
        .into_string()
        .expect("Failed to read response body");
    let json: serde_json::Value = serde_json::from_str(&body).expect("Failed to parse JSON");

    assert!(json.get("data").is_some(), "Response should have data");
    let task = json.get("data").unwrap().get("createTask").unwrap();
    assert_eq!(task.get("name").unwrap().as_str().unwrap(), "T");
    assert_eq!(task.get("description").unwrap().as_str().unwrap(), "");
    assert_eq!(task.get("difficultyRank").unwrap().as_i64().unwrap(), 0);
}

#[test]
fn test_create_task_maximum_valid_input() {
    let server = SharedTestServer::get();
    let email = unique_email("task_max");
    let password = "password123";

    // Register user
    let _ = server
        .post_json(
            "/auth/register",
            json!({
                "email": email,
                "password": password
            }),
        )
        .expect("Registration should succeed");

    let access_token = get_access_token_for_user(&server, &email, &password);

    let max_name = "a".repeat(100);
    let max_description = "b".repeat(3000);

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

    let response = make_authenticated_graphql_request(&server, &access_token, query);
    assert!(response.is_ok(), "Maximum valid input should succeed");

    let response = response.unwrap();
    assert_eq!(response.status(), 200);

    let body = response
        .into_string()
        .expect("Failed to read response body");
    let json: serde_json::Value = serde_json::from_str(&body).expect("Failed to parse JSON");

    assert!(json.get("data").is_some(), "Response should have data");
    let task = json.get("data").unwrap().get("createTask").unwrap();
    assert!(
        task.get("id").is_some(),
        "Task should be created with valid max inputs"
    );
}
