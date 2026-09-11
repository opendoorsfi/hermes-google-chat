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
  roles/artifactregistry.writer \
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

PROJECT_NUMBER="$(gcloud projects describe "${PROJECT}" --format='value(projectNumber)')"
CB_SA="${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com"
echo "  + roles/iam.serviceAccountUser on ${CB_SA}"
gcloud iam service-accounts add-iam-policy-binding "${CB_SA}" \
  --project="${PROJECT}" \
  --member="serviceAccount:${DEPLOY_SA}" \
  --role="roles/iam.serviceAccountUser" \
  --quiet >/dev/null

BUCKET="gs://${PROJECT}_cloudbuild"
if gsutil ls -b "${BUCKET}" &>/dev/null; then
  echo "  + storage.admin on ${BUCKET}"
  gsutil iam ch "serviceAccount:${DEPLOY_SA}:roles/storage.admin" "${BUCKET}" || true
else
  echo "  (bucket ${BUCKET} ei vielä — Cloud Build luo sen ensimmäisellä buildilla)"
fi

echo "OK — push registry.json uudelleen → Sync Chat users luo SA + avaimen automaattisesti"
