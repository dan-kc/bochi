use chrono::NaiveDateTime;
use sqlx::{postgres::PgPoolOptions, Pool, Postgres};

use crate::graphql::{
    CreateHabitInput, CreateProjectInput, CreateRewardInput, CreateTagInput, CreateTaskInput,
    CreateTreatInput,
};

#[derive(Clone)]
pub struct Database {
    pool: Pool<Postgres>,
}

impl Database {
    pub async fn new(user: &str, password: &str, host: &str, name: &str) -> Self {
        let database_url = format!("postgres://{}:{}@{}/{}", user, password, host, name);
        let pool = PgPoolOptions::new()
            .max_connections(97) // 97 is the default limit for postgres. Change this if we ever have
            // another server connecting. All pools must add up to 97.
            .connect(&database_url)
            .await
            .expect("Unable to create database pool");

        Database { pool }
    }

    /// Creates a user, returning the user id.
    pub async fn create_user(
        &self,
        email: &str,
        hashed_password: &str,
    ) -> Result<i32, sqlx::Error> {
        let (user_id,): (i32,) =
            sqlx::query_as("INSERT INTO users (email, password) VALUES ($1, $2) RETURNING id")
                .bind(email)
                .bind(hashed_password)
                .fetch_one(&self.pool)
                .await?;

        Ok(user_id)
    }
    pub async fn create_task(
        &self,
        create_task_options: CreateTaskOptions,
    ) -> Result<TaskRow, sqlx::Error> {
        sqlx::query_as(
            "INSERT INTO tasks
            (user_id, name, hidden_until, due_by, description, difficulty, importance, duration) VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING *",
        )
        .bind(create_task_options.user_id)
        .bind(create_task_options.name)
        .bind(create_task_options.hidden_until)
        .bind(create_task_options.due_by)
        .bind(create_task_options.description)
        .bind(create_task_options.difficulty)
        .bind(create_task_options.importance)
        .bind(create_task_options.duration)
        .fetch_one(&self.pool)
        .await
    }
    /// Creates a habit, returning the habit..
    pub async fn create_habit(
        &self,
        create_habit_options: CreateHabitOptions,
    ) -> Result<HabitRow, sqlx::Error> {
        sqlx::query_as(
            "INSERT INTO habits
            (user_id, name, hidden_until, description, difficulty, importance, duration, min_freqency) VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING *",
        )
        .bind(create_habit_options.user_id)
        .bind(create_habit_options.name)
        .bind(create_habit_options.hidden_until)
        .bind(create_habit_options.description)
        .bind(create_habit_options.difficulty)
        .bind(create_habit_options.importance)
        .bind(create_habit_options.duration)
        .bind(create_habit_options.min_frequency)
        .fetch_one(&self.pool)
        .await
    }

    /// Creates a project, returning the project..
    pub async fn create_project(
        &self,
        create_project_options: CreateProjectOptions,
    ) -> Result<ProjectRow, sqlx::Error> {
        sqlx::query_as(
            "INSERT INTO projects
            (user_id, name, hidden_until, due_by, description, importance) VALUES ($1, $2, $3, $4, $5, $6) RETURNING *",
        )
        .bind(create_project_options.user_id)
        .bind(create_project_options.name)
        .bind(create_project_options.hidden_until)
        .bind(create_project_options.due_by)
        .bind(create_project_options.description)
        .bind(create_project_options.importance)
        .fetch_one(&self.pool)
        .await
    }

    /// Creates a reward, returning the reward..
    pub async fn create_reward(
        &self,
        create_reward_options: CreateRewardOptions,
    ) -> Result<RewardRow, sqlx::Error> {
        sqlx::query_as(
            "INSERT INTO rewards
            (user_id, name, hidden_until, description, damage, pleasure, max_frequency) VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING *",
        )
        .bind(create_reward_options.user_id)
        .bind(create_reward_options.name)
        .bind(create_reward_options.hidden_until)
        .bind(create_reward_options.description)
        .bind(create_reward_options.damage)
        .bind(create_reward_options.pleasure)
        .bind(create_reward_options.max_frequency)
        .fetch_one(&self.pool)
        .await
    }

    /// Creates a mega_reward, returning the mega_reward..
    pub async fn create_treat_reward(
        &self,
        create_mega_reward_options: CreateTreatOptions,
    ) -> Result<MegaRewardRow, sqlx::Error> {
        sqlx::query_as(
            "INSERT INTO mega_rewards
            (user_id, name, hidden_until, description, damage, pleasure) VALUES ($1, $2, $3, $4, $5, $6) RETURNING *",
        )
        .bind(create_mega_reward_options.user_id)
        .bind(create_mega_reward_options.name)
        .bind(create_mega_reward_options.hidden_until)
        .bind(create_mega_reward_options.description)
        .bind(create_mega_reward_options.damage)
        .bind(create_mega_reward_options.pleasure)
        .fetch_one(&self.pool)
        .await
    }

    /// Creates a tag, returning the tag..
    pub async fn create_tag(
        &self,
        create_tag_options: CreateTagOptions,
    ) -> Result<TagRow, sqlx::Error> {
        sqlx::query_as(
            "INSERT INTO tags
            (user_id, name, color_hex) VALUES ($1, $2, $3) RETURNING *",
        )
        .bind(create_tag_options.user_id)
        .bind(create_tag_options.name)
        .bind(create_tag_options.color_hex)
        .fetch_one(&self.pool)
        .await
    }

    /// Creates refresh token in the db. Api keys have expires_at = NULL
    pub async fn create_or_overwrite_refresh_token(
        &self,
        refresh_token: &str,
        user_id: i32,
        name: &str,
        is_api_key: bool,
    ) -> Result<RefreshTokenRow, sqlx::Error> {
        // TODO: put in transaction.
        // Delete
        sqlx::query("DELETE FROM refresh_tokens WHERE name = $1 AND user_id = $2;")
            .bind(name)
            .bind(user_id)
            .execute(&self.pool)
            .await?;

        let insert_query = match is_api_key{
            true => "INSERT INTO refresh_tokens (key, user_id, name, expires_at) VALUES ($1, $2, $3, NULL) RETURNING *",
            false => "INSERT INTO refresh_tokens (key, user_id, name) VALUES ($1, $2, $3) RETURNING *"
        };
        let refresh_token_row: RefreshTokenRow = sqlx::query_as(insert_query)
            .bind(refresh_token)
            .bind(user_id)
            .bind(name)
            .fetch_one(&self.pool)
            .await
            .map_err(|_| sqlx::Error::RowNotFound)?;

        Ok(refresh_token_row)
    }

    pub async fn delete_refresh_token_by_user_and_name(
        &self,
        user_id: i32,
        name: &str,
    ) -> Result<(), sqlx::Error> {
        sqlx::query("DELETE FROM refresh_tokens WHERE user_id = $1 AND name = $2")
            .bind(user_id)
            .bind(name)
            .execute(&self.pool)
            .await?;

        Ok(())
    }

    pub async fn get_refresh_token_from_name_user(
        &self,
        name: &str,
        user_id: i32,
    ) -> Result<RefreshTokenRow, sqlx::Error> {
        sqlx::query_as(
            "
            SELECT * FROM refresh_tokens
            INNER JOIN users ON refresh_tokens.user_id = users.id
            WHERE refresh_tokens.name = $1
            AND refresh_tokens.user_id = $2
            AND (refresh_tokens.expires_at > NOW() OR refresh_tokens.expires_at IS NULL);
        ",
        )
        .bind(name)
        .bind(user_id)
        .fetch_optional(&self.pool)
        .await
        .unwrap()
        .ok_or(sqlx::Error::RowNotFound)
    }

    /// Returns the user from email.
    pub async fn get_user_from_email(&self, email: &str) -> Result<UserRow, sqlx::Error> {
        sqlx::query_as("SELECT * FROM users WHERE email = $1")
            .bind(email)
            .fetch_optional(&self.pool)
            .await?
            .ok_or(sqlx::Error::RowNotFound)
    }

    pub async fn get_user_from_user_id(&self, user_id: i32) -> Result<UserRow, sqlx::Error> {
        sqlx::query_as("SELECT * FROM users WHERE id = $1")
            .bind(user_id)
            .fetch_optional(&self.pool)
            .await?
            .ok_or(sqlx::Error::RowNotFound)
    }
}

pub struct CreateTaskOptions {
    pub user_id: i32,
    pub name: String,
    pub hidden_until: Option<NaiveDateTime>,
    pub due_by: Option<NaiveDateTime>,
    pub description: String,
    pub difficulty: i32,
    pub importance: i32,
    pub duration: i32,
}
impl CreateTaskOptions {
    pub fn new(input: CreateTaskInput, user_id: i32) -> Self {
        Self {
            user_id,
            name: input.name,
            hidden_until: input.hidden_until,
            due_by: input.due_by,
            description: input.description,
            difficulty: input.difficulty,
            importance: input.importance,
            duration: input.duration,
        }
    }
}

