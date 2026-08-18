use argon2::{password_hash::SaltString, Argon2, PasswordHash, PasswordHasher, PasswordVerifier};
use uuid::Uuid;

#[derive(Debug)]
pub enum Error {
    FailedToParseRefreshToken,
}

pub const ACCESS_TOKEN_LIFETIME_SECONDS: i64 = 60 * 30;
pub const REFRESH_TOKEN_LIFETIME_SECONDS: i64 = 60 * 60 * 24 * 30;

pub mod jwt {
    use jsonwebtoken::{Algorithm, DecodingKey, EncodingKey, Validation};
    use rand::Rng;
    use serde::{Deserialize, Serialize};
    use uuid::Uuid;

    use super::{generate_refresh_token, hash_password};

    #[derive(Debug, Serialize, Deserialize)]
    pub struct Claims {
        exp: i64,
        sub: String,
    }

    impl Claims {
        // access the sub (user_id). This must be a string in Claims.
        pub fn sub(&self) -> Uuid {
            self.sub.parse::<Uuid>().unwrap()
        }
    }

    #[derive(Clone)]
    pub struct JWTManager {
        validation: Validation,
        decoding_key: DecodingKey,
        encoding_key: EncodingKey,
    }

    impl Default for JWTManager {
        fn default() -> Self {
            Self::new()
        }
    }

    impl JWTManager {
        pub fn new() -> Self {
            let private_key = std::env::var("JWT_PRIVATE_KEY").expect("JWT_PRIVATE_KEY not set");
            let public_key = std::env::var("JWT_PUBLIC_KEY").expect("JWT_PUBLIC_KEY not set");
            let decoding_key = DecodingKey::from_ed_pem(public_key.as_bytes()).unwrap();
            let encoding_key = EncodingKey::from_ed_pem(private_key.as_bytes()).unwrap();

            Self {
                validation: Validation::new(Algorithm::EdDSA),
                decoding_key,
                encoding_key,
            }
        }

        // Validates the jwt, returning the user's id if all is well.
        pub fn validate(&self, jwt: &str) -> Option<Uuid> {
            if let Ok(token_data) =
                jsonwebtoken::decode::<Claims>(jwt, &self.decoding_key, &self.validation)
            {
                Some(token_data.claims.sub())
            } else {
                None
            }
        }

        /// Returns the access token, refresh token, and the hashed uuid part of the refresh token
        pub fn create(&self, user_id: Uuid, name: &str) -> (String, String, String) {
            let time_in_half_an_hour =
                chrono::Utc::now().timestamp() + super::ACCESS_TOKEN_LIFETIME_SECONDS;
            let claims = Claims {
                exp: time_in_half_an_hour,
                sub: user_id.to_string(),
            };
            let access_token = jsonwebtoken::encode(
                &jsonwebtoken::Header::new(jsonwebtoken::Algorithm::EdDSA),
                &claims,
                &self.encoding_key,
            )
            .expect("Could not create JWT");

            let (uuid_part, refresh_token) = generate_refresh_token(user_id, name);
            let hashed_uuid_part = hash_password(uuid_part.as_str());

            (access_token, refresh_token, hashed_uuid_part)
        }
    }

    /// Generates a random 10 letter string consisting of a-z, A-Z and 0-9.
    pub fn create_random_string() -> String {
        let charset = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";

        let mut res = String::new();
        for _ in 0..10 {
            let mut rng = rand::thread_rng();
            let random_char = charset[rng.gen_range(0..charset.len())] as char;
            res.push(random_char);
        }

        res
    }
}

pub fn parse_refresh_token(refresh_token: &str) -> Result<(Uuid, String, String), Error> {
    let parts: Vec<&str> = refresh_token.split('$').collect();
    if parts.len() != 3 {
        return Err(Error::FailedToParseRefreshToken);
    };
    let user_id: Uuid = parts[0]
        .parse()
        .map_err(|_| Error::FailedToParseRefreshToken)?;

    Ok((user_id, parts[1].to_string(), parts[2].to_string()))
}

fn generate_refresh_token(user_id: Uuid, name: &str) -> (String, String) {
    let mut refresh_token = String::with_capacity(36 + 1 + 10 + 1 + 36);
    refresh_token.push_str(user_id.to_string().as_str());
    refresh_token.push('$');
    refresh_token.push_str(name);
    refresh_token.push('$');
    let uuid_part = Uuid::new_v4().to_string().replace('-', "_");
    refresh_token.push_str(uuid_part.as_str());

    (uuid_part, refresh_token)
}

pub fn check_password(hashed_password: &str, raw_password: &str) -> bool {
    let parsed_hash = PasswordHash::new(hashed_password).unwrap();
    Argon2::default()
        .verify_password(raw_password.as_bytes(), &parsed_hash)
        .is_ok()
}

pub fn hash_password(input: &str) -> String {
    let salt = SaltString::generate(rand::thread_rng());
    Argon2::default()
        .hash_password(input.as_bytes(), &salt)
        .unwrap()
        .to_string()
}
