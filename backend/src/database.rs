use chrono::NaiveDateTime;
use serde_json::Value;
use sqlx::{postgres::PgPoolOptions, Pool, Postgres, Transaction};
use tracing::{error, info};
use url::form_urlencoded;
use uuid::Uuid;

use crate::error_context::SqlxErrorContext;

const VAULT_MICRO_UNITS_PER_COIN: i64 = 1_000_000;

#[derive(Clone)]
pub struct Database {
    pool: Pool<Postgres>,
}

fn validate_trade_shape(trade: &UpsertTradeOptions) -> Result<(), sqlx::Error> {
    let source_count = usize::from(trade.task_id.is_some())
        + usize::from(trade.recurring_task_id.is_some())
        + usize::from(trade.reward_id.is_some());

    if trade.refunds_trade_id.is_some() {
        return Ok(());
    }

    match trade.trade_kind.as_str() {
        "taskCompletion" if trade.task_id.is_some() && source_count == 1 => Ok(()),
        "recurringTaskCompletion" if trade.recurring_task_id.is_some() && source_count == 1 => {
            Ok(())
        }
        "rewardPurchase" | "vaultRewardPurchase"
            if trade.reward_id.is_some() && source_count == 1 =>
        {
            Ok(())
        }
        "vaultDeposit" | "vaultInterest" if source_count == 0 => Ok(()),
        "taskCompletion"
        | "recurringTaskCompletion"
        | "rewardPurchase"
        | "vaultDeposit"
        | "vaultInterest"
        | "vaultRewardPurchase" => Err(sqlx::Error::Protocol(
            "Trade source shape does not match trade kind".into(),
        )),
        _ => Err(sqlx::Error::Protocol(format!(
            "Invalid trade kind: {}",
            trade.trade_kind
        ))),
    }?;

    match trade.trade_kind.as_str() {
        "vaultDeposit"
            if trade.amount >= 0
                || trade.vault_amount_micro
                    != Some(-(trade.amount as i64) * VAULT_MICRO_UNITS_PER_COIN) =>
        {
            Err(sqlx::Error::Protocol(
                "Vault deposits must subtract from spendable balance and add matching vault micro-units".into(),
            ))
        }
        "vaultInterest"
            if trade.amount != 0 || trade.vault_amount_micro.is_none_or(|amount| amount <= 0) =>
        {
            Err(sqlx::Error::Protocol(
                "Vault interest must add positive vault micro-units".into(),
            ))
        }
        "vaultInterest" if trade.vault_interest_hour.is_none() => Err(sqlx::Error::Protocol(
            "Vault interest trades require vault_interest_hour".into(),
        )),
        "vaultRewardPurchase"
            if trade.amount != 0 || trade.vault_amount_micro.is_none_or(|amount| amount >= 0) =>
        {
            Err(sqlx::Error::Protocol(
                "Vault reward purchases must spend vault micro-units without changing spendable balance".into(),
            ))
        }
        kind if !matches!(kind, "vaultDeposit" | "vaultInterest" | "vaultRewardPurchase")
            && trade.vault_amount_micro.is_some() =>
        {
            Err(sqlx::Error::Protocol(
                "Only vault trades may include vault micro-units".into(),
            ))
        }
        kind if kind != "vaultInterest" && trade.vault_interest_hour.is_some() => {
            Err(sqlx::Error::Protocol(
                "Only vault interest trades may include vault interest markers".into(),
            ))
        }
        _ => Ok(()),
    }
}

fn active_unresolved_task_trade_exists_sql(task_id_expr: &str, user_id_expr: &str) -> String {
    format!(
        "EXISTS (
            SELECT 1
            FROM trades task_trade
            WHERE task_trade.user_id = {user_id_expr}
              AND task_trade.task_id = {task_id_expr}
              AND task_trade.deleted_at IS NULL
              AND task_trade.refunds_trade_id IS NULL
              AND NOT EXISTS (
                SELECT 1
                FROM trades refund
                WHERE refund.refunds_trade_id = task_trade.id
                  AND refund.deleted_at IS NULL
              )
        )"
    )
}

pub(crate) fn task_select_columns(task_alias: &str, _user_id_expr: &str) -> String {
    format!(
        "{task_alias}.id,
         {task_alias}.name,
         {task_alias}.description,
         {task_alias}.created_at,
         {task_alias}.updated_at,
         {task_alias}.deleted_at,
         {task_alias}.recurring,
         {task_alias}.base_price,
         {task_alias}.due_date,
         {task_alias}.min_daily_frequency,
         {task_alias}.lockout_duration_seconds,
         {task_alias}.pinned,
         {task_alias}.hidden,
         {task_alias}.timer_mode,
         {task_alias}.timer_id,
         {task_alias}.server_revision"
    )
}

impl Database {
    pub async fn new() -> Self {
        // Get configuration from environment variables
        let user = std::env::var("DB_USER").expect("DB_USER not set");
        let password = std::env::var("DB_PASSWORD").expect("DB_PASSWORD not set");
        let encoded_password: String =
            form_urlencoded::byte_serialize(password.as_bytes()).collect();
        let host = std::env::var("DB_HOST").expect("DB_HOST not set");
        let name = std::env::var("DB_NAME").expect("DB_NAME not set");
        let ssl_mode = std::env::var("SSL_MODE").expect("SSL_MODE not set");

        let database_url = format!(
            "postgres://{}:{}@{}:5432/{}?sslmode={}",
            user, encoded_password, host, name, ssl_mode
        );

        let max_connections = 48;
        info!(
            operation = "database.connect",
            db_host = %host,
            db_name = %name,
            db_user = %user,
            db_ssl_mode = %ssl_mode,
            db_pool_max_connections = max_connections,
            "connecting to database"
        );

        let pool = PgPoolOptions::new()
            // 97 is the default connection limit for postgres. All pools must add up
            // to at most 97. Since we will have at most 2 servers, 48 is an
            // appropriate value here.
            .max_connections(max_connections)
            .connect(&database_url)
            .await
            .unwrap_or_else(|error| {
                let context = SqlxErrorContext::from_error(&error);
                error!(
                    operation = "database.connect",
                    db_host = %host,
                    db_name = %name,
                    db_user = %user,
                    db_ssl_mode = %ssl_mode,
                    db_pool_max_connections = max_connections,
                    error = %error,
                    database_error_kind = context.kind,
                    database_error_code = context.database_code(),
                    database_error_message = context.database_message(),
                    database_error_constraint = context.database_constraint(),
                    database_error_table = context.database_table(),
                    "failed to create database pool"
                );
                panic!("Unable to create database pool.");
            });

        info!(
            operation = "database.connect",
            db_host = %host,
            db_name = %name,
            db_user = %user,
            db_ssl_mode = %ssl_mode,
            db_pool_max_connections = max_connections,
            "database pool connected"
        );

        Database { pool }
    }

    /// Creates a Sign in with Apple account, returning the user id.
    pub async fn create_apple_user(
        &self,
        apple_user_id: &str,
        email: Option<&str>,
        apple_refresh_token: Option<&str>,
    ) -> Result<Uuid, sqlx::Error> {
        let (user_id,): (Uuid,) = sqlx::query_as(
            "INSERT INTO users (apple_user_id, email, apple_refresh_token)
             VALUES ($1, $2, $3)
             RETURNING id",
        )
        .bind(apple_user_id)
        .bind(email)
        .bind(apple_refresh_token)
        .fetch_one(&self.pool)
        .await?;

        Ok(user_id)
    }

    pub async fn update_apple_refresh_token(
        &self,
        user_id: Uuid,
        apple_refresh_token: &str,
    ) -> Result<(), sqlx::Error> {
        sqlx::query(
            "UPDATE users
             SET apple_refresh_token = $1
             WHERE id = $2",
        )
        .bind(apple_refresh_token)
        .bind(user_id)
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    pub async fn get_apple_refresh_token_for_user(
        &self,
        user_id: Uuid,
    ) -> Result<Option<String>, sqlx::Error> {
        let row: Option<(Option<String>,)> = sqlx::query_as(
            "SELECT apple_refresh_token
             FROM users
             WHERE id = $1",
        )
        .bind(user_id)
        .fetch_optional(&self.pool)
        .await?;

        row.map(|(token,)| token).ok_or(sqlx::Error::RowNotFound)
    }

    pub async fn delete_user_account(&self, user_id: Uuid) -> Result<bool, sqlx::Error> {
        let result = sqlx::query("DELETE FROM users WHERE id = $1")
            .bind(user_id)
            .execute(&self.pool)
            .await?;

        Ok(result.rows_affected() > 0)
    }

    /// Creates refresh token in the db. Api keys have expires_at = NULL
    pub async fn create_or_overwrite_refresh_token(
        &self,
        refresh_token: &str,
        user_id: Uuid,
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
            true => "INSERT INTO refresh_tokens (key, user_id, name, expires_at) VALUES ($1, $2, $3, NULL) RETURNING key, created_at, expires_at",
            false => "INSERT INTO refresh_tokens (key, user_id, name) VALUES ($1, $2, $3) RETURNING key, created_at, expires_at"
        };
        let refresh_token_row: RefreshTokenRow = sqlx::query_as(insert_query)
            .bind(refresh_token)
            .bind(user_id)
            .bind(name)
            .fetch_one(&self.pool)
            .await?;

        Ok(refresh_token_row)
    }

