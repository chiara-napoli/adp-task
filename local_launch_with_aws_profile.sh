#!/usr/bin/env bash
#
# local_launch_with_aws_profile.sh
#
# Launches main.py locally using a given AWS profile, with all the
# environment variables and dependencies set up automatically.
#
# Usage:
#   ./local_launch_with_aws_profile.sh <aws-profile-name>
#

set -euo pipefail

# ── Validate arguments ───────────────────────────────────────────────
if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <aws-profile-name>"
    exit 1
fi

AWS_PROFILE_NAME="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${SCRIPT_DIR}/.venv"

# ── 1. Get the S3 bucket name from Terraform output ─────────────────
echo "==> Retrieving S3 bucket name from Terraform output..."
BUCKET_NAME=$(terraform -chdir="${SCRIPT_DIR}" output -raw s3_bucket_name)
if [[ -z "${BUCKET_NAME}" ]]; then
    echo "ERROR: Could not retrieve s3_bucket_name from Terraform output." >&2
    echo "       Make sure you have run 'terraform apply' first." >&2
    exit 1
fi
echo "    Bucket: ${BUCKET_NAME}"

# ── 2. Create virtual environment and install dependencies ───────────
if [[ ! -d "${VENV_DIR}" ]]; then
    echo "==> Creating Python virtual environment in ${VENV_DIR}..."
    python3 -m venv "${VENV_DIR}"
fi

echo "==> Installing dependencies from requirements.txt..."
"${VENV_DIR}/bin/pip" install --quiet -r "${SCRIPT_DIR}/requirements.txt"

# ── 3. Set environment variables ─────────────────────────────────────
export AWS_PROFILE="${AWS_PROFILE_NAME}"
export BUCKET_NAME
export INPUT_PREFIX="input/"
export OUTPUT_PREFIX="output/"

echo "==> Environment variables set:"
echo "    AWS_PROFILE   = ${AWS_PROFILE}"
echo "    BUCKET_NAME   = ${BUCKET_NAME}"
echo "    INPUT_PREFIX   = ${INPUT_PREFIX}"
echo "    OUTPUT_PREFIX  = ${OUTPUT_PREFIX}"

# ── 4. Launch main.py ────────────────────────────────────────────────
echo "==> Launching main.py..."
"${VENV_DIR}/bin/python" "${SCRIPT_DIR}/main.py"