pub struct CreateHabitOptions {
    pub user_id: i32,
    pub name: String,
    pub hidden_until: Option<NaiveDateTime>,
    pub description: String,
    pub difficulty: i32,
    pub importance: i32,
    pub duration: i32,
    pub min_frequency: i32,
}
impl CreateHabitOptions {
    pub fn new(input: CreateHabitInput, user_id: i32) -> Self {
        Self {
            user_id,
            name: input.name,
            hidden_until: input.hidden_until,
            description: input.description,
            difficulty: input.difficulty,
            importance: input.importance,
            duration: input.duration,
            min_frequency: input.min_frequency,
        }
    }
}

pub struct CreateProjectOptions {
    pub user_id: i32,
    pub name: String,
    pub hidden_until: Option<NaiveDateTime>,
    pub due_by: Option<NaiveDateTime>,
    pub description: String,
    pub importance: i32,
}
impl CreateProjectOptions {
    pub fn new(input: CreateProjectInput, user_id: i32) -> Self {
        let description = match input.description {
            None => "".to_string(),
            Some(desc) => desc,
        };
        Self {
            user_id,
            name: input.name,
            hidden_until: input.hidden_until,
            due_by: input.due_by,
            description,
            importance: input.importance,
        }
    }
}

pub struct CreateRewardOptions {
    pub user_id: i32,
    pub name: String,
    pub hidden_until: Option<NaiveDateTime>,
    pub description: String,
    pub damage: i32,
    pub pleasure: i32,
    pub max_frequency: i32,
}
impl CreateRewardOptions {
    pub fn new(input: CreateRewardInput, user_id: i32) -> Self {
        Self {
            user_id,
            name: input.name,
            hidden_until: input.hidden_until,
            description: input.description,
            damage: input.damage,
            pleasure: input.pleasure,
            max_frequency: input.max_frequency,
        }
    }
}

pub struct CreateTreatOptions {
    pub user_id: i32,
    pub name: String,
    pub hidden_until: Option<NaiveDateTime>,
    pub description: String,
    pub damage: i32,
    pub pleasure: i32,
}
impl CreateTreatOptions {
    pub fn new(input: CreateTreatInput, user_id: i32) -> Self {
        Self {
            user_id,
            name: input.name,
            hidden_until: input.hidden_until,
            description: input.description,
            damage: input.damage,
            pleasure: input.pleasure,
        }
    }
}

pub struct CreateTagOptions {
    pub user_id: i32,
    pub name: String,
    pub color_hex: String,
}
impl CreateTagOptions {
    pub fn new(input: CreateTagInput, user_id: i32) -> Self {
        Self {
            user_id,
            name: input.name,
            color_hex: input.color_hex,
        }
    }
}

#[derive(sqlx::FromRow)]
pub struct UserRow {
    pub id: i32,
    pub email: String,
    pub password: String,
}

#[derive(sqlx::FromRow)]
pub struct RefreshTokenRow {
    pub key: String,
    pub created_at: NaiveDateTime,
    pub expires_at: Option<NaiveDateTime>,
}

#[derive(sqlx::FromRow)]
#[allow(unused)]
pub struct TaskRow {
    pub id: i32,
    pub user_id: i32,
    pub name: String,
    pub created_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub hidden_until: Option<NaiveDateTime>,
    pub due_by: Option<NaiveDateTime>,
    pub difficulty: i32,
    pub description: String,
    pub importance: i32,
    pub duration: i32,
}

#[derive(sqlx::FromRow)]
pub struct HabitRow {
    pub id: i32,
    pub user_id: i32,
    pub name: String,
    pub created_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub hidden_until: Option<NaiveDateTime>,
    pub difficulty: i32,
    pub description: String,
    pub importance: i32,
    pub duration: i32,
    pub min_frequency: i32,
}

#[derive(sqlx::FromRow)]
pub struct ProjectRow {
    pub id: i32,
    pub user_id: i32,
    pub name: String,
    pub created_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub hidden_until: Option<NaiveDateTime>,
    pub due_by: Option<NaiveDateTime>,
    pub description: String,
    pub importance: i32,
}

#[derive(sqlx::FromRow)]
pub struct RewardRow {
    pub id: i32,
    pub user_id: i32,
    pub name: String,
    pub created_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub hidden_until: Option<NaiveDateTime>,
    pub description: String,
    pub damage: i32,
    pub pleasure: i32,
    pub max_frequency: i32,
}

#[derive(sqlx::FromRow)]
pub struct MegaRewardRow {
    pub id: i32,
    pub user_id: i32,
    pub name: String,
    pub created_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub hidden_until: Option<NaiveDateTime>,
    pub description: String,
    pub damage: i32,
    pub pleasure: i32,
}

#[derive(sqlx::FromRow)]
pub struct TagRow {
    pub id: i32,
    pub user_id: i32,
    pub name: String,
    pub created_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub color_hex: String,
}
