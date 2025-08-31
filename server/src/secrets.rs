use aws_config::{BehaviorVersion, Region};
use aws_sdk_secretsmanager::Client;

pub struct SecretsManager {
    client: Client,
}

impl SecretsManager {
    pub async fn new() -> Self {
        let config = aws_config::defaults(BehaviorVersion::latest())
            .region(Region::new("eu-west-1"))
            .load()
            .await;
        let client = Client::new(&config);

        SecretsManager { client }
    }

    pub async fn get_secret(
        &self,
        secret_name: &str,
    ) -> Result<String, String> {
        let response = self
            .client
            .get_secret_value()
            .secret_id(secret_name)
            .send()
            .await
            .map_err(|e| {
                format!("Failed to get secret '{}': {}", secret_name, e)
            })?;

        response
            .secret_string()
            .map(|s| s.to_string())
            .ok_or_else(|| {
                format!("Secret '{}' has no string value", secret_name)
            })
    }
}
