#!/bin/bash
echo "Initializing LocalStack secrets..."
awslocal secretsmanager create-secret --name db-user --secret-string 'your_local_db_user' --region eu-west-1 2>/dev/null || true
awslocal secretsmanager create-secret --name db-password --secret-string 'your_local_db_password' --region eu-west-1 2>/dev/null || true
echo "LocalStack secrets initialized"