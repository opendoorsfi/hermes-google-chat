# GitHub Actions — secrets ja WIF

Repo: **`opendoorsfi/hermes-google-chat`** (ei moderate).

## Secrets

| Secret | Kuvaus |
|--------|--------|
| `GCP_WIF_PROVIDER` | WIF provider resource name |
| `GCP_DEPLOY_SA_EMAIL` | Deploy service account |

## WIF (kertaluontoinen)

```bash
export GCP_PROJECT=od-azuracast-sync
export HERMES_GITHUB_REPO=opendoorsfi/hermes-google-chat
bash scripts/setup_github_wif.sh
```

```bash
gh secret set GCP_WIF_PROVIDER --repo opendoorsfi/hermes-google-chat --body 'projects/.../providers/github-provider'
gh secret set GCP_DEPLOY_SA_EMAIL --repo opendoorsfi/hermes-google-chat --body 'github-azuracast-deploy@od-azuracast-sync.iam.gserviceaccount.com'
```

## Deploy SA:n oikeudet tenant-projekteissa

WIF antaa Actionsille deploy-SA:n identiteetin, mutta `setup_tenant_gcp.sh` toimii **tenantin
omassa projektissa** (`hermes-alice`, `hermes-team`, …). Anna deploy-SA:lle siellä:

```bash
TENANT_PROJECT=hermes-alice
DEPLOY_SA=github-azuracast-deploy@od-azuracast-sync.iam.gserviceaccount.com
for role in roles/serviceusage.serviceUsageAdmin roles/iam.serviceAccountAdmin; do
  gcloud projects add-iam-policy-binding "${TENANT_PROJECT}" \
    --member="serviceAccount:${DEPLOY_SA}" --role="${role}"
done
```

## Workflowt

| Workflow | Tiedosto | Trigger |
|----------|----------|---------|
| **CI** | `.github/workflows/ci.yml` | push `main` / PR → `make validate` + `scripts/export_standalone_check.sh` |
| **Setup tenant GCP** | `.github/workflows/tenant-gcp.yml` | `workflow_dispatch` → `tenant` (+ `funnel_base_url`, `gcp_project`) |

**Setup tenant GCP** -inputit: manifestit `config/tenants/<id>.env` ovat gitignoressa, joten
repossa on vain `*.env.example` (placeholder-Funnel-URL). Anna oikea URL `funnel_base_url`-inputtina.
Workflow ajaa skriptin `SKIP_SA_KEY=1` — SA JSON -avain luodaan Consolesta suoraan hostille,
ei GitHub-artefakteihin. Artefaktina tulee `gcp.env` + `CHAT_CONSOLE_CHECKLIST.md`.

Host VM (Caddy, systemd) asennetaan palvelimella — ei Actionsista.
