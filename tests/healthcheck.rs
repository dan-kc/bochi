mod common;

use common::SharedTestServer;

#[test]
fn test_healthcheck() {
    let server = SharedTestServer::get();

    let response = ureq::get(&format!("{}/health", server.base_url))
        .call()
        .expect("Failed to call health endpoint");

    assert_eq!(response.status(), 200, "Expected status code 200");

    let body = response
        .into_string()
        .expect("Failed to read response body");
    let json: serde_json::Value = serde_json::from_str(&body).expect("Failed to parse JSON");

    assert_eq!(
        json.get("healthy").and_then(|v| v.as_bool()),
        Some(true),
        "Response should indicate healthy status"
    );
}

