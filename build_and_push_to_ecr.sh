##!/bin/bash
set -e

AWS_REGION="eu-west-1"
IMAGE_TAG="v1.0"
AWS_PROFILE="aptsapienza"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── 1. Get the ECR Repository name from Terraform output ─────────────────
echo "==> Retrieving ECR Repository name from Terraform output..."
ECR_REPOSITORY_URL=$(tflocal -chdir="${SCRIPT_DIR}" output -raw ecr_repository_url)
if [[ -z "${ECR_REPOSITORY_URL}" ]]; then
    echo "ERROR: Could not retrieve ecr_repository_url from Terraform output." >&2
    echo "       Make sure you have run 'terraform apply' first." >&2
    exit 1
fi
ECR_URL_NO_REPO=${ECR_REPOSITORY_URL%/*} # Remove the repository name from the URL
echo "    ECR Repository URL: ${ECR_REPOSITORY_URL}"
echo "    ECR URL without repository name: ${ECR_URL_NO_REPO}"

# ── 2. Log in to AWS ECR ───────────────────────────────────────────────
echo "1. Logging in to AWS ECR..."
awslocal ecr get-login-password --region $AWS_REGION --profile $AWS_PROFILE | \
    docker login --username AWS --password-stdin $ECR_URL_NO_REPO

# ── 3. Build Docker Image ───────────────────────────────────────────────
echo "2. Building Docker Image (if not already built)..."
docker build -t $ECR_REPOSITORY_URL .

# ── 4. Tag Docker Image ───────────────────────────────────────────────
echo "3. Tagging Image..."
docker tag $ECR_REPOSITORY_URL:latest $ECR_REPOSITORY_URL:$IMAGE_TAG

# ── 5. Push Docker Image ───────────────────────────────────────────────
echo "4. Pushing to ECR..."
docker push $ECR_REPOSITORY_URL:$IMAGE_TAG

echo "✅ Image pushed successfully."
