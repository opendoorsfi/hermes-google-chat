# GitHub Actions — secrets ja WIF

Repo: **`opendoorsfi/hermes-google-chat`**. GCP-projekti: **`od-kansiot`**.

## Kerran (GCP admin)

```bash
export GCP_PROJECT=od-kansiot
bash scripts/bootstrap_od_kansiot_project.sh
```

Tämä luo Pub/Sub + SA + deploy-SA IAM + WIF poolin.

## GitHub secrets

```bash
export GCP_PROJECT=od-kansiot
export HERMES_GITHUB_REPO=opendoorsfi/hermes-google-chat
bash scripts/setup_github_wif.sh   # tulostaa arvot
bash scripts/bootstrap_github_secrets.sh --wif
```

| Secret | Esimerkki |
|--------|-----------|
| `GCP_WIF_PROVIDER` | `projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-pool/providers/github-provider` |
| `GCP_DEPLOY_SA_EMAIL` | `github-hermes-deploy@od-kansiot.iam.gserviceaccount.com` |

Päivitä myös `config/tenants/registry.json` → `"wif_provider": "..."`.

## Workflowt

| Workflow | Tarkoitus |
|----------|-----------|
| **Sync Chat users** | registry → GCP + Chat app infra + host-sync |
| **Create Hermes Chat app** | Pub/Sub + Console-ohje |
| **Inspect Chat GCP** | Diagnostiikka |
| **Send Chat test** | Pub/Sub testiviesti |

GCP-projekti luetaan registrystä (`scripts/github_actions_load_gcp_env.sh`).
