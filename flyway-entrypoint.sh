#!/bin/sh
set -e

echo "Starting Flyway migration process..."

: "${DB_HOST:?DB_HOST not set}"
: "${DB_NAME:?DB_NAME not set}"
: "${DB_PORT:?DB_PORT not set}"
: "${DB_USER:?DB_USER not set}"
: "${DB_PASSWORD:?DB_PASSWORD not set}"

echo "Database host: $DB_HOST"
echo "Database port: $DB_PORT"
echo "Database name: $DB_NAME"
echo "Database user: $DB_USER"

# Build the JDBC URL
JDBC_URL="jdbc:postgresql://${DB_HOST}:${DB_PORT}/${DB_NAME}"

# Run Flyway with the credentials
echo "Running Flyway migrations..."
flyway \
    -url="$JDBC_URL" \
    -user="$DB_USER" \
    -password="$DB_PASSWORD" \
    -locations="filesystem:/sql" \
    -connectRetries=0 \
    -schemas=public \
    -validateMigrationNaming=true \
    -baselineOnMigrate=true \
    migrate 2>&1

FLYWAY_EXIT_CODE=$?
if [ $FLYWAY_EXIT_CODE -ne 0 ]; then
    echo "Flyway migration failed with exit code: $FLYWAY_EXIT_CODE"
    exit $FLYWAY_EXIT_CODE
fi

echo "Flyway migrations completed successfully"
exit 0
