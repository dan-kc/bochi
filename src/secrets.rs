use aws_config::{BehaviorVersion, Region};
use aws_sdk_secretsmanager::Client;

#[derive(Debug, Clone, Copy)]
pub enum State {
    DEV,
    TEST,
    PROD,
}

pub fn get_state() -> State {
    let state = std::env::var("STATE");
    if state.is_err() {
        return State::PROD;
    }

    let state = state.unwrap();
    let state = state.as_str();
    if state.eq("DEV") {
        return State::DEV;
    }
    if state.eq("TEST") {
        return State::TEST;
    }
    if state.eq("PROD") {
        return State::PROD;
    }

    panic!("Unexpected state: {}", state)
}

pub struct SecretsManager {
    client: Option<Client>,
    state: State,
}

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("An unexpected internal server error occurred. {0}")]
    Internal(String),
    #[error("Unknown secret requested {0}")]
    UnknownSecret(String),
}

impl SecretsManager {
    pub async fn new() -> Self {
        let state = get_state();

        let client = match state {
            State::PROD => {
                // Use real AWS Secrets Manager for production
                let config_loader = aws_config::defaults(BehaviorVersion::latest())
                    .region(Region::new("eu-west-1"));
                let config = config_loader.load().await;
                Some(Client::new(&config))
            }
            State::DEV | State::TEST => None,
        };

        SecretsManager { client, state }
    }

    pub async fn get_secret(&self, secret_name: &str) -> Result<String, Error> {
        match self.state {
            State::DEV => {
                // Use fixed values for DEV environment
                match secret_name {
                    "db-user" => Ok("user".to_string()),
                    "db-password" => Ok("password".to_string()),
                    "db-host" => Ok("localhost".to_string()),
                    "db-name" => Ok("habit_market".to_string()),
                    "eddsa-public-key" => Ok("-----BEGIN PUBLIC KEY-----\nMCowBQYDK2VwAyEAgqOy39tZbw5kBo7F7+BIJfcemdiIbQhirZW4NV8lC2I=\n-----END PUBLIC KEY-----".to_string()),
                    "eddsa-private-key" => Ok("-----BEGIN PRIVATE KEY-----\nMC4CAQAwBQYDK2VwBCIEIL9ijTozRgbWNk4WlZosj9MibQ9s8gwcEOqk0KxQxxGd\n-----END PRIVATE KEY-----".to_string()),
                    _ => { Err(Error::UnknownSecret(secret_name.to_string()))}
                }
            }
            State::TEST => {
                // Use fixed values for TEST environment
                match secret_name {
                    "db-user" => Ok("user".to_string()),
                    "db-password" => Ok("password".to_string()),
                    "db-host" => Ok("localhost".to_string()),
                    "db-name" => Ok("test_habit_market".to_string()),
                    "eddsa-public-key" => Ok("-----BEGIN PUBLIC KEY-----\nMCowBQYDK2VwAyEAgqOy39tZbw5kBo7F7+BIJfcemdiIbQhirZW4NV8lC2I=\n-----END PUBLIC KEY-----".to_string()),
                    "eddsa-private-key" => Ok("-----BEGIN PRIVATE KEY-----\nMC4CAQAwBQYDK2VwBCIEIL9ijTozRgbWNk4WlZosj9MibQ9s8gwcEOqk0KxQxxGd\n-----END PRIVATE KEY-----".to_string()),
                    _ => { Err(Error::UnknownSecret(secret_name.to_string()))}
                }
            }
            State::PROD => {
                // Use real AWS Secrets Manager for production
                if let Some(ref client) = self.client {
                    client
                        .get_secret_value()
                        .secret_id(secret_name)
                        .send()
                        .await
                        .map_err(|e| {
                            Error::Internal(format!(
                                "Failed to get secret '{}': {}",
                                secret_name, e
                            ))
                        })?
                        .secret_string()
                        .map(|s| s.to_string())
                        .ok_or_else(|| {
                            Error::Internal(format!("Failed to get secret '{}'", secret_name))
                        })
                } else {
                    Err(Error::UnknownSecret(secret_name.to_string()))
                }
            }
        }
    }
}
