use std::io::Read;
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, Instant};

#[test]
fn test_healthcheck() {
    // First build the binary if it doesn't exist
    let build_output = Command::new("cargo")
        .args(&["build", "--release"])
        .output()
        .expect("Failed to build binary");

    if !build_output.status.success() {
        panic!(
            "Failed to build project: {}",
            String::from_utf8_lossy(&build_output.stderr)
        );
    }

    // Run the built binary with LocalStack environment variables
    let mut server = Command::new("./target/release/habit-market-backend")
        .env("AWS_SECRETS_PREFIX", "test-")
        .env("AWS_ENDPOINT_URL_SECRETSMANAGER", "http://localhost:4566")
        .env("AWS_ACCESS_KEY_ID", "test")
        .env("AWS_SECRET_ACCESS_KEY", "test")
        .env("AWS_DEFAULT_REGION", "eu-west-1")
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("Failed to start server");

    // Wait for server to start with retry logic
    let start = Instant::now();
    let timeout = Duration::from_secs(30);
    let mut connected = false;

    while start.elapsed() < timeout && !connected {
        // Check if server process is still running
        match server.try_wait() {
            Ok(Some(status)) => {
                // Process has exited, read stderr to understand why
                let mut stderr = String::new();
                if let Some(mut stderr_handle) = server.stderr.take() {
                    stderr_handle.read_to_string(&mut stderr).ok();
                }
                panic!(
                    "Server exited unexpectedly with status: {:?}\nStderr: {}",
                    status, stderr
                );
            }
            Ok(None) => {
                // Process is still running, continue
            }
            Err(e) => {
                panic!("Error checking server status: {}", e);
            }
        }

        thread::sleep(Duration::from_millis(500));

        match ureq::get("http://127.0.0.1:8080/health").call() {
            Ok(response) => {
                assert_eq!(response.status(), 200, "Expected status code 200");

                let body = response
                    .into_string()
                    .expect("Failed to read response body");
                let json: serde_json::Value =
                    serde_json::from_str(&body).expect("Failed to parse JSON");
                assert_eq!(
                    json.get("healthy").and_then(|v| v.as_bool()),
                    Some(true),
                    "Response should indicate healthy status"
                );
                connected = true;
            }
            Err(_) => {
                // Server not ready yet, continue waiting
            }
        }
    }

    if !connected {
        server.kill().ok();
        panic!("Server did not start within timeout period");
    }

    // Clean up
    server.kill().expect("Failed to kill server");
}

