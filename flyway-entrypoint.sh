#!/bin/sh
set -e

echo "Starting Flyway migration process..."

# Check if running in AWS ECS/Fargate (has ECS metadata endpoint)
if [ -n "$ECS_CONTAINER_METADATA_URI_V4" ]; then
    echo "Detected ECS/Fargate environment"
    
    # Get the secret ARN for the RDS master credentials
    # AWS automatically creates a secret with the pattern: rds!db-<resource-id>
    # But we need to get the actual secret ARN
    echo "Retrieving database credentials from Secrets Manager..."
    
    # Get the secret containing the RDS credentials
    # The secret is auto-created by RDS when using manage_master_user_password
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
    SECRET_JSON=$(aws secretsmanager get-secret-value \
        --region eu-west-2 \
        --secret-id "$SECRET_ARN" \
        --query 'SecretString' \
        --output text)
    
    # Parse the JSON to get credentials
    DB_USERNAME=$(echo "$SECRET_JSON" | grep -o '"username":"[^"]*' | cut -d'"' -f4)
    DB_PASSWORD=$(echo "$SECRET_JSON" | grep -o '"password":"[^"]*' | cut -d'"' -f4)
    DB_HOST=$(echo "$SECRET_JSON" | grep -o '"host":"[^"]*' | cut -d'"' -f4)
    DB_PORT=$(echo "$SECRET_JSON" | grep -o '"port":[^,}]*' | cut -d':' -f2)
    DB_NAME=$(echo "$SECRET_JSON" | grep -o '"dbname":"[^"]*' | cut -d'"' -f4)
    
    echo "Database host: $DB_HOST"
    echo "Database port: $DB_PORT"
    echo "Database name: $DB_NAME"
    echo "Database user: $DB_USERNAME"
    
    # Build the JDBC URL
    JDBC_URL="jdbc:postgresql://${DB_HOST}:${DB_PORT}/${DB_NAME}"
    
    # Run Flyway with the credentials
    echo "Running Flyway migrations..."
    exec flyway \
        -url="$JDBC_URL" \
        -user="$DB_USERNAME" \
        -password="$DB_PASSWORD" \
        -locations="filesystem:/sql" \
        -connectRetries=60 \
        -schemas=public \
        -validateMigrationNaming=true \
        -baselineOnMigrate=true \
        migrate
else
    echo "Not running in ECS/Fargate - using environment variables"
    
    # Local or non-ECS environment - use environment variables
    if [ -z "$FLYWAY_URL" ]; then
        echo "Error: FLYWAY_URL environment variable is required"
        exit 1
    fi
    
    if [ -z "$FLYWAY_USER" ]; then
        echo "Error: FLYWAY_USER environment variable is required"
        exit 1
    fi
    
    if [ -z "$FLYWAY_PASSWORD" ]; then
        echo "Error: FLYWAY_PASSWORD environment variable is required"
        exit 1
    fi
    
    echo "Running Flyway migrations with provided environment variables..."
    exec flyway migrate
fi
