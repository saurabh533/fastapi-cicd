#!/usr/bin/env bash
#
# One-time GCP infrastructure setup for the Cloud Build + Cloud Run pipeline.
# Run this once from your machine after `gcloud auth login`.
#
# Usage:
#   PROJECT_ID=my-project bash gcp/setup.sh
#
set -euo pipefail

# ---- Config (override with env vars) ----
PROJECT_ID="${PROJECT_ID:?set PROJECT_ID, e.g. PROJECT_ID=my-proj bash gcp/setup.sh}"
REGION="${REGION:-us-central1}"
REPO="${REPO:-demo}"
SERVICE="${SERVICE:-demo-api}"
# ------------------------------------------

echo "==> Using project: $PROJECT_ID  region: $REGION"
gcloud config set project "$PROJECT_ID" >/dev/null

echo "==> Enabling required APIs"
gcloud services enable \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com

echo "==> Creating Artifact Registry repo '$REPO' (idempotent)"
gcloud artifacts repositories create "$REPO" \
  --repository-format=docker \
  --location="$REGION" \
  --description="Docker images for $SERVICE" \
  || echo "    repo already exists, continuing"

echo "==> Granting the build service account(s) permission to deploy"
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"
# Depending on project age, builds run as one of these. Granting both is safe.
CB_SA="${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com"
COMPUTE_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

for SA in "$CB_SA" "$COMPUTE_SA"; do
  for ROLE in roles/run.admin roles/iam.serviceAccountUser roles/artifactregistry.writer; do
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
      --member="serviceAccount:${SA}" \
      --role="$ROLE" \
      --condition=None >/dev/null 2>&1 || true
  done
done

echo ""
echo "==> Infra ready."
echo "    Next steps (see ../README.md 'Way 2' for details):"
echo "    1. Connect this GitHub repo in the console:"
echo "         Cloud Build -> Repositories -> Connect repository"
echo "    2. Create the two triggers (edit owner/name first):"
echo "         gcloud builds triggers create github \\"
echo "           --name=ci-pr \\"
echo "           --repo-owner=YOUR_GH_USER --repo-name=fastapi-cicd \\"
echo "           --pull-request-pattern='^main\$' \\"
echo "           --build-config=cloudbuild.ci.yaml"
echo ""
echo "         gcloud builds triggers create github \\"
echo "           --name=cd-main \\"
echo "           --repo-owner=YOUR_GH_USER --repo-name=fastapi-cicd \\"
echo "           --branch-pattern='^main\$' \\"
echo "           --build-config=cloudbuild.yaml \\"
echo "           --substitutions='_TAG=\$SHORT_SHA'"