    pub async fn delete_refresh_token_by_user_and_name(
        &self,
        user_id: Uuid,
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
        user_id: Uuid,
    ) -> Result<RefreshTokenRow, sqlx::Error> {
        sqlx::query_as(
            "
            SELECT refresh_tokens.key, refresh_tokens.created_at, refresh_tokens.expires_at
            FROM refresh_tokens
            INNER JOIN users ON refresh_tokens.user_id = users.id
            WHERE refresh_tokens.name = $1
            AND refresh_tokens.user_id = $2
            AND (refresh_tokens.expires_at > NOW() OR refresh_tokens.expires_at IS NULL);
        ",
        )
        .bind(name)
        .bind(user_id)
        .fetch_optional(&self.pool)
        .await?
        .ok_or(sqlx::Error::RowNotFound)
    }

    /// Returns the user from Apple's stable per-app user identifier.
    pub async fn get_user_from_apple_user_id(
        &self,
        apple_user_id: &str,
    ) -> Result<UserRow, sqlx::Error> {
        sqlx::query_as(
            "SELECT
                id
             FROM users
             WHERE apple_user_id = $1",
        )
        .bind(apple_user_id)
        .fetch_optional(&self.pool)
        .await?
        .ok_or(sqlx::Error::RowNotFound)
    }

    /// Get the account-level auth and subscription state needed by the client.
    pub async fn get_user_account_state(
        &self,
        user_id: Uuid,
    ) -> Result<UserAccountStateRow, sqlx::Error> {
        sqlx::query_as(
            "SELECT
                users.email,
                entitlement.source AS subscription_source,
                COALESCE(entitlement.status, 'none') AS subscription_status,
                entitlement.product_id AS subscription_product_id,
                entitlement.expires_at AS subscription_expires_at
             FROM users
             LEFT JOIN LATERAL (
                SELECT
                    source,
                    status,
                    product_id,
                    expires_at,
                    updated_at
                FROM premium_entitlements
                WHERE user_id = users.id
                  AND deleted_at IS NULL
                ORDER BY
                    CASE
                        WHEN status IN ('active', 'grace_period')
                         AND (expires_at IS NULL OR expires_at > NOW())
                        THEN 0
                        ELSE 1
                    END,
                    updated_at DESC
                LIMIT 1
             ) entitlement ON TRUE
             WHERE users.id = $1",
        )
        .bind(user_id)
        .fetch_one(&self.pool)
        .await
    }

    /// Returns the user who already owns a given Apple original transaction, if any.
    pub async fn get_user_id_from_app_store_original_transaction_id(
        &self,
        original_transaction_id: &str,
    ) -> Result<Option<Uuid>, sqlx::Error> {
        let row: Option<(Uuid,)> = sqlx::query_as(
            "SELECT user_id
             FROM premium_entitlements
             WHERE source = 'apple'
               AND app_store_original_transaction_id = $1
               AND deleted_at IS NULL",
        )
        .bind(original_transaction_id)
        .fetch_optional(&self.pool)
        .await?;

        Ok(row.map(|(id,)| id))
    }

    /// Attaches an Apple subscription to the given user account and returns
    /// the client-facing account state after linking.
    pub async fn link_apple_subscription(
        &self,
        user_id: Uuid,
        original_transaction_id: &str,
        latest_transaction_id: &str,
        product_id: Option<&str>,
        subscription_status: &str,
        subscription_expires_at: Option<NaiveDateTime>,
        app_store_environment: &str,
    ) -> Result<UserAccountStateRow, sqlx::Error> {
        let mut tx = self.pool.begin().await?;

        sqlx::query(
            "INSERT INTO premium_entitlements (
                user_id,
                source,
                status,
                product_id,
                expires_at,
                app_store_original_transaction_id,
                app_store_latest_transaction_id,
                app_store_environment
             )
             VALUES ($1, 'apple', $2, $3, $4, $5, $6, $7)
             ON CONFLICT (app_store_original_transaction_id)
             WHERE source = 'apple'
               AND app_store_original_transaction_id IS NOT NULL
               AND deleted_at IS NULL
             DO UPDATE SET
                status = EXCLUDED.status,
                product_id = EXCLUDED.product_id,
                expires_at = EXCLUDED.expires_at,
                app_store_latest_transaction_id = EXCLUDED.app_store_latest_transaction_id,
                app_store_environment = EXCLUDED.app_store_environment
             WHERE premium_entitlements.user_id = EXCLUDED.user_id",
        )
        .bind(user_id)
        .bind(subscription_status)
        .bind(product_id)
        .bind(subscription_expires_at)
        .bind(original_transaction_id)
        .bind(latest_transaction_id)
        .bind(app_store_environment)
        .execute(&mut *tx)
        .await?;

        sqlx::query(
            "UPDATE users
             SET subscription_source = 'apple',
                 subscription_status = $2,
                 subscription_expires_at = $3,
                 app_store_original_transaction_id = $4,
                 app_store_latest_transaction_id = $5,
                 app_store_environment = $6,
                 subscription_product_id = $7
             WHERE id = $1",
        )
        .bind(user_id)
        .bind(subscription_status)
        .bind(subscription_expires_at)
        .bind(original_transaction_id)
        .bind(latest_transaction_id)
        .bind(app_store_environment)
        .bind(product_id)
        .execute(&mut *tx)
        .await?;

        Self::apply_latest_apple_notification_to_entitlement_tx(
            &mut tx,
            user_id,
            original_transaction_id,
        )
        .await?;

        let account_state = Self::get_user_account_state_tx(&mut tx, user_id).await?;
        tx.commit().await?;

        Ok(account_state)
    }

    async fn apply_latest_apple_notification_to_entitlement_tx(
        tx: &mut Transaction<'_, Postgres>,
        user_id: Uuid,
        original_transaction_id: &str,
    ) -> Result<(), sqlx::Error> {
        sqlx::query(
            "WITH latest_notification AS (
                SELECT
                    latest_transaction_id,
                    product_id,
                    subscription_status,
                    expires_at,
                    environment
                FROM apple_server_notifications
                WHERE original_transaction_id = $1
                  AND latest_transaction_id IS NOT NULL
                  AND product_id IS NOT NULL
                  AND subscription_status IS NOT NULL
                  AND environment IS NOT NULL
                ORDER BY event_signed_at DESC, processed_at DESC
                LIMIT 1
             ),
             updated_entitlement AS (
                UPDATE premium_entitlements
                SET status = latest_notification.subscription_status,
                    product_id = latest_notification.product_id,
                    expires_at = latest_notification.expires_at,
                    app_store_latest_transaction_id = latest_notification.latest_transaction_id,
                    app_store_environment = latest_notification.environment
                FROM latest_notification
                WHERE premium_entitlements.user_id = $2
                  AND premium_entitlements.source = 'apple'
                  AND premium_entitlements.app_store_original_transaction_id = $1
                  AND premium_entitlements.deleted_at IS NULL
                RETURNING
                    premium_entitlements.user_id,
                    premium_entitlements.status,
                    premium_entitlements.product_id,
                    premium_entitlements.expires_at,
                    premium_entitlements.app_store_latest_transaction_id,
                    premium_entitlements.app_store_environment
             )
             UPDATE users
             SET subscription_source = 'apple',
                 subscription_status = updated_entitlement.status,
                 subscription_product_id = updated_entitlement.product_id,
                 subscription_expires_at = updated_entitlement.expires_at,
                 app_store_latest_transaction_id = updated_entitlement.app_store_latest_transaction_id,
                 app_store_environment = updated_entitlement.app_store_environment
             FROM updated_entitlement
             WHERE users.id = updated_entitlement.user_id",
        )
        .bind(original_transaction_id)
        .bind(user_id)
        .execute(&mut **tx)
        .await?;

        Ok(())
    }

    async fn get_user_account_state_tx(
        tx: &mut Transaction<'_, Postgres>,
        user_id: Uuid,
    ) -> Result<UserAccountStateRow, sqlx::Error> {
        sqlx::query_as(
            "SELECT
                users.email,
                entitlement.source AS subscription_source,
                COALESCE(entitlement.status, 'none') AS subscription_status,
                entitlement.product_id AS subscription_product_id,
                entitlement.expires_at AS subscription_expires_at
             FROM users
             LEFT JOIN LATERAL (
                SELECT
                    source,
                    status,
                    product_id,
                    expires_at,
                    updated_at
                FROM premium_entitlements
                WHERE user_id = users.id
                  AND deleted_at IS NULL
                ORDER BY
                    CASE
                        WHEN status IN ('active', 'grace_period')
                         AND (expires_at IS NULL OR expires_at > NOW())
                        THEN 0
                        ELSE 1
                    END,
                    updated_at DESC
                LIMIT 1
             ) entitlement ON TRUE
             WHERE users.id = $1",
        )
        .bind(user_id)
        .fetch_one(&mut **tx)
        .await
    }

    pub async fn record_apple_server_notification(
        &self,
        notification_uuid: &str,
        notification_type: Option<&str>,
        subtype: Option<&str>,
        original_transaction_id: Option<&str>,
        latest_transaction_id: Option<&str>,
        product_id: Option<&str>,
        environment: Option<&str>,
        subscription_status: Option<&str>,
        subscription_expires_at: Option<NaiveDateTime>,
        event_signed_at: NaiveDateTime,
        payload_hash: &str,
    ) -> Result<bool, sqlx::Error> {
        let result = sqlx::query(
            "INSERT INTO apple_server_notifications (
                notification_uuid,
                notification_type,
                subtype,
                original_transaction_id,
                latest_transaction_id,
                product_id,
                environment,
                subscription_status,
                expires_at,
                event_signed_at,
                payload_hash
             )
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
             ON CONFLICT (notification_uuid) DO NOTHING",
        )
        .bind(notification_uuid)
        .bind(notification_type)
        .bind(subtype)
        .bind(original_transaction_id)
        .bind(latest_transaction_id)
        .bind(product_id)
        .bind(environment)
        .bind(subscription_status)
        .bind(subscription_expires_at)
        .bind(event_signed_at)
        .bind(payload_hash)
        .execute(&self.pool)
        .await?;

        Ok(result.rows_affected() == 1)
    }

    pub async fn update_apple_entitlement_from_notification(
        &self,
        original_transaction_id: &str,
    ) -> Result<(), sqlx::Error> {
        let mut tx = self.pool.begin().await?;

        sqlx::query(
            "WITH latest_notification AS (
                SELECT
                    latest_transaction_id,
                    product_id,
                    subscription_status,
                    expires_at,
                    environment
                FROM apple_server_notifications
                WHERE original_transaction_id = $1
                  AND latest_transaction_id IS NOT NULL
                  AND product_id IS NOT NULL
                  AND subscription_status IS NOT NULL
                  AND environment IS NOT NULL
                ORDER BY event_signed_at DESC, processed_at DESC
                LIMIT 1
             ),
             updated_entitlement AS (
                UPDATE premium_entitlements
                SET status = latest_notification.subscription_status,
                    product_id = latest_notification.product_id,
                    expires_at = latest_notification.expires_at,
                    app_store_latest_transaction_id = latest_notification.latest_transaction_id,
                    app_store_environment = latest_notification.environment
                FROM latest_notification
                WHERE source = 'apple'
                  AND app_store_original_transaction_id = $1
                  AND deleted_at IS NULL
                RETURNING
                    premium_entitlements.user_id,
                    premium_entitlements.status,
                    premium_entitlements.product_id,
                    premium_entitlements.expires_at,
                    premium_entitlements.app_store_latest_transaction_id,
                    premium_entitlements.app_store_environment
             )
             UPDATE users
             SET subscription_source = 'apple',
                 subscription_status = updated_entitlement.status,
                 subscription_product_id = updated_entitlement.product_id,
                 subscription_expires_at = updated_entitlement.expires_at,
                 app_store_latest_transaction_id = updated_entitlement.app_store_latest_transaction_id,
                 app_store_environment = updated_entitlement.app_store_environment
             FROM updated_entitlement
             WHERE users.id = updated_entitlement.user_id",
        )
        .bind(original_transaction_id)
        .execute(&mut *tx)
        .await?;

        tx.commit().await?;
        Ok(())
    }

    /// Update theme palettes within a transaction.
    pub async fn update_theme_palettes_tx(
        tx: &mut Transaction<'_, Postgres>,
        user_id: Uuid,
        palettes: &UserThemePalettesRow,
    ) -> Result<(), sqlx::Error> {
        sqlx::query(
            "UPDATE users
             SET theme_palette_main = $2,
                 theme_palette_accent = $3
             WHERE id = $1",
        )
        .bind(user_id)
        .bind(&palettes.main)
        .bind(&palettes.accent)
        .execute(&mut **tx)
        .await?;
        Ok(())
    }

    // ============================================================================
    // Transaction Support for Unified Sync
    // ============================================================================

    /// Begin a new database transaction
    pub async fn begin_transaction(&self) -> Result<Transaction<'_, Postgres>, sqlx::Error> {
        self.pool.begin().await
    }

    /// Upsert a recurringTask within a transaction
    pub async fn upsert_recurring_task_tx(
        tx: &mut Transaction<'_, Postgres>,
        user_id: Uuid,
        recurring_task: &UpsertRecurringTaskOptions,
    ) -> Result<RecurringTaskRow, sqlx::Error> {
        sqlx::query_as(
            "INSERT INTO tasks (id, user_id, recurring, name, description, created_at, deleted_at, min_daily_frequency, base_price, lockout_duration_seconds, pinned, hidden, timer_mode, timer_id, server_revision)
             VALUES ($1, $2, TRUE, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
             ON CONFLICT (id) DO UPDATE SET
                name = EXCLUDED.name,
                description = EXCLUDED.description,
                deleted_at = EXCLUDED.deleted_at,
                min_daily_frequency = EXCLUDED.min_daily_frequency,
                base_price = EXCLUDED.base_price,
                lockout_duration_seconds = EXCLUDED.lockout_duration_seconds,
                pinned = EXCLUDED.pinned,
                hidden = EXCLUDED.hidden,
                timer_mode = EXCLUDED.timer_mode,
                timer_id = EXCLUDED.timer_id,
                server_revision = EXCLUDED.server_revision
             WHERE tasks.user_id = $2
               AND tasks.recurring = TRUE
             RETURNING id, name, created_at, updated_at, deleted_at, description, min_daily_frequency, base_price, lockout_duration_seconds, pinned, hidden, timer_mode, timer_id, server_revision",
        )
        .bind(recurring_task.id)
        .bind(user_id)
        .bind(&recurring_task.name)
        .bind(&recurring_task.description)
        .bind(recurring_task.created_at)
        .bind(recurring_task.deleted_at)
        .bind(recurring_task.min_daily_frequency)
        .bind(recurring_task.base_price)
        .bind(recurring_task.lockout_duration_seconds)
        .bind(recurring_task.pinned)
        .bind(recurring_task.hidden)
        .bind(&recurring_task.timer_mode)
        .bind(recurring_task.timer_id)
        .bind(recurring_task.server_revision)
        .fetch_one(&mut **tx)
        .await
    }

    /// Upsert a task within a transaction
    pub async fn upsert_task_tx(
        tx: &mut Transaction<'_, Postgres>,
        user_id: Uuid,
        task: &UpsertTaskOptions,
    ) -> Result<TaskRow, sqlx::Error> {
        sqlx::query_as(
            "INSERT INTO tasks (id, user_id, recurring, name, description, created_at, deleted_at, base_price, due_date, pinned, hidden, timer_mode, timer_id, server_revision)
             VALUES ($1, $2, FALSE, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
             ON CONFLICT (id) DO UPDATE SET
                name = EXCLUDED.name,
                description = EXCLUDED.description,
                deleted_at = EXCLUDED.deleted_at,
                base_price = EXCLUDED.base_price,
                due_date = EXCLUDED.due_date,
                pinned = EXCLUDED.pinned,
                hidden = EXCLUDED.hidden,
                timer_mode = EXCLUDED.timer_mode,
                timer_id = EXCLUDED.timer_id,
                server_revision = EXCLUDED.server_revision
             WHERE tasks.user_id = $2
               AND tasks.recurring = FALSE
             RETURNING id, name, description, created_at, updated_at, deleted_at, recurring, base_price, due_date, min_daily_frequency, lockout_duration_seconds, pinned, hidden, timer_mode, timer_id, server_revision",
        )
        .bind(task.id)
        .bind(user_id)
        .bind(&task.name)
        .bind(&task.description)
        .bind(task.created_at)
        .bind(task.deleted_at)
        .bind(task.base_price)
        .bind(task.due_date)
        .bind(task.pinned)
        .bind(task.hidden)
        .bind(&task.timer_mode)
        .bind(task.timer_id)
        .bind(task.server_revision)
        .fetch_one(&mut **tx)
        .await
    }

    pub async fn upsert_timer_tx(
        tx: &mut Transaction<'_, Postgres>,
        user_id: Uuid,
        timer: &UpsertTimerOptions,
    ) -> Result<TimerRow, sqlx::Error> {
        sqlx::query_as(
            "INSERT INTO timers (id, user_id, name, intervals, created_at, deleted_at, server_revision)
             VALUES ($1, $2, $3, $4, $5, $6, $7)
             ON CONFLICT (id) DO UPDATE SET
                name = EXCLUDED.name,
                intervals = EXCLUDED.intervals,
                deleted_at = EXCLUDED.deleted_at,
                server_revision = EXCLUDED.server_revision
             WHERE timers.user_id = $2
             RETURNING id, name, intervals, created_at, updated_at, deleted_at, server_revision",
        )
        .bind(timer.id)
        .bind(user_id)
        .bind(&timer.name)
        .bind(&timer.intervals)
        .bind(timer.created_at)
        .bind(timer.deleted_at)
        .bind(timer.server_revision)
        .fetch_one(&mut **tx)
        .await
    }

    /// Upsert a trade within a transaction.
    pub async fn upsert_trade_tx(
        tx: &mut Transaction<'_, Postgres>,
        user_id: Uuid,
        trade: &UpsertTradeOptions,
    ) -> Result<TradeRow, sqlx::Error> {
        validate_trade_shape(trade)?;

        // Validate task belongs to user if task_id is provided
        if let Some(task_id) = trade.task_id {
            let task_valid: Option<(Uuid,)> = sqlx::query_as(
                "SELECT id FROM tasks
                 WHERE id = $1 AND user_id = $2 AND recurring = FALSE",
            )
            .bind(task_id)
            .bind(user_id)
            .fetch_optional(&mut **tx)
            .await?;

            if task_valid.is_none() {
                return Err(sqlx::Error::RowNotFound);
            }
        }

        // Validate recurringTask belongs to user if recurring_task_id is provided
        if let Some(recurring_task_id) = trade.recurring_task_id {
            let recurring_task_valid: Option<(Uuid,)> = sqlx::query_as(
                "SELECT id FROM tasks
                 WHERE id = $1 AND user_id = $2 AND recurring = TRUE",
            )
            .bind(recurring_task_id)
            .bind(user_id)
            .fetch_optional(&mut **tx)
            .await?;

            if recurring_task_valid.is_none() {
                return Err(sqlx::Error::RowNotFound);
            }
        }

        // Validate reward belongs to user if reward_id is provided
        if let Some(reward_id) = trade.reward_id {
            let reward_valid: Option<(Uuid, bool)> = sqlx::query_as(
                "SELECT id, recurring FROM rewards WHERE id = $1 AND user_id = $2 FOR UPDATE",
            )
            .bind(reward_id)
            .bind(user_id)
            .fetch_optional(&mut **tx)
            .await?;

            let Some((_, recurring)) = reward_valid else {
                return Err(sqlx::Error::RowNotFound);
            };

            if !recurring && trade.refunds_trade_id.is_none() && trade.deleted_at.is_none() {
                let active_purchase_exists: Option<(Uuid,)> = sqlx::query_as(
                    "SELECT purchase.id
                     FROM trades purchase
                     WHERE purchase.user_id = $1
                       AND purchase.reward_id = $2
                       AND purchase.id <> $3
                       AND purchase.deleted_at IS NULL
                       AND purchase.refunds_trade_id IS NULL
                       AND NOT EXISTS (
                           SELECT 1
                           FROM trades refund
                           WHERE refund.refunds_trade_id = purchase.id
                             AND refund.deleted_at IS NULL
                       )
                     LIMIT 1",
                )
                .bind(user_id)
                .bind(reward_id)
                .bind(trade.id)
                .fetch_optional(&mut **tx)
                .await?;

                if active_purchase_exists.is_some() {
                    return Err(sqlx::Error::Protocol(
                        "One-off rewards can only be purchased once unless the purchase is refunded or deleted."
                            .into(),
                    ));
                }
            }
        }

        if let Some(refunds_trade_id) = trade.refunds_trade_id {
            let refunded_trade: Option<TradeRow> = sqlx::query_as(
                "SELECT id, task_id, recurring_task_id, reward_id, source_name, amount, vault_amount_micro, adjustment_base_amount, one_time_adjustment_multiplier, trade_kind, vault_interest_hour, created_at, updated_at, deleted_at, refunds_trade_id, server_revision
                 FROM trades
                 WHERE id = $1 AND user_id = $2",
            )
            .bind(refunds_trade_id)
            .bind(user_id)
            .fetch_optional(&mut **tx)
            .await?;

            let refunded_trade = refunded_trade.ok_or(sqlx::Error::RowNotFound)?;

            if refunded_trade.deleted_at.is_some() || refunded_trade.refunds_trade_id.is_some() {
                return Err(sqlx::Error::Protocol(
                    "Refund trades must target an active non-refund trade".into(),
                ));
            }

            if refunded_trade.trade_kind == "vaultDeposit"
                || refunded_trade.trade_kind == "vaultInterest"
            {
                return Err(sqlx::Error::Protocol(
                    "Vault deposits and interest cannot be refunded".into(),
                ));
            }

            if refunded_trade.task_id != trade.task_id
                || refunded_trade.recurring_task_id != trade.recurring_task_id
                || refunded_trade.reward_id != trade.reward_id
                || refunded_trade.trade_kind != trade.trade_kind
            {
                return Err(sqlx::Error::Protocol(
                    "Refund trades must match the original trade source".into(),
                ));
            }

            if trade.amount != -refunded_trade.amount {
                return Err(sqlx::Error::Protocol(
                    "Refund trades must negate the original trade amount".into(),
                ));
            }

            if trade.vault_amount_micro != refunded_trade.vault_amount_micro.map(|amount| -amount) {
                return Err(sqlx::Error::Protocol(
                    "Refund trades must negate the original vault amount".into(),
                ));
            }

            if trade.created_at < refunded_trade.created_at {
                return Err(sqlx::Error::Protocol(
                    "Refund trades cannot be created before the original trade.".into(),
                ));
            }

            let latest_trade_id = Self::latest_unresolved_trade_id_for_source_tx(
                tx,
                user_id,
                trade.task_id,
                trade.recurring_task_id,
                trade.reward_id,
                &trade.trade_kind,
            )
            .await?;

            if latest_trade_id != Some(refunds_trade_id) {
                return Err(sqlx::Error::Protocol(
                    "Refund trades may only reverse the latest unresolved trade for that source"
                        .into(),
                ));
            }
        }

        // Upsert the trade
        sqlx::query_as(
            "INSERT INTO trades (id, user_id, task_id, recurring_task_id, reward_id, source_name, amount, vault_amount_micro, adjustment_base_amount, one_time_adjustment_multiplier, trade_kind, vault_interest_hour, created_at, deleted_at, refunds_trade_id, server_revision)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16)
             ON CONFLICT (id) DO UPDATE SET
                source_name = EXCLUDED.source_name,
                vault_amount_micro = EXCLUDED.vault_amount_micro,
                adjustment_base_amount = EXCLUDED.adjustment_base_amount,
                one_time_adjustment_multiplier = EXCLUDED.one_time_adjustment_multiplier,
                trade_kind = EXCLUDED.trade_kind,
                vault_interest_hour = EXCLUDED.vault_interest_hour,
                deleted_at = EXCLUDED.deleted_at,
                refunds_trade_id = EXCLUDED.refunds_trade_id,
                server_revision = EXCLUDED.server_revision
             WHERE trades.user_id = $2
             RETURNING id, task_id, recurring_task_id, reward_id, source_name, amount, vault_amount_micro, adjustment_base_amount, one_time_adjustment_multiplier, trade_kind, vault_interest_hour, created_at, updated_at, deleted_at, refunds_trade_id, server_revision",
        )
        .bind(trade.id)
        .bind(user_id)
        .bind(trade.task_id)
        .bind(trade.recurring_task_id)
        .bind(trade.reward_id)
        .bind(&trade.source_name)
        .bind(trade.amount)
        .bind(trade.vault_amount_micro)
        .bind(trade.adjustment_base_amount)
        .bind(trade.one_time_adjustment_multiplier)
        .bind(&trade.trade_kind)
        .bind(trade.vault_interest_hour)
        .bind(trade.created_at)
        .bind(trade.deleted_at)
        .bind(trade.refunds_trade_id)
        .bind(trade.server_revision)
        .fetch_one(&mut **tx)
        .await
    }

    /// Upsert a task_tag association within a transaction
    pub async fn upsert_task_tag_tx(
        tx: &mut Transaction<'_, Postgres>,
        user_id: Uuid,
        task_tag: &UpsertTaskTagOptions,
    ) -> Result<TaskTagRow, sqlx::Error> {
        let task_valid: Option<(Uuid,)> = sqlx::query_as(
            "SELECT id FROM tasks WHERE id = $1 AND user_id = $2 AND recurring = FALSE",
        )
        .bind(task_tag.task_id)
        .bind(user_id)
        .fetch_optional(&mut **tx)
        .await?;

        if task_valid.is_none() {
            return Err(sqlx::Error::RowNotFound);
        }

        let tag_valid: Option<(Uuid,)> =
            sqlx::query_as("SELECT id FROM tags WHERE id = $1 AND user_id = $2")
                .bind(task_tag.tag_id)
                .bind(user_id)
                .fetch_optional(&mut **tx)
                .await?;

        if tag_valid.is_none() {
            return Err(sqlx::Error::RowNotFound);
        }

        sqlx::query_as(
            "INSERT INTO task_tags (task_id, tag_id, created_at, deleted_at, server_revision)
             VALUES ($1, $2, $3, $4, $5)
             ON CONFLICT (task_id, tag_id) DO UPDATE SET
                deleted_at = EXCLUDED.deleted_at,
                server_revision = EXCLUDED.server_revision
             RETURNING task_id, tag_id, created_at, updated_at, deleted_at, server_revision",
        )
        .bind(task_tag.task_id)
        .bind(task_tag.tag_id)
        .bind(task_tag.created_at)
        .bind(task_tag.deleted_at)
        .bind(task_tag.server_revision)
        .fetch_one(&mut **tx)
        .await
    }

    /// Upsert a task-task dependency within a transaction
    pub async fn upsert_task_task_dependency_tx(
        tx: &mut Transaction<'_, Postgres>,
        user_id: Uuid,
        dependency: &UpsertTaskTaskDependencyOptions,
    ) -> Result<TaskTaskDependencyRow, sqlx::Error> {
        let task_valid: Option<(Uuid,)> = sqlx::query_as(
            "SELECT id FROM tasks WHERE id = $1 AND user_id = $2 AND recurring = FALSE",
        )
        .bind(dependency.task_id)
        .bind(user_id)
        .fetch_optional(&mut **tx)
        .await?;

        if task_valid.is_none() {
            return Err(sqlx::Error::RowNotFound);
        }

        let depends_on_task_valid: Option<(Uuid,)> = sqlx::query_as(
            "SELECT id FROM tasks WHERE id = $1 AND user_id = $2 AND recurring = FALSE",
        )
        .bind(dependency.depends_on_task_id)
        .bind(user_id)
        .fetch_optional(&mut **tx)
        .await?;

        if depends_on_task_valid.is_none() {
            return Err(sqlx::Error::RowNotFound);
        }

        sqlx::query_as(
            "INSERT INTO task_task_dependencies (task_id, depends_on_task_id, created_at, deleted_at, server_revision)
             VALUES ($1, $2, $3, $4, $5)
             ON CONFLICT (task_id, depends_on_task_id) DO UPDATE SET
                deleted_at = EXCLUDED.deleted_at,
                server_revision = EXCLUDED.server_revision
             RETURNING task_id, depends_on_task_id, created_at, updated_at, deleted_at, server_revision",
        )
        .bind(dependency.task_id)
        .bind(dependency.depends_on_task_id)
        .bind(dependency.created_at)
        .bind(dependency.deleted_at)
        .bind(dependency.server_revision)
        .fetch_one(&mut **tx)
        .await
    }

    /// Upsert a task-recurringTask dependency within a transaction
    pub async fn upsert_task_recurring_task_dependency_tx(
        tx: &mut Transaction<'_, Postgres>,
        user_id: Uuid,
        dependency: &UpsertTaskRecurringTaskDependencyOptions,
    ) -> Result<TaskRecurringTaskDependencyRow, sqlx::Error> {
        let task_valid: Option<(Uuid,)> = sqlx::query_as(
            "SELECT id FROM tasks WHERE id = $1 AND user_id = $2 AND recurring = FALSE",
        )
        .bind(dependency.task_id)
        .bind(user_id)
        .fetch_optional(&mut **tx)
        .await?;

        if task_valid.is_none() {
            return Err(sqlx::Error::RowNotFound);
        }

        let recurring_task_valid: Option<(Uuid,)> = sqlx::query_as(
            "SELECT id FROM tasks WHERE id = $1 AND user_id = $2 AND recurring = TRUE",
        )
        .bind(dependency.recurring_task_id)
        .bind(user_id)
        .fetch_optional(&mut **tx)
        .await?;

        if recurring_task_valid.is_none() {
            return Err(sqlx::Error::RowNotFound);
        }

        sqlx::query_as(
            "INSERT INTO task_recurring_task_dependencies (task_id, recurring_task_id, required_completions, baseline_completion_count, created_at, deleted_at, server_revision)
             VALUES ($1, $2, $3, $4, $5, $6, $7)
             ON CONFLICT (task_id, recurring_task_id) DO UPDATE SET
                required_completions = EXCLUDED.required_completions,
                baseline_completion_count = EXCLUDED.baseline_completion_count,
                deleted_at = EXCLUDED.deleted_at,
                server_revision = EXCLUDED.server_revision
             RETURNING task_id, recurring_task_id, required_completions, baseline_completion_count, created_at, updated_at, deleted_at, server_revision",
        )
        .bind(dependency.task_id)
        .bind(dependency.recurring_task_id)
        .bind(dependency.required_completions)
        .bind(dependency.baseline_completion_count)
        .bind(dependency.created_at)
        .bind(dependency.deleted_at)
        .bind(dependency.server_revision)
        .fetch_one(&mut **tx)
        .await
    }

    pub async fn upsert_reward_task_dependency_tx(
        tx: &mut Transaction<'_, Postgres>,
        user_id: Uuid,
        dependency: &UpsertRewardTaskDependencyOptions,
    ) -> Result<RewardTaskDependencyRow, sqlx::Error> {
        let reward_valid: Option<(Uuid,)> =
            sqlx::query_as("SELECT id FROM rewards WHERE id = $1 AND user_id = $2")
                .bind(dependency.reward_id)
                .bind(user_id)
                .fetch_optional(&mut **tx)
                .await?;

        if reward_valid.is_none() {
            return Err(sqlx::Error::RowNotFound);
        }

        let task_valid: Option<(Uuid,)> = sqlx::query_as(
            "SELECT id FROM tasks WHERE id = $1 AND user_id = $2 AND recurring = FALSE",
        )
        .bind(dependency.depends_on_task_id)
        .bind(user_id)
        .fetch_optional(&mut **tx)
        .await?;

        if task_valid.is_none() {
            return Err(sqlx::Error::RowNotFound);
        }

        sqlx::query_as(
            "INSERT INTO reward_task_dependencies (reward_id, depends_on_task_id, created_at, deleted_at, server_revision)
             VALUES ($1, $2, $3, $4, $5)
             ON CONFLICT (reward_id, depends_on_task_id) DO UPDATE SET
                deleted_at = EXCLUDED.deleted_at,
                server_revision = EXCLUDED.server_revision
             RETURNING reward_id, depends_on_task_id, created_at, updated_at, deleted_at, server_revision",
        )
        .bind(dependency.reward_id)
        .bind(dependency.depends_on_task_id)
        .bind(dependency.created_at)
        .bind(dependency.deleted_at)
        .bind(dependency.server_revision)
        .fetch_one(&mut **tx)
        .await
    }

    pub async fn upsert_reward_recurring_task_dependency_tx(
        tx: &mut Transaction<'_, Postgres>,
        user_id: Uuid,
        dependency: &UpsertRewardRecurringTaskDependencyOptions,
    ) -> Result<RewardRecurringTaskDependencyRow, sqlx::Error> {
        let reward_valid: Option<(Uuid,)> =
            sqlx::query_as("SELECT id FROM rewards WHERE id = $1 AND user_id = $2")
                .bind(dependency.reward_id)
                .bind(user_id)
                .fetch_optional(&mut **tx)
                .await?;

        if reward_valid.is_none() {
            return Err(sqlx::Error::RowNotFound);
        }

        let recurring_task_valid: Option<(Uuid,)> = sqlx::query_as(
            "SELECT id FROM tasks WHERE id = $1 AND user_id = $2 AND recurring = TRUE",
        )
        .bind(dependency.recurring_task_id)
        .bind(user_id)
        .fetch_optional(&mut **tx)
        .await?;

        if recurring_task_valid.is_none() {
            return Err(sqlx::Error::RowNotFound);
        }

        sqlx::query_as(
            "INSERT INTO reward_recurring_task_dependencies (reward_id, recurring_task_id, required_completions, baseline_completion_count, created_at, deleted_at, server_revision)
             VALUES ($1, $2, $3, $4, $5, $6, $7)
             ON CONFLICT (reward_id, recurring_task_id) DO UPDATE SET
                required_completions = EXCLUDED.required_completions,
                baseline_completion_count = EXCLUDED.baseline_completion_count,
                deleted_at = EXCLUDED.deleted_at,
                server_revision = EXCLUDED.server_revision
             RETURNING reward_id, recurring_task_id, required_completions, baseline_completion_count, created_at, updated_at, deleted_at, server_revision",
        )
        .bind(dependency.reward_id)
        .bind(dependency.recurring_task_id)
        .bind(dependency.required_completions)
        .bind(dependency.baseline_completion_count)
        .bind(dependency.created_at)
        .bind(dependency.deleted_at)
        .bind(dependency.server_revision)
        .fetch_one(&mut **tx)
        .await
    }

    async fn latest_unresolved_trade_id_for_source_tx(
        tx: &mut Transaction<'_, Postgres>,
        user_id: Uuid,
        task_id: Option<Uuid>,
        recurring_task_id: Option<Uuid>,
        reward_id: Option<Uuid>,
        trade_kind: &str,
    ) -> Result<Option<Uuid>, sqlx::Error> {
        sqlx::query_scalar(
            "SELECT candidate.id
             FROM trades candidate
             WHERE candidate.user_id = $1
               AND candidate.deleted_at IS NULL
               AND candidate.refunds_trade_id IS NULL
               AND candidate.task_id IS NOT DISTINCT FROM $2
               AND candidate.recurring_task_id IS NOT DISTINCT FROM $3
               AND candidate.reward_id IS NOT DISTINCT FROM $4
               AND candidate.trade_kind = $5
               AND NOT EXISTS (
                    SELECT 1
                    FROM trades refund
                    WHERE refund.refunds_trade_id = candidate.id
                      AND refund.deleted_at IS NULL
               )
             ORDER BY candidate.created_at DESC, candidate.updated_at DESC, candidate.id DESC
             LIMIT 1",
        )
        .bind(user_id)
        .bind(task_id)
        .bind(recurring_task_id)
        .bind(reward_id)
        .bind(trade_kind)
        .fetch_optional(&mut **tx)
        .await
    }

    pub async fn active_reward_purchase_trade_exists_tx(
        tx: &mut Transaction<'_, Postgres>,
        user_id: Uuid,
        trade_id: Uuid,
    ) -> Result<bool, sqlx::Error> {
        sqlx::query_scalar(
            "SELECT EXISTS (
                SELECT 1
                FROM trades
                WHERE id = $1
                  AND user_id = $2
                  AND reward_id IS NOT NULL
                  AND trade_kind IN ('rewardPurchase', 'vaultRewardPurchase')
                  AND deleted_at IS NULL
                  AND refunds_trade_id IS NULL
            )",
        )
        .bind(trade_id)
        .bind(user_id)
        .fetch_one(&mut **tx)
        .await
    }

    pub async fn task_has_incomplete_dependencies_tx(
        tx: &mut Transaction<'_, Postgres>,
        user_id: Uuid,
        task_id: Uuid,
    ) -> Result<bool, sqlx::Error> {
        let dependency_task_is_completed = active_unresolved_task_trade_exists_sql(
            "dependency_task.id",
            "dependency_task.user_id",
        );
        let blocked_by_task: bool = sqlx::query_scalar(&format!(
            "SELECT EXISTS (
                SELECT 1
                FROM task_task_dependencies ttd
                JOIN tasks dependency_task ON dependency_task.id = ttd.depends_on_task_id
                WHERE ttd.task_id = $2
                  AND ttd.deleted_at IS NULL
                  AND dependency_task.user_id = $1
                  AND dependency_task.recurring = FALSE
                  AND (dependency_task.deleted_at IS NOT NULL OR NOT {})
            )",
            dependency_task_is_completed
        ))
        .bind(user_id)
        .bind(task_id)
        .fetch_one(&mut **tx)
        .await?;

        if blocked_by_task {
            return Ok(true);
        }

        let blocked_by_recurring_task: bool = sqlx::query_scalar(
            "SELECT EXISTS (
                SELECT 1
                FROM task_recurring_task_dependencies thd
                WHERE thd.task_id = $2
                  AND thd.deleted_at IS NULL
                  AND (
                    SELECT COUNT(*)
                    FROM trades trade
                    WHERE trade.user_id = $1
                      AND trade.recurring_task_id = thd.recurring_task_id
                      AND trade.deleted_at IS NULL
                      AND trade.refunds_trade_id IS NULL
                      AND NOT EXISTS (
                        SELECT 1
                        FROM trades refund
                        WHERE refund.refunds_trade_id = trade.id
                          AND refund.deleted_at IS NULL
                      )
                  ) < (thd.baseline_completion_count + thd.required_completions)
            )",
        )
        .bind(user_id)
        .bind(task_id)
        .fetch_one(&mut **tx)
        .await?;

        Ok(blocked_by_recurring_task)
    }

    pub async fn reward_has_incomplete_dependencies_tx(
        tx: &mut Transaction<'_, Postgres>,
        user_id: Uuid,
        reward_id: Uuid,
    ) -> Result<bool, sqlx::Error> {
        let dependency_task_is_completed = active_unresolved_task_trade_exists_sql(
            "dependency_task.id",
            "dependency_task.user_id",
        );
        let blocked_by_task: bool = sqlx::query_scalar(&format!(
            "SELECT EXISTS (
                SELECT 1
                FROM reward_task_dependencies rtd
                JOIN tasks dependency_task ON dependency_task.id = rtd.depends_on_task_id
                WHERE rtd.reward_id = $2
                  AND rtd.deleted_at IS NULL
                  AND dependency_task.user_id = $1
                  AND dependency_task.recurring = FALSE
                  AND (dependency_task.deleted_at IS NOT NULL OR NOT {})
            )",
            dependency_task_is_completed
        ))
        .bind(user_id)
        .bind(reward_id)
        .fetch_one(&mut **tx)
        .await?;

        if blocked_by_task {
            return Ok(true);
        }

        let blocked_by_recurring_task: bool = sqlx::query_scalar(
            "SELECT EXISTS (
                SELECT 1
                FROM reward_recurring_task_dependencies rhd
                WHERE rhd.reward_id = $2
                  AND rhd.deleted_at IS NULL
                  AND (
                    SELECT COUNT(*)
                    FROM trades trade
                    WHERE trade.user_id = $1
                      AND trade.recurring_task_id = rhd.recurring_task_id
                      AND trade.deleted_at IS NULL
                      AND trade.refunds_trade_id IS NULL
                      AND NOT EXISTS (
                        SELECT 1
                        FROM trades refund
                        WHERE refund.refunds_trade_id = trade.id
                          AND refund.deleted_at IS NULL
                      )
                  ) < (rhd.baseline_completion_count + rhd.required_completions)
            )",
        )
        .bind(user_id)
        .bind(reward_id)
        .fetch_one(&mut **tx)
        .await?;

        Ok(blocked_by_recurring_task)
    }

    pub async fn reset_reward_recurring_task_dependencies_tx(
        tx: &mut Transaction<'_, Postgres>,
        user_id: Uuid,
        reward_id: Uuid,
        server_revision: i64,
    ) -> Result<Vec<RewardRecurringTaskDependencyRow>, sqlx::Error> {
        sqlx::query_as(
            "UPDATE reward_recurring_task_dependencies rhd
             SET baseline_completion_count = (
                SELECT COUNT(*)::integer
                FROM trades trade
                WHERE trade.user_id = $1
                  AND trade.recurring_task_id = rhd.recurring_task_id
                  AND trade.deleted_at IS NULL
                  AND trade.refunds_trade_id IS NULL
                  AND NOT EXISTS (
                    SELECT 1
                    FROM trades refund
                    WHERE refund.refunds_trade_id = trade.id
                      AND refund.deleted_at IS NULL
                  )
             ),
                 server_revision = $3
             FROM rewards reward
             WHERE reward.id = rhd.reward_id
               AND reward.user_id = $1
               AND rhd.reward_id = $2
               AND rhd.deleted_at IS NULL
             RETURNING rhd.reward_id, rhd.recurring_task_id, rhd.required_completions, rhd.baseline_completion_count, rhd.created_at, rhd.updated_at, rhd.deleted_at, rhd.server_revision",
        )
        .bind(user_id)
        .bind(reward_id)
        .bind(server_revision)
        .fetch_all(&mut **tx)
        .await
    }

    pub async fn user_has_task_dependency_cycles_tx(
        tx: &mut Transaction<'_, Postgres>,
        user_id: Uuid,
    ) -> Result<bool, sqlx::Error> {
        sqlx::query_scalar(
            "WITH RECURSIVE reach(task_id, depends_on_task_id) AS (
                SELECT ttd.task_id, ttd.depends_on_task_id
                FROM task_task_dependencies ttd
                JOIN tasks t ON ttd.task_id = t.id
                WHERE t.user_id = $1
                  AND t.recurring = FALSE
                  AND ttd.deleted_at IS NULL
                UNION
                SELECT reach.task_id, ttd.depends_on_task_id
                FROM reach
                JOIN task_task_dependencies ttd
                  ON ttd.task_id = reach.depends_on_task_id
                WHERE ttd.deleted_at IS NULL
            )
            SELECT EXISTS (
                SELECT 1
                FROM reach
                WHERE task_id = depends_on_task_id
            )",
        )
        .bind(user_id)
        .fetch_one(&mut **tx)
        .await
    }

    pub async fn soft_delete_task_task_dependencies_for_task_tx(
        tx: &mut Transaction<'_, Postgres>,
        user_id: Uuid,
        task_id: Uuid,
        deleted_at: NaiveDateTime,
        server_revision: i64,
    ) -> Result<Vec<TaskTaskDependencyRow>, sqlx::Error> {
        sqlx::query_as(
            "UPDATE task_task_dependencies ttd
             SET deleted_at = $3,
                 server_revision = $4
             FROM tasks dependent_task
             WHERE dependent_task.id = ttd.task_id
               AND dependent_task.user_id = $1
               AND dependent_task.recurring = FALSE
               AND ttd.deleted_at IS NULL
               AND (ttd.task_id = $2 OR ttd.depends_on_task_id = $2)
             RETURNING ttd.task_id, ttd.depends_on_task_id, ttd.created_at, ttd.updated_at, ttd.deleted_at, ttd.server_revision",
        )
        .bind(user_id)
        .bind(task_id)
        .bind(deleted_at)
        .bind(server_revision)
        .fetch_all(&mut **tx)
        .await
    }

    pub async fn soft_delete_task_recurring_task_dependencies_for_task_tx(
        tx: &mut Transaction<'_, Postgres>,
        user_id: Uuid,
        task_id: Uuid,
        deleted_at: NaiveDateTime,
        server_revision: i64,
    ) -> Result<Vec<TaskRecurringTaskDependencyRow>, sqlx::Error> {
        sqlx::query_as(
            "UPDATE task_recurring_task_dependencies thd
             SET deleted_at = $3,
                 server_revision = $4
             FROM tasks dependent_task
             WHERE dependent_task.id = thd.task_id
               AND dependent_task.user_id = $1
               AND dependent_task.recurring = FALSE
               AND thd.deleted_at IS NULL
               AND thd.task_id = $2
             RETURNING thd.task_id, thd.recurring_task_id, thd.required_completions, thd.baseline_completion_count, thd.created_at, thd.updated_at, thd.deleted_at, thd.server_revision",
        )
        .bind(user_id)
        .bind(task_id)
        .bind(deleted_at)
        .bind(server_revision)
        .fetch_all(&mut **tx)
        .await
    }

    pub async fn soft_delete_reward_task_dependencies_for_task_tx(
        tx: &mut Transaction<'_, Postgres>,
        user_id: Uuid,
        task_id: Uuid,
        deleted_at: NaiveDateTime,
        server_revision: i64,
    ) -> Result<Vec<RewardTaskDependencyRow>, sqlx::Error> {
        sqlx::query_as(
            "UPDATE reward_task_dependencies rtd
             SET deleted_at = $3,
                 server_revision = $4
             FROM rewards dependent_reward
             WHERE dependent_reward.id = rtd.reward_id
               AND dependent_reward.user_id = $1
               AND rtd.deleted_at IS NULL
               AND rtd.depends_on_task_id = $2
             RETURNING rtd.reward_id, rtd.depends_on_task_id, rtd.created_at, rtd.updated_at, rtd.deleted_at, rtd.server_revision",
        )
        .bind(user_id)
        .bind(task_id)
        .bind(deleted_at)
        .bind(server_revision)
        .fetch_all(&mut **tx)
        .await
    }

    pub async fn soft_delete_reward_dependencies_for_reward_tx(
        tx: &mut Transaction<'_, Postgres>,
        user_id: Uuid,
        reward_id: Uuid,
        deleted_at: NaiveDateTime,
        server_revision: i64,
    ) -> Result<
        (
            Vec<RewardTaskDependencyRow>,
            Vec<RewardRecurringTaskDependencyRow>,
        ),
        sqlx::Error,
    > {
        let deleted_task_dependencies = sqlx::query_as(
            "UPDATE reward_task_dependencies rtd
             SET deleted_at = $3,
                 server_revision = $4
             FROM rewards dependent_reward
             WHERE dependent_reward.id = rtd.reward_id
               AND dependent_reward.user_id = $1
               AND rtd.deleted_at IS NULL
               AND rtd.reward_id = $2
             RETURNING rtd.reward_id, rtd.depends_on_task_id, rtd.created_at, rtd.updated_at, rtd.deleted_at, rtd.server_revision",
        )
        .bind(user_id)
        .bind(reward_id)
        .bind(deleted_at)
        .bind(server_revision)
        .fetch_all(&mut **tx)
        .await?;

        let deleted_recurring_task_dependencies = sqlx::query_as(
            "UPDATE reward_recurring_task_dependencies rhd
             SET deleted_at = $3,
                 server_revision = $4
             FROM rewards dependent_reward
             WHERE dependent_reward.id = rhd.reward_id
               AND dependent_reward.user_id = $1
               AND rhd.deleted_at IS NULL
               AND rhd.reward_id = $2
             RETURNING rhd.reward_id, rhd.recurring_task_id, rhd.required_completions, rhd.baseline_completion_count, rhd.created_at, rhd.updated_at, rhd.deleted_at, rhd.server_revision",
        )
        .bind(user_id)
        .bind(reward_id)
        .bind(deleted_at)
        .bind(server_revision)
        .fetch_all(&mut **tx)
        .await?;

        Ok((
            deleted_task_dependencies,
            deleted_recurring_task_dependencies,
        ))
    }

    pub async fn recurring_task_has_active_dependents_tx(
        tx: &mut Transaction<'_, Postgres>,
        user_id: Uuid,
        recurring_task_id: Uuid,
    ) -> Result<bool, sqlx::Error> {
        let dependent_task_is_completed =
            active_unresolved_task_trade_exists_sql("dependent_task.id", "dependent_task.user_id");
        sqlx::query_scalar(&format!(
            "SELECT EXISTS (
                SELECT 1
                FROM task_recurring_task_dependencies thd
                JOIN tasks dependent_task ON dependent_task.id = thd.task_id
                WHERE thd.recurring_task_id = $2
                  AND thd.deleted_at IS NULL
                  AND dependent_task.user_id = $1
                  AND dependent_task.recurring = FALSE
                  AND dependent_task.deleted_at IS NULL
                  AND NOT {}
            )",
            dependent_task_is_completed
        ))
        .bind(user_id)
        .bind(recurring_task_id)
        .fetch_one(&mut **tx)
        .await
    }

    pub async fn recurring_task_has_active_reward_dependents_tx(
        tx: &mut Transaction<'_, Postgres>,
        user_id: Uuid,
        recurring_task_id: Uuid,
    ) -> Result<bool, sqlx::Error> {
        sqlx::query_scalar(
            "SELECT EXISTS (
                SELECT 1
                FROM reward_recurring_task_dependencies rhd
                JOIN rewards dependent_reward ON dependent_reward.id = rhd.reward_id
                WHERE rhd.recurring_task_id = $2
                  AND rhd.deleted_at IS NULL
                  AND dependent_reward.user_id = $1
                  AND dependent_reward.deleted_at IS NULL
            )",
        )
        .bind(user_id)
        .bind(recurring_task_id)
        .fetch_one(&mut **tx)
        .await
    }

    /// Calculate a user's balance from non-deleted ledger rows within a transaction.
    pub async fn calculate_balance_from_trades_tx(
        tx: &mut Transaction<'_, Postgres>,
        user_id: Uuid,
    ) -> Result<i64, sqlx::Error> {
        let (total,): (Option<i64>,) = sqlx::query_as(
            "SELECT COALESCE(SUM(amount), 0)
             FROM trades
             WHERE user_id = $1
               AND deleted_at IS NULL
               AND trade_kind IN ('taskCompletion', 'recurringTaskCompletion', 'rewardPurchase', 'vaultDeposit')",
        )
        .bind(user_id)
        .fetch_one(&mut **tx)
        .await?;

        Ok(total.unwrap_or(0))
    }

    /// Upsert a tag within a transaction
    pub async fn upsert_tag_tx(
        tx: &mut Transaction<'_, Postgres>,
        user_id: Uuid,
        tag: &UpsertTagOptions,
    ) -> Result<TagRow, sqlx::Error> {
        sqlx::query_as(
            "INSERT INTO tags (id, user_id, name, color_hex, created_at, deleted_at, server_revision)
             VALUES ($1, $2, $3, $4, $5, $6, $7)
             ON CONFLICT (id) DO UPDATE SET
                name = EXCLUDED.name,
                color_hex = EXCLUDED.color_hex,
                deleted_at = EXCLUDED.deleted_at,
                server_revision = EXCLUDED.server_revision
             WHERE tags.user_id = $2
             RETURNING id, name, color_hex, created_at, updated_at, deleted_at, server_revision",
        )
        .bind(tag.id)
        .bind(user_id)
        .bind(&tag.name)
        .bind(&tag.color_hex)
        .bind(tag.created_at)
        .bind(tag.deleted_at)
        .bind(tag.server_revision)
        .fetch_one(&mut **tx)
        .await
    }

    /// Upsert a recurring_task_tag association within a transaction
    pub async fn upsert_recurring_task_tag_tx(
        tx: &mut Transaction<'_, Postgres>,
        user_id: Uuid,
        recurring_task_tag: &UpsertRecurringTaskTagOptions,
    ) -> Result<RecurringTaskTagRow, sqlx::Error> {
        // Validate recurringTask belongs to user
        let recurring_task_valid: Option<(Uuid,)> = sqlx::query_as(
            "SELECT id FROM tasks WHERE id = $1 AND user_id = $2 AND recurring = TRUE",
        )
        .bind(recurring_task_tag.recurring_task_id)
        .bind(user_id)
        .fetch_optional(&mut **tx)
        .await?;

        if recurring_task_valid.is_none() {
            return Err(sqlx::Error::RowNotFound);
        }

        // Validate tag belongs to user
        let tag_valid: Option<(Uuid,)> =
            sqlx::query_as("SELECT id FROM tags WHERE id = $1 AND user_id = $2")
                .bind(recurring_task_tag.tag_id)
                .bind(user_id)
                .fetch_optional(&mut **tx)
                .await?;

        if tag_valid.is_none() {
            return Err(sqlx::Error::RowNotFound);
        }

        sqlx::query_as(
            "INSERT INTO recurring_task_tags (recurring_task_id, tag_id, created_at, deleted_at, server_revision)
             VALUES ($1, $2, $3, $4, $5)
             ON CONFLICT (recurring_task_id, tag_id) DO UPDATE SET
                deleted_at = EXCLUDED.deleted_at,
                server_revision = EXCLUDED.server_revision
             RETURNING recurring_task_id, tag_id, created_at, updated_at, deleted_at, server_revision",
        )
        .bind(recurring_task_tag.recurring_task_id)
        .bind(recurring_task_tag.tag_id)
        .bind(recurring_task_tag.created_at)
        .bind(recurring_task_tag.deleted_at)
        .bind(recurring_task_tag.server_revision)
        .fetch_one(&mut **tx)
        .await
    }

    /// Upsert a reward within a transaction
    pub async fn upsert_reward_tx(
        tx: &mut Transaction<'_, Postgres>,
        user_id: Uuid,
        reward: &UpsertRewardOptions,
    ) -> Result<RewardRow, sqlx::Error> {
        sqlx::query_as(
            "INSERT INTO rewards (id, user_id, recurring, name, description, created_at, deleted_at, max_daily_frequency, base_price, lockout_duration_seconds, pinned, hidden, timer_mode, timer_id, server_revision)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15)
             ON CONFLICT (id) DO UPDATE SET
                recurring = EXCLUDED.recurring,
                name = EXCLUDED.name,
                description = EXCLUDED.description,
                deleted_at = EXCLUDED.deleted_at,
                max_daily_frequency = EXCLUDED.max_daily_frequency,
                base_price = EXCLUDED.base_price,
                lockout_duration_seconds = EXCLUDED.lockout_duration_seconds,
                pinned = EXCLUDED.pinned,
                hidden = EXCLUDED.hidden,
                timer_mode = EXCLUDED.timer_mode,
                timer_id = EXCLUDED.timer_id,
                server_revision = EXCLUDED.server_revision
             WHERE rewards.user_id = $2
             RETURNING id, recurring, name, description, created_at, updated_at, deleted_at, max_daily_frequency, base_price, lockout_duration_seconds, pinned, hidden, timer_mode, timer_id, server_revision",
        )
        .bind(reward.id)
        .bind(user_id)
        .bind(reward.recurring)
        .bind(&reward.name)
        .bind(&reward.description)
        .bind(reward.created_at)
        .bind(reward.deleted_at)
        .bind(reward.max_daily_frequency)
        .bind(reward.base_price)
        .bind(reward.lockout_duration_seconds)
        .bind(reward.pinned)
        .bind(reward.hidden)
        .bind(&reward.timer_mode)
        .bind(reward.timer_id)
        .bind(reward.server_revision)
        .fetch_one(&mut **tx)
        .await
    }

    /// Upsert a reward_tag association within a transaction
    pub async fn upsert_reward_tag_tx(
        tx: &mut Transaction<'_, Postgres>,
        user_id: Uuid,
        reward_tag: &UpsertRewardTagOptions,
    ) -> Result<RewardTagRow, sqlx::Error> {
        // Validate reward belongs to user
        let reward_valid: Option<(Uuid,)> =
            sqlx::query_as("SELECT id FROM rewards WHERE id = $1 AND user_id = $2")
                .bind(reward_tag.reward_id)
                .bind(user_id)
                .fetch_optional(&mut **tx)
                .await?;

        if reward_valid.is_none() {
            return Err(sqlx::Error::RowNotFound);
        }

        // Validate tag belongs to user
        let tag_valid: Option<(Uuid,)> =
            sqlx::query_as("SELECT id FROM tags WHERE id = $1 AND user_id = $2")
                .bind(reward_tag.tag_id)
                .bind(user_id)
                .fetch_optional(&mut **tx)
                .await?;

        if tag_valid.is_none() {
            return Err(sqlx::Error::RowNotFound);
        }

        sqlx::query_as(
            "INSERT INTO reward_tags (reward_id, tag_id, created_at, deleted_at, server_revision)
             VALUES ($1, $2, $3, $4, $5)
             ON CONFLICT (reward_id, tag_id) DO UPDATE SET
                deleted_at = EXCLUDED.deleted_at,
                server_revision = EXCLUDED.server_revision
             RETURNING reward_id, tag_id, created_at, updated_at, deleted_at, server_revision",
        )
        .bind(reward_tag.reward_id)
        .bind(reward_tag.tag_id)
        .bind(reward_tag.created_at)
        .bind(reward_tag.deleted_at)
        .bind(reward_tag.server_revision)
        .fetch_one(&mut **tx)
        .await
    }
}

pub struct UpsertTaskOptions {
    pub id: Uuid,
    pub name: String,
    pub description: String,
    pub created_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub base_price: i32,
    pub due_date: Option<NaiveDateTime>,
    pub pinned: bool,
    pub hidden: bool,
    pub timer_mode: Option<String>,
    pub timer_id: Option<Uuid>,
    pub server_revision: i64,
}

pub struct UpsertRecurringTaskOptions {
    pub id: Uuid,
    pub name: String,
    pub description: String,
    pub created_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub min_daily_frequency: Option<f64>,
    pub lockout_duration_seconds: Option<i32>,
    pub base_price: i32,
    pub pinned: bool,
    pub hidden: bool,
    pub timer_mode: Option<String>,
    pub timer_id: Option<Uuid>,
    pub server_revision: i64,
}

pub struct UpsertTimerOptions {
    pub id: Uuid,
    pub name: String,
    pub intervals: Value,
    pub created_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub server_revision: i64,
}

pub struct UpsertTradeOptions {
    pub id: Uuid,
    pub task_id: Option<Uuid>,
    pub recurring_task_id: Option<Uuid>,
    pub reward_id: Option<Uuid>,
    pub source_name: Option<String>,
    pub amount: i32,
    pub vault_amount_micro: Option<i64>,
    pub adjustment_base_amount: Option<i32>,
    pub one_time_adjustment_multiplier: Option<f64>,
    pub trade_kind: String,
    pub vault_interest_hour: Option<NaiveDateTime>,
    pub created_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub refunds_trade_id: Option<Uuid>,
    pub server_revision: i64,
}

pub struct UpsertTagOptions {
    pub id: Uuid,
    pub name: String,
    pub color_hex: String,
    pub created_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub server_revision: i64,
}

pub struct UpsertRecurringTaskTagOptions {
    pub recurring_task_id: Uuid,
    pub tag_id: Uuid,
    pub created_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub server_revision: i64,
}

pub struct UpsertTaskTagOptions {
    pub task_id: Uuid,
    pub tag_id: Uuid,
    pub created_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub server_revision: i64,
}

pub struct UpsertTaskTaskDependencyOptions {
    pub task_id: Uuid,
    pub depends_on_task_id: Uuid,
    pub created_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub server_revision: i64,
}

pub struct UpsertTaskRecurringTaskDependencyOptions {
    pub task_id: Uuid,
    pub recurring_task_id: Uuid,
    pub required_completions: i32,
    pub baseline_completion_count: i32,
    pub created_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub server_revision: i64,
}

pub struct UpsertRewardTaskDependencyOptions {
    pub reward_id: Uuid,
    pub depends_on_task_id: Uuid,
    pub created_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub server_revision: i64,
}

pub struct UpsertRewardRecurringTaskDependencyOptions {
    pub reward_id: Uuid,
    pub recurring_task_id: Uuid,
    pub required_completions: i32,
    pub baseline_completion_count: i32,
    pub created_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub server_revision: i64,
}

pub struct UpsertRewardOptions {
    pub id: Uuid,
    pub recurring: bool,
    pub name: String,
    pub description: String,
    pub created_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub max_daily_frequency: Option<f64>,
    pub lockout_duration_seconds: Option<i32>,
    pub base_price: i32,
    pub pinned: bool,
    pub hidden: bool,
    pub timer_mode: Option<String>,
    pub timer_id: Option<Uuid>,
    pub server_revision: i64,
}

pub struct UpsertRewardTagOptions {
    pub reward_id: Uuid,
    pub tag_id: Uuid,
    pub created_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub server_revision: i64,
}

#[derive(sqlx::FromRow)]
pub struct TradeRow {
    pub id: Uuid,
    pub task_id: Option<Uuid>,
    pub recurring_task_id: Option<Uuid>,
    pub reward_id: Option<Uuid>,
    pub source_name: Option<String>,
    pub amount: i32,
    pub vault_amount_micro: Option<i64>,
    pub adjustment_base_amount: Option<i32>,
    pub one_time_adjustment_multiplier: Option<f64>,
    pub trade_kind: String,
    pub vault_interest_hour: Option<NaiveDateTime>,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub refunds_trade_id: Option<Uuid>,
    pub server_revision: i64,
}

#[derive(sqlx::FromRow)]
pub struct UserProfileRow {
    pub email: Option<String>,
    pub subscription_status: String,
    pub subscription_expires_at: Option<NaiveDateTime>,
    pub theme_palette_main: String,
    pub theme_palette_accent: String,
}

#[derive(Clone)]
pub struct UserThemePalettesRow {
    pub main: String,
    pub accent: String,
}

#[derive(sqlx::FromRow)]
pub struct UserRow {
    pub id: Uuid,
}

#[derive(sqlx::FromRow)]
pub struct UserAccountStateRow {
    pub email: Option<String>,
    pub subscription_source: Option<String>,
    pub subscription_status: String,
    pub subscription_product_id: Option<String>,
    pub subscription_expires_at: Option<NaiveDateTime>,
}

#[derive(sqlx::FromRow)]
pub struct RefreshTokenRow {
    pub key: String,
    #[allow(dead_code)]
    pub created_at: NaiveDateTime,
    pub expires_at: Option<NaiveDateTime>,
}

#[derive(sqlx::FromRow)]
pub struct TaskRow {
    pub id: Uuid,
    pub name: String,
    pub description: String,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub recurring: bool,
    pub base_price: i32,
    pub due_date: Option<NaiveDateTime>,
    pub min_daily_frequency: Option<f64>,
    pub lockout_duration_seconds: Option<i32>,
    pub pinned: bool,
    pub hidden: bool,
    pub timer_mode: Option<String>,
    pub timer_id: Option<Uuid>,
    pub server_revision: i64,
}

#[derive(sqlx::FromRow)]
pub struct RecurringTaskRow {
    pub id: Uuid,
    pub name: String,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub description: String,
    pub min_daily_frequency: Option<f64>,
    pub lockout_duration_seconds: Option<i32>,
    pub base_price: i32,
    pub pinned: bool,
    pub hidden: bool,
    pub timer_mode: Option<String>,
    pub timer_id: Option<Uuid>,
    pub server_revision: i64,
}

#[derive(sqlx::FromRow)]
pub struct RewardRow {
    pub id: Uuid,
    pub recurring: bool,
    pub name: String,
    pub description: String,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub max_daily_frequency: Option<f64>,
    pub lockout_duration_seconds: Option<i32>,
    pub base_price: i32,
    pub pinned: bool,
    pub hidden: bool,
    pub timer_mode: Option<String>,
    pub timer_id: Option<Uuid>,
    pub server_revision: i64,
}

#[derive(sqlx::FromRow)]
pub struct TimerRow {
    pub id: Uuid,
    pub name: String,
    pub intervals: Value,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub server_revision: i64,
}

#[derive(sqlx::FromRow)]
pub struct TaskTagRow {
    pub task_id: Uuid,
    pub tag_id: Uuid,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub server_revision: i64,
}

#[derive(sqlx::FromRow)]
pub struct TaskTaskDependencyRow {
    pub task_id: Uuid,
    pub depends_on_task_id: Uuid,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub server_revision: i64,
}

#[derive(sqlx::FromRow)]
pub struct TaskRecurringTaskDependencyRow {
    pub task_id: Uuid,
    pub recurring_task_id: Uuid,
    pub required_completions: i32,
    pub baseline_completion_count: i32,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub server_revision: i64,
}

#[derive(sqlx::FromRow)]
pub struct RewardTaskDependencyRow {
    pub reward_id: Uuid,
    pub depends_on_task_id: Uuid,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub server_revision: i64,
}

#[derive(sqlx::FromRow)]
pub struct RewardRecurringTaskDependencyRow {
    pub reward_id: Uuid,
    pub recurring_task_id: Uuid,
    pub required_completions: i32,
    pub baseline_completion_count: i32,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub server_revision: i64,
}

#[derive(sqlx::FromRow)]
pub struct RewardTagRow {
    pub reward_id: Uuid,
    pub tag_id: Uuid,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub server_revision: i64,
}

#[derive(sqlx::FromRow)]
pub struct TagRow {
    pub id: Uuid,
    pub name: String,
    pub color_hex: String,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub server_revision: i64,
}

#[derive(sqlx::FromRow)]
pub struct RecurringTaskTagRow {
    pub recurring_task_id: Uuid,
    pub tag_id: Uuid,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub deleted_at: Option<NaiveDateTime>,
    pub server_revision: i64,
}
