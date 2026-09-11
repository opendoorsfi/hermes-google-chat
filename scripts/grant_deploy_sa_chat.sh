#!/usr/bin/env bash
# Kerran (GCP admin): anna GitHub deploy-SA:lle Chat-automaation oikeudet.
#   bash scripts/grant_deploy_sa_chat.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="${GCP_PROJECT:-$(python3 "${ROOT}/scripts/chat_registry.py" hub-json | python3 -c "import json,sys; print(json.load(sys.stdin)['gcp_project'])")}"
DEPLOY_SA="${GCP_DEPLOY_SA_EMAIL:-github-hermes-deploy@${PROJECT}.iam.gserviceaccount.com}"

echo "==> Grant deploy SA Chat + Cloud Run IAM on ${PROJECT}"
echo "    ${DEPLOY_SA}"

for role in \
  roles/serviceusage.serviceUsageAdmin \
  roles/iam.serviceAccountAdmin \
  roles/iam.serviceAccountKeyAdmin \
  roles/secretmanager.secretAccessor \
  roles/secretmanager.admin \
  roles/pubsub.admin \
  roles/chat.owner \
  roles/run.admin \
  roles/artifactregistry.admin \
  roles/cloudbuild.builds.editor \
  roles/storage.admin \
  roles/iam.serviceAccountUser \
  roles/viewer; do
  echo "  + ${role}"
  gcloud projects add-iam-policy-binding "${PROJECT}" \
    --member="serviceAccount:${DEPLOY_SA}" \
    --role="${role}" \
    --condition=None \
    --quiet >/dev/null
done

gcloud services enable cloudbuild.googleapis.com --project="${PROJECT}" --quiet 2>/dev/null || true
if gcloud beta services identity create --service=cloudbuild.googleapis.com --project="${PROJECT}" &>/dev/null; then
  echo "  OK: Cloud Build service identity"
fi

PROJECT_NUMBER="$(gcloud projects describe "${PROJECT}" --format='value(projectNumber)')"
CB_SA="${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com"
if gcloud iam service-accounts describe "${CB_SA}" --project="${PROJECT}" &>/dev/null; then
  echo "  + roles/iam.serviceAccountUser on ${CB_SA}"
  gcloud iam service-accounts add-iam-policy-binding "${CB_SA}" \
    --project="${PROJECT}" \
    --member="serviceAccount:${DEPLOY_SA}" \
    --role="roles/iam.serviceAccountUser" \
    --quiet >/dev/null
else
  echo "  (Cloud Build SA ei vielä — API aktivoidaan deploy-vaiheessa)"
fi

BUCKET="gs://${PROJECT}_cloudbuild"
if command -v gsutil >/dev/null && gsutil ls -b "${BUCKET}" &>/dev/null; then
  echo "  + storage.admin on ${BUCKET}"
  gsutil iam ch "serviceAccount:${DEPLOY_SA}:roles/storage.admin" "${BUCKET}" || true
else
  echo "  (bucket ${BUCKET} ei vielä — projektitason storage.admin riittää)"
fi

echo "OK — push registry.json uudelleen → Sync Chat users luo SA + avaimen automaattisesti"
