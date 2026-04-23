use axum::body::Body;
use axum::http::{Request, StatusCode};
use http::Method;
use http_body_util::BodyExt;
use serde_json::json;
use tofustash_backend::router;
use tower::ServiceExt;

pub async fn register_and_get_refresh_token(email: &str, password: &str) -> Result<String, String> {
    let router = router::router().await;

    let request_body = json!({
        "email": email,
        "password": password
    });

    let response = router
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/auth/register")
                .header(http::header::CONTENT_TYPE, "application/json")
                .body(Body::from(request_body.to_string()))
                .unwrap(),
        )
        .await
        .map_err(|e| format!("Failed to register: {}", e))?;

    if response.status() != StatusCode::OK && response.status() != StatusCode::CONFLICT {
        return Err(format!(
            "Registration failed with status: {}",
            response.status()
        ));
    }

    let response_body_bytes = response
        .into_body()
        .collect()
        .await
        .map_err(|e| format!("Failed to read response body: {}", e))?
        .to_bytes();

    let json: serde_json::Value = serde_json::from_slice(&response_body_bytes)
        .map_err(|e| format!("Failed to parse JSON: {}", e))?;

    json.get("refreshToken")
        .and_then(|v| v.as_str())
        .map(|s| s.to_string())
        .ok_or_else(|| "No refreshToken in response".to_string())
}

#[allow(dead_code)]
pub fn create_password_of_length(len: usize) -> String {
    "a".repeat(len)
}

#[macro_export]
macro_rules! generate_email_from_fn {
    ($fn_name:path) => {{
        // $fn_name will be parsed as a path (e.g., `my_module::my_function`)
        // stringify! will convert that path into a string literal.
        let full_name = stringify!($fn_name);
        format!("{}@test.com", full_name)
    }};
    ($fn_name:ident) => {{
        // This variant handles simple identifiers (functions in the current scope)
        let full_name = stringify!($fn_name);
        format!("{}@test.com", full_name)
    }};
}

pub async fn register_user(email: &str, password: &str) {
    let router = router::router().await;

    let request_body = json!({
        "email": email,
        "password": password
    });

    let _ = router
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/auth/register")
                .header(http::header::CONTENT_TYPE, "application/json")
                .body(Body::from(request_body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
}

pub async fn get_access_token_for_user(email: &str, password: &str) -> String {
    let router = router::router().await;

    let request_body = json!({
        "email": email,
        "password": password
    });

    let response = router
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/auth/login")
                .header(http::header::CONTENT_TYPE, "application/json")
                .body(Body::from(request_body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    let response_body_bytes = response
        .into_body()
        .collect()
        .await
        .expect("Failed to read response body")
        .to_bytes();
    let json: serde_json::Value =
        serde_json::from_slice(&response_body_bytes).expect("Failed to parse JSON response body");

    json.get("accessToken")
        .and_then(|v| v.as_str())
        .unwrap_or_else(|| {
            eprintln!(
                "Login response body: {}",
                serde_json::to_string_pretty(&json).unwrap()
            );
            panic!("Login response should contain accessToken");
        })
        .to_string()
}

pub async fn make_authenticated_get_request(
    access_token: &str,
    path: &str,
) -> (StatusCode, serde_json::Value) {
    let router = router::router().await;

    let response = router
        .oneshot(
            Request::builder()
                .method(Method::GET)
                .uri(path)
                .header(
                    http::header::AUTHORIZATION,
                    format!("Bearer {}", access_token),
                )
                .body(Body::empty())
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

    let json: serde_json::Value = if response_body_bytes.is_empty() {
        serde_json::Value::Null
    } else {
        serde_json::from_slice(&response_body_bytes).expect("Failed to parse JSON response body")
    };

    (status, json)
}

pub async fn make_authenticated_post_request(
    access_token: &str,
    path: &str,
    body: serde_json::Value,
) -> (StatusCode, serde_json::Value) {
    let router = router::router().await;

    let response = router
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri(path)
                .header(http::header::CONTENT_TYPE, "application/json")
                .header(
                    http::header::AUTHORIZATION,
                    format!("Bearer {}", access_token),
                )
                .body(Body::from(body.to_string()))
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

    let json: serde_json::Value = if response_body_bytes.is_empty() {
        serde_json::Value::Null
    } else {
        serde_json::from_slice(&response_body_bytes).expect("Failed to parse JSON response body")
    };

    (status, json)
}

pub async fn make_unauthenticated_get_request(path: &str) -> (StatusCode, serde_json::Value) {
    let router = router::router().await;

    let response = router
        .oneshot(
            Request::builder()
                .method(Method::GET)
                .uri(path)
                .body(Body::empty())
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

    let json: serde_json::Value = if response_body_bytes.is_empty() {
        serde_json::Value::Null
    } else {
        serde_json::from_slice(&response_body_bytes).expect("Failed to parse JSON response body")
    };

    (status, json)
}

pub async fn make_unauthenticated_post_request(
    path: &str,
    body: serde_json::Value,
) -> (StatusCode, serde_json::Value) {
    let router = router::router().await;

    let response = router
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri(path)
                .header(http::header::CONTENT_TYPE, "application/json")
                .body(Body::from(body.to_string()))
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

    let json: serde_json::Value = if response_body_bytes.is_empty() {
        serde_json::Value::Null
    } else {
        serde_json::from_slice(&response_body_bytes).expect("Failed to parse JSON response body")
    };

    (status, json)
}
