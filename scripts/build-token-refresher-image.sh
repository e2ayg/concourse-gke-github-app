#!/usr/bin/env bash
#
# Build and push the token refresher image to Google Artifact Registry.
#
# Prerequisites:
#   - gcloud CLI authenticated (gcloud auth login)
#   - docker (or set BUILDER=podman)
#   - An Artifact Registry Docker repository (create with --create-repo)
#
# Docs:
#   - Artifact Registry auth: https://cloud.google.com/artifact-registry/docs/docker/authentication
#   - Push/pull images:       https://cloud.google.com/artifact-registry/docs/docker/pushing-and-pulling
#
# Usage:
#   PROJECT_ID=my-proj REGION=europe-west1 REPO=concourse TAG=1.0.0 \
#     scripts/build-token-refresher-image.sh
#
# Optional:
#   IMAGE_NAME (default: concourse-token-refresher)
#   BUILDER    (default: docker)
#   --create-repo   create the Artifact Registry repo if it does not exist

set -euo pipefail

PROJECT_ID="${PROJECT_ID:?Set PROJECT_ID}"
REGION="${REGION:?Set REGION (e.g. europe-west1)}"
REPO="${REPO:?Set REPO (Artifact Registry repository name)}"
TAG="${TAG:?Set TAG (image tag, e.g. 1.0.0)}"
IMAGE_NAME="${IMAGE_NAME:-concourse-token-refresher}"
BUILDER="${BUILDER:-docker}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTEXT_DIR="$(cd "${SCRIPT_DIR}/../token-refresher" && pwd)"

REGISTRY_HOST="${REGION}-docker.pkg.dev"
IMAGE_URI="${REGISTRY_HOST}/${PROJECT_ID}/${REPO}/${IMAGE_NAME}:${TAG}"

echo "==> Image URI: ${IMAGE_URI}"
echo "==> Build context: ${CONTEXT_DIR}"

if [[ "${1:-}" == "--create-repo" ]]; then
  echo "==> Ensuring Artifact Registry repo '${REPO}' exists in ${REGION}..."
  if ! gcloud artifacts repositories describe "${REPO}" \
    --project="${PROJECT_ID}" --location="${REGION}" >/dev/null 2>&1; then
    gcloud artifacts repositories create "${REPO}" \
      --project="${PROJECT_ID}" \
      --location="${REGION}" \
      --repository-format=docker \
      --description="Concourse token refresher images"
  else
    echo "    repo already exists."
  fi
fi

echo "==> Configuring Docker auth for ${REGISTRY_HOST}..."
gcloud auth configure-docker "${REGISTRY_HOST}" --quiet

echo "==> Building image..."
"${BUILDER}" build --platform linux/amd64 -t "${IMAGE_URI}" "${CONTEXT_DIR}"

echo "==> Pushing image..."
"${BUILDER}" push "${IMAGE_URI}"

echo ""
echo "Done. Set this in your terraform.tfvars:"
echo "  token_refresher_image = \"${IMAGE_URI}\""
