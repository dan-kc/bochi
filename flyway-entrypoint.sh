#!/bin/sh
set -e

echo "Starting Flyway migration process..."

# Get the secret ARN for the RDS master credentials
# AWS automatically creates a secret with the pattern: rds!db-<resource-id>
# But we need to get the actual secret ARN
echo "Retrieving database credentials from Secrets Manager..."

# Get the secret containing the RDS credentials
SECRET_ARN=$(aws secretsmanager list-secrets \
    --region eu-west-2 \
    --query "SecretList[?contains(Name, 'rds')].ARN | [0]" \
    --output text)

if [ -z "$SECRET_ARN" ] || [ "$SECRET_ARN" = "None" ]; then
    echo "Error: Could not find secret for RDS instance"
    exit 1
fi

echo "Found secret: $SECRET_ARN"

# Retrieve the secret value
echo "Attempting to retrieve secret value..."
SECRET_JSON=$(aws secretsmanager get-secret-value \
    --region eu-west-2 \
    --secret-id "$SECRET_ARN" \
    --query 'SecretString' \
    --output text 2>&1)

if [ $? -ne 0 ]; then
    echo "Error retrieving secret: $SECRET_JSON"
    exit 1
fi

echo "Successfully retrieved secret value"

# Parse the JSON to get credentials
DB_USERNAME=$(echo "$SECRET_JSON" | grep -o '"username":"[^"]*' | cut -d'"' -f4)
DB_PASSWORD=$(echo "$SECRET_JSON" | grep -o '"password":"[^"]*' | cut -d'"' -f4)
DB_NAME=habit-market
DB_PORT=5432
echo "Attempting to get database host..."
DB_HOST=$(aws rds describe-db-instances \
    --region eu-west-2 \
    --db-instance-identifier habit-market \
    --query 'DBInstances[0].Endpoint.Address' \
    --output text 2>&1)

if [ $? -ne 0 ]; then
    echo "Error retrieving database host: $DB_HOST"
    exit 1
fi

echo "Successfully retrieved database host"

echo "Database host: $DB_HOST"
echo "Database port: $DB_PORT"
echo "Database name: $DB_NAME"
echo "Database user: $DB_USERNAME"

# Build the JDBC URL
JDBC_URL="jdbc:postgresql://${DB_HOST}:${DB_PORT}/${DB_NAME}"

# Run Flyway with the credentials
echo "Running Flyway migrations..."
flyway \
    -url="$JDBC_URL" \
    -user="$DB_USERNAME" \
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
