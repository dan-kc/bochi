use aws_config::{BehaviorVersion, Region};
use aws_sdk_secretsmanager::Client;

pub struct SecretsManager {
    client: Client,
}

impl SecretsManager {
    pub async fn new() -> Self {
        let mut config_loader =
            aws_config::defaults(BehaviorVersion::latest()).region(Region::new("eu-west-1"));

        // Check for LocalStack endpoint
        if let Ok(endpoint_url) = std::env::var("AWS_ENDPOINT_URL_SECRETSMANAGER") {
            config_loader = config_loader.endpoint_url(endpoint_url);
        }

        let config = config_loader.load().await;
        let client = Client::new(&config);

        SecretsManager { client }
    }

    pub async fn get_secret(&self, secret_name: &str) -> Result<String, String> {
        // Check for secrets prefix
        let secrets_prefix = std::env::var("AWS_SECRETS_PREFIX").unwrap_or("".to_string());
        let prefixed_secret_name = secrets_prefix + secret_name;

        self.client
            .get_secret_value()
            .secret_id(&prefixed_secret_name)
            .send()
            .await
            .map_err(|e| format!("Failed to get secret '{}': {}", prefixed_secret_name, e))?
            .secret_string()
            .map(|s| s.to_string())
            .ok_or_else(|| format!("Secret '{}' has no string value", prefixed_secret_name))
    }
}
