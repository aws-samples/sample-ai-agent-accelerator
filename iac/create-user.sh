#!/bin/bash

# Script to create a Cognito user for the AI Agent application

set -e

# Get Cognito User Pool ID from Terraform output
USER_POOL_ID=$(terraform output -raw cognito_user_pool_id)

if [ -z "$USER_POOL_ID" ]; then
    echo "Error: Could not get Cognito User Pool ID from Terraform output"
    exit 1
fi

# Prompt for user email
read -p "Enter email address for the new user: " EMAIL

if [ -z "$EMAIL" ]; then
    echo "Error: Email address is required"
    exit 1
fi

# Prompt for temporary password
read -s -p "Enter temporary password (min 8 chars, must include uppercase, lowercase, number, symbol): " TEMP_PASSWORD
echo

if [ -z "$TEMP_PASSWORD" ]; then
    echo "Error: Password is required"
    exit 1
fi

echo "Creating user in Cognito User Pool: $USER_POOL_ID"

# Create the user
aws cognito-idp admin-create-user \
    --user-pool-id "$USER_POOL_ID" \
    --username "$EMAIL" \
    --user-attributes Name=email,Value="$EMAIL" Name=email_verified,Value=true \
    --temporary-password "$TEMP_PASSWORD" \
    --message-action SUPPRESS

echo "User created successfully!"
echo "Email: $EMAIL"
echo "Temporary password: $TEMP_PASSWORD"
echo ""
echo "The user will need to change their password on first login."
echo "Access the application at: $(terraform output -raw endpoint)"