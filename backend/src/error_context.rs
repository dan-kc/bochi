use sqlx::Error as SqlxError;

pub(crate) struct SqlxErrorContext {
    pub(crate) kind: &'static str,
    pub(crate) database_code: Option<String>,
    pub(crate) database_message: Option<String>,
    pub(crate) database_constraint: Option<String>,
    pub(crate) database_table: Option<String>,
}

impl SqlxErrorContext {
    pub(crate) fn from_error(error: &SqlxError) -> Self {
        let mut context = Self {
            kind: sqlx_error_kind(error),
            database_code: None,
            database_message: None,
            database_constraint: None,
            database_table: None,
        };

        if let SqlxError::Database(database_error) = error {
            context.database_code = database_error.code().map(|value| value.into_owned());
            context.database_message = Some(database_error.message().to_string());
            context.database_constraint = database_error.constraint().map(str::to_string);
            context.database_table = database_error.table().map(str::to_string);
        }

        context
    }

    pub(crate) fn database_code(&self) -> &str {
        self.database_code.as_deref().unwrap_or("<none>")
    }

    pub(crate) fn database_message(&self) -> &str {
        self.database_message.as_deref().unwrap_or("<none>")
    }

    pub(crate) fn database_constraint(&self) -> &str {
        self.database_constraint.as_deref().unwrap_or("<none>")
    }

    pub(crate) fn database_table(&self) -> &str {
        self.database_table.as_deref().unwrap_or("<none>")
    }
}

pub(crate) fn is_row_not_found(error: &SqlxError) -> bool {
    matches!(error, SqlxError::RowNotFound)
}

pub(crate) fn is_unique_violation(error: &SqlxError) -> bool {
    match error {
        SqlxError::Database(database_error) => database_error.code().as_deref() == Some("23505"),
        _ => false,
    }
}

pub(crate) fn log_sqlx_error(operation: &'static str, error: &SqlxError, message: &'static str) {
    let context = SqlxErrorContext::from_error(error);
    tracing::error!(
        operation,
        error = %error,
        database_error_kind = context.kind,
        database_error_code = context.database_code(),
        database_error_message = context.database_message(),
        database_error_constraint = context.database_constraint(),
        database_error_table = context.database_table(),
        "{}",
        message
    );
}

pub(crate) fn warn_sqlx_error(operation: &'static str, error: &SqlxError, message: &'static str) {
    let context = SqlxErrorContext::from_error(error);
    tracing::warn!(
        operation,
        error = %error,
        database_error_kind = context.kind,
        database_error_code = context.database_code(),
        database_error_message = context.database_message(),
        database_error_constraint = context.database_constraint(),
        database_error_table = context.database_table(),
        "{}",
        message
    );
}

fn sqlx_error_kind(error: &SqlxError) -> &'static str {
    match error {
        SqlxError::Configuration(_) => "configuration",
        SqlxError::Database(_) => "database",
        SqlxError::Io(_) => "io",
        SqlxError::Tls(_) => "tls",
        SqlxError::Protocol(_) => "protocol",
        SqlxError::RowNotFound => "row_not_found",
        SqlxError::TypeNotFound { .. } => "type_not_found",
        SqlxError::ColumnIndexOutOfBounds { .. } => "column_index_out_of_bounds",
        SqlxError::ColumnNotFound(_) => "column_not_found",
        SqlxError::ColumnDecode { .. } => "column_decode",
        SqlxError::Decode(_) => "decode",
        SqlxError::PoolTimedOut => "pool_timed_out",
        SqlxError::PoolClosed => "pool_closed",
        SqlxError::WorkerCrashed => "worker_crashed",
        SqlxError::Migrate(_) => "migrate",
        _ => "unknown",
    }
}
