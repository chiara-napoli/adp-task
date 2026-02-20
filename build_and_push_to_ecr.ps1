## usare comandi localstack (cambiare nome, salta un passaggio)

# Imposta l'interruzione dello script in caso di errori (equivalente a set -e)
$ErrorActionPreference = "Stop"

$AWS_REGION = "eu-west-1"
$IMAGE_TAG = "v1.0"
$AWS_PROFILE = "aptsapienza"

# Ottiene la directory dello script corrente
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrEmpty($SCRIPT_DIR)) { $SCRIPT_DIR = Get-Location }

# ── 1. Recupera il nome del repository ECR dall'output di Terraform ──
Write-Host "==> Retrieving ECR Repository name from Terraform output..." -ForegroundColor Cyan

# Esegue terraform output
$ECR_REPOSITORY_URL = tflocal -chdir="$SCRIPT_DIR" output -raw ecr_repository_url

if ([string]::IsNullOrWhiteSpace($ECR_REPOSITORY_URL)) {
    Write-Error "ERROR: Could not retrieve ecr_repository_url from Terraform output."
    Write-Host "       Make sure you have run 'terraform apply' first." -ForegroundColor Red
    exit 1
}

# Rimuove il nome del repository dall'URL (equivalente a ${ECR_REPOSITORY_URL%/*})
$ECR_URL_NO_REPO = $ECR_REPOSITORY_URL.Substring(0, $ECR_REPOSITORY_URL.LastIndexOf('/'))

Write-Host "    ECR Repository URL: $ECR_REPOSITORY_URL"
Write-Host "    ECR URL without repository name: $ECR_URL_NO_REPO"

# ── 2. Login in AWS ECR ───────────────────────────────────────────────
Write-Host "1. Logging in to AWS ECR..." -ForegroundColor Cyan
$password = awslocal ecr get-login-password --region $AWS_REGION --profile $AWS_PROFILE
$password | docker login --username AWS --password-stdin $ECR_URL_NO_REPO

# ── 3. Build Docker Image ──────────────────────────────────────────────
Write-Host "2. Building Docker Image (if not already built)..." -ForegroundColor Cyan
docker build -t $ECR_REPOSITORY_URL "$SCRIPT_DIR/."

# ── 4. Tag Docker Image ───────────────────────────────────────────────
Write-Host "3. Tagging Image..." -ForegroundColor Cyan
docker tag "${ECR_REPOSITORY_URL}:latest" "${ECR_REPOSITORY_URL}:${IMAGE_TAG}"

# ── 5. Push Docker Image ──────────────────────────────────────────────
Write-Host "4. Pushing to ECR..." -ForegroundColor Cyan
docker push "${ECR_REPOSITORY_URL}:${IMAGE_TAG}"

Write-Host "✅ Image pushed successfully." -ForegroundColor Green