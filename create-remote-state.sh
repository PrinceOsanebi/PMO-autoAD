#!/bin/bash
set -e  # Exit script if any command fails

# Variables
BUCKET_NAME="pmo-remote-state"
AWS_REGION="eu-west-1"
AWS_PROFILE="pmo-admin"

echo "Checking if bucket $BUCKET_NAME exists in $AWS_REGION with profile $AWS_PROFILE"

if aws s3api head-bucket --bucket "$BUCKET_NAME" --profile "$AWS_PROFILE" 2>/dev/null; then
  echo "Bucket $BUCKET_NAME already exists, skipping creation."
else
  echo "Creating S3 bucket: $BUCKET_NAME in $AWS_REGION"
  aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION" --profile "$AWS_PROFILE" \
    --create-bucket-configuration LocationConstraint="$AWS_REGION"
  echo "Bucket created."
fi

echo "Enabling versioning on bucket: $BUCKET_NAME"
aws s3api put-bucket-versioning --bucket "$BUCKET_NAME" --region "$AWS_REGION" --profile "$AWS_PROFILE" \
  --versioning-configuration Status=Enabled

echo "Creating Vault and Jenkins Server with Terraform"
cd vault-jenkins

# Export env vars for Terraform
export AWS_PROFILE=$AWS_PROFILE
export AWS_REGION=$AWS_REGION

terraform init
terraform fmt --recursive
terraform validate
terraform apply -auto-approve
