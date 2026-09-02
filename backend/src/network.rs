use std::{collections::HashSet, net::IpAddr};

const DEFAULT_BIND_HOST: &str = "0.0.0.0";
const DEFAULT_PORT: &str = "8080";

pub fn listen_address(bind_host: Option<&str>, port: Option<&str>) -> String {
    let bind_host = bind_host
        .filter(|value| !value.trim().is_empty())
        .unwrap_or(DEFAULT_BIND_HOST);
    let port = port
        .filter(|value| !value.trim().is_empty())
        .unwrap_or(DEFAULT_PORT);

    format!("{bind_host}:{port}")
}

#[derive(Clone, Debug)]
pub struct ClientIpPolicy {
    allowed_ips: Option<HashSet<IpAddr>>,
}

impl ClientIpPolicy {
    pub fn from_csv(value: Option<&str>) -> Result<Self, String> {
        let Some(value) = value else {
            return Ok(Self { allowed_ips: None });
        };

        let allowed_ips = value
            .split(',')
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(|value| {
                value.parse::<IpAddr>().map_err(|_| {
                    format!("invalid IP address in SERVER_ALLOWED_CLIENT_IPS: {value}")
                })
            })
            .collect::<Result<HashSet<_>, _>>()?;

        if allowed_ips.is_empty() {
            return Err(
                "SERVER_ALLOWED_CLIENT_IPS must contain at least one IP address".to_string(),
            );
        }

        Ok(Self {
            allowed_ips: Some(allowed_ips),
        })
    }

    pub fn from_environment() -> Result<Self, String> {
        let value = std::env::var("SERVER_ALLOWED_CLIENT_IPS").ok();
        Self::from_csv(value.as_deref())
    }

    pub fn allows(&self, client_ip: IpAddr) -> bool {
        self.allowed_ips
            .as_ref()
            .is_none_or(|allowed_ips| allowed_ips.contains(&client_ip))
    }

    pub fn is_restricted(&self) -> bool {
        self.allowed_ips.is_some()
    }
}
