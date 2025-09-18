#!/bin/bash
echo "Initializing LocalStack secrets..."

awslocal secretsmanager create-secret --name db-user --secret-string 'user' --region eu-west-1 2>/dev/null || true &
awslocal secretsmanager create-secret --name db-password --secret-string 'password' --region eu-west-1 2>/dev/null || true &
awslocal secretsmanager create-secret --name db-host --secret-string 'localhost' --region eu-west-1 2>/dev/null || true &
awslocal secretsmanager create-secret --name db-name --secret-string 'habit_market' --region eu-west-1 2>/dev/null || true &
awslocal secretsmanager create-secret --name eddsa-public-key --secret-string $'-----BEGIN PUBLIC KEY-----\nMCowBQYDK2VwAyEAgqOy39tZbw5kBo7F7+BIJfcemdiIbQhirZW4NV8lC2I=\n-----END PUBLIC KEY-----' --region eu-west-1 2>/dev/null || true &
awslocal secretsmanager create-secret --name eddsa-private-key --secret-string $'-----BEGIN PRIVATE KEY-----\nMC4CAQAwBQYDK2VwBCIEIL9ijTozRgbWNk4WlZosj9MibQ9s8gwcEOqk0KxQxxGd\n-----END PRIVATE KEY-----' --region eu-west-1 2>/dev/null || true &

awslocal secretsmanager create-secret --name test-db-user --secret-string 'user' --region eu-west-1 2>/dev/null || true &
awslocal secretsmanager create-secret --name test-db-password --secret-string 'password' --region eu-west-1 2>/dev/null || true &
awslocal secretsmanager create-secret --name test-db-host --secret-string 'localhost' --region eu-west-1 2>/dev/null || true &
awslocal secretsmanager create-secret --name test-db-name --secret-string 'test_habit_market' --region eu-west-1 2>/dev/null || true &
awslocal secretsmanager create-secret --name test-eddsa-public-key --secret-string $'-----BEGIN PUBLIC KEY-----\nMCowBQYDK2VwAyEAgqOy39tZbw5kBo7F7+BIJfcemdiIbQhirZW4NV8lC2I=\n-----END PUBLIC KEY-----' --region eu-west-1 2>/dev/null || true &
awslocal secretsmanager create-secret --name test-eddsa-private-key --secret-string $'-----BEGIN PRIVATE KEY-----\nMC4CAQAwBQYDK2VwBCIEIL9ijTozRgbWNk4WlZosj9MibQ9s8gwcEOqk0KxQxxGd\n-----END PRIVATE KEY-----' --region eu-west-1 2>/dev/null || true

wait

echo "LocalStack secrets initialized"
