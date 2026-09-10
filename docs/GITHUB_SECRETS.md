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

## Workflowt

| Workflow | Trigger |
|----------|---------|
| **CI** | push / PR |
| **Setup tenant GCP** | `workflow_dispatch` → tenant id |

Host VM (Caddy, systemd) asennetaan palvelimella — ei Actionsista.
