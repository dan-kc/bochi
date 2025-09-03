use std::io::Read;
use std::process::{Child, Command, Stdio};
use std::sync::{Arc, Mutex, OnceLock};
use std::thread;
use std::time::{Duration, Instant};

static SHARED_SERVER: OnceLock<Arc<Mutex<TestServer>>> = OnceLock::new();

pub struct TestServer {
    pub process: Child,
    pub base_url: String,
}

pub struct SharedTestServer {
    pub base_url: String,
}

impl TestServer {
    pub fn start() -> Self {
        // Build the binary if needed
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

        // Start the server
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

        // Wait for server to be ready
        let start = Instant::now();
        let timeout = Duration::from_secs(30);
        let base_url = "http://127.0.0.1:8080".to_string();

        while start.elapsed() < timeout {
            // Check if server process is still running
            match server.try_wait() {
                Ok(Some(status)) => {
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
                    // Process is still running, check if it's ready
                    thread::sleep(Duration::from_millis(500));

                    if ureq::get(&format!("{}/health", base_url)).call().is_ok() {
                        return TestServer {
                            process: server,
                            base_url,
                        };
                    }
                }
                Err(e) => {
                    panic!("Error checking server status: {}", e);
                }
            }
        }

        server.kill().ok();
        panic!("Server did not start within timeout period");
    }
}

impl SharedTestServer {
    #[allow(dead_code)]
    pub fn get() -> Self {
        let server_arc = SHARED_SERVER.get_or_init(|| {
            let server = TestServer::start();
            Arc::new(Mutex::new(server))
        });

        let server = server_arc.lock().unwrap();
        SharedTestServer {
            base_url: server.base_url.clone(),
        }
    }

    #[allow(dead_code)]
    pub fn post_json(
        &self,
        path: &str,
        json: serde_json::Value,
    ) -> Result<ureq::Response, ureq::Error> {
        ureq::post(&format!("{}{}", self.base_url, path))
            .set("Content-Type", "application/json")
            .send_string(&json.to_string())
    }
}

impl Drop for TestServer {
    fn drop(&mut self) {
        self.process.kill().ok();
    }
}

#[allow(dead_code)]
pub fn create_password_of_length(len: usize) -> String {
    "a".repeat(len)
}
