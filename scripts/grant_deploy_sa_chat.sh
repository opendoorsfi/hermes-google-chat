#!/usr/bin/env bash
# Kerran (GCP admin): anna GitHub deploy-SA:lle Chat-automaation oikeudet.
#   bash scripts/grant_deploy_sa_chat.sh
set -euo pipefail

PROJECT="${GCP_PROJECT:-od-azuracast-sync}"
DEPLOY_SA="${GCP_DEPLOY_SA_EMAIL:-github-azuracast-deploy@od-azuracast-sync.iam.gserviceaccount.com}"

echo "==> Grant deploy SA Chat automation IAM on ${PROJECT}"
echo "    ${DEPLOY_SA}"

for role in \
  roles/serviceusage.serviceUsageAdmin \
  roles/iam.serviceAccountAdmin \
  roles/iam.serviceAccountKeyAdmin \
  roles/secretmanager.secretAccessor \
  roles/secretmanager.admin; do
  echo "  + ${role}"
  gcloud projects add-iam-policy-binding "${PROJECT}" \
    --member="serviceAccount:${DEPLOY_SA}" \
    --role="${role}" \
    --condition=None \
    --quiet >/dev/null
done

echo "OK — push registry.json uudelleen → Sync Chat users luo SA + avaimen automaattisesti"
