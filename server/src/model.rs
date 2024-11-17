use argon2::{password_hash::SaltString, Argon2, PasswordHasher};
use async_graphql::{
    EmptySubscription, InputObject, Object, Schema, SimpleObject,
};
use regex::Regex;
use sqlx::{Pool, Postgres};
use uuid::Uuid;

pub type ServiceSchema = Schema<QueryRoot, MutationRoot, EmptySubscription>;

pub struct QueryRoot;

#[Object]
impl QueryRoot {
    async fn hello(&self, _ctx: &async_graphql::Context<'_>) -> &'static str {
        "Wag1"
    }
    // async fn user(
    //     &self,
    //     _ctx: &async_graphql::Context<'_>,
    // ) -> Result<User, &'static str> {
    //     todo!();
    // }
}

pub struct MutationRoot;

#[derive(SimpleObject)]
struct User {
    id: i32,
    email: String,
}

#[derive(SimpleObject)]
struct AuthResponse {
    user: User,
    session_id: String,
}

#[derive(InputObject)]
struct CreateUserInput {
    email: String,
    password: String,
    confirm_password: String,
}

#[Object]
impl MutationRoot {
    async fn create_user(
        &self,
        ctx: &async_graphql::Context<'_>,
        input: CreateUserInput,
    ) -> Result<AuthResponse, &'static str> {
        let is_valid_email =
            Regex::new(r"^[\w\.-]+@[a-zA-Z\d\.-]+\.[a-zA-Z]{2,}$")
                .unwrap()
                .is_match(input.email.as_str());
        if !is_valid_email {
            return Err("Invalid email address.");
        }
        if input.email.len() > 40 {
            return Err("Email too long. The max email length is 40.");
        }


        if !input.password.is_ascii() {
            return Err("Password must contain only standard English letters, numbers, and common punctuation.");
        }
        if input.password.len() > 64 {
            return Err("Password too long. The max password length is 64.");
        }
        if input.password.len() < 8 {
            return Err("Password too short. The min password length is 8.");
        }
        if input.password != input.confirm_password {
            return Err("Passwords do not match.");
        }


        let db_pool =
            ctx.data::<Pool<Postgres>>().expect("No db pool in context");

        // Check if the user already exists.
        let row: (bool,) = sqlx::query_as(
            "SELECT EXISTS(SELECT 1 FROM users WHERE email = $1)",
        )
        .bind(input.email.as_str())
        .fetch_one(&db_pool.clone())
        .await
        .expect("failed to check if user already exists");
        let email_taken = row.0;
        if email_taken {
            return Err("Email already exists");
        }

        let salt = SaltString::generate(rand::thread_rng());
        let hashed_password = Argon2::default()
            .hash_password(input.password.as_bytes(), &salt)
            .unwrap()
            .to_string();

        let (user_id,): (i32,) = sqlx::query_as(
        "INSERT INTO users (email, password, salt) VALUES ($1, $2, $3) RETURNING id",
        )
        .bind(input.email.as_str())
        .bind(hashed_password)
        .bind(salt.to_string())
        .fetch_one(&db_pool.clone())
        .await
        .expect("Failed to insert user");

        // log user in
        let session_id = Uuid::new_v4().to_string().replace('-', "_");
        sqlx::query(
            "INSERT INTO sessions (session_id, user_id) VALUES ($1, $2)",
        )
        .bind(session_id.clone())
        .bind(user_id)
        .execute(&db_pool.clone())
        .await
        .expect("Failed to create session id");

        let user = User {
            id: user_id,
            email: input.email,
        };

        Ok(AuthResponse { user, session_id })
    }
}
