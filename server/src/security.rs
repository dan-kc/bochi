use argon2::{password_hash::SaltString, Argon2, PasswordHasher};
use argon2::{PasswordHash, PasswordVerifier};

pub mod jwt {
    use jsonwebtoken::{Algorithm, DecodingKey, Validation};
    use serde::{Deserialize, Serialize};
    use std::{fs::File, io::Read};
    use uuid::Uuid;

    #[derive(Debug, Serialize, Deserialize)]
    pub struct Claims {
        exp: i64,
        sub: String,
    }

    impl Claims {
        // access the sub (user_id). This must be a string in Claims.
        pub fn sub(&self) -> i32 {
            self.sub.parse::<i32>().unwrap()
        }
    }

    #[derive(Clone)]
    pub struct Validator {
        validation: Validation,
        decoding_key: DecodingKey,
    }

    impl Validator {
        pub fn new() -> Self {
            let mut public_key_file =
                File::open("/usr/src/app/public_key.pem").unwrap();
            let mut public_key = Vec::new();
            public_key_file.read_to_end(&mut public_key).unwrap();

            let decoding_key =
                DecodingKey::from_ed_pem(public_key.as_slice()).unwrap();

            Self {
                validation: Validation::new(Algorithm::EdDSA),
                decoding_key,
            }
        }

        // Validates the jwt, returning the user's id if all is well.
        pub fn validate(&self, jwt: &str) -> Option<i32> {
            if let Ok(token_data) = jsonwebtoken::decode::<Claims>(
                jwt,
                &self.decoding_key,
                &self.validation,
            ) {
                Some(token_data.claims.sub())
            } else {
                None
            }
        }
    }

    pub fn create_jwt_pair(user_id: i32) -> (String, String) {
        let mut private_key_file =
            File::open("/usr/src/app/private_key.pem").unwrap();
        let mut private_key = Vec::new();
        private_key_file.read_to_end(&mut private_key).unwrap();

        let time_in_half_an_hour = chrono::Utc::now().timestamp() + 60 * 30;
        let claims = Claims {
            exp: time_in_half_an_hour,
            sub: user_id.to_string(),
        };
        let access_token = jsonwebtoken::encode(
            &jsonwebtoken::Header::new(jsonwebtoken::Algorithm::EdDSA),
            &claims,
            &jsonwebtoken::EncodingKey::from_ed_pem(private_key.as_slice())
                .unwrap(),
        )
        .expect("Could not create JWT");

        // Add refresh token to db
        let refresh_token = Uuid::new_v4().to_string().replace('-', "_");

        (access_token, refresh_token)
    }
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
