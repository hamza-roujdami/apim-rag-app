#!/usr/bin/env bash
# Build the Ollama+models image and push it to the ACR provisioned by ../00-infra.
# Run this AFTER `terraform apply` in ../00-infra (the ACR must exist) and BEFORE
# `terraform apply` here (the Container App pulls this image).
#
# Usage:  ./build.sh [image:tag]        (default: ollama-models:latest)
set -euo pipefail

IMAGE="${1:-ollama-models:latest}"
ACR="$(terraform -chdir=../00-infra output -raw acr_name)"

echo "==> Building '${IMAGE}' in ACR '${ACR}' (ACR-side build, no local Docker needed)"
az acr build --registry "${ACR}" --image "${IMAGE}" .

echo "==> Done. Now run: terraform init && terraform apply -var=\"image=${IMAGE}\""
