# hermes-google-chat

**Multi-tenant Google Chat -yhteys olemassa oleviin Hermes-asennuksiin.**

Erillinen työkalu — **ei** liity [`opendoorsfi/moderate`](https://github.com/opendoorsfi/moderate) -kommenttimoderointiin.

## Arkkitehtuuri

```
Google Chat → Tailscale Funnel (HTTPS)
           → Caddy (/alice, /bob, /team)
           → hermes gateway (per Linux-käyttäjä, localhost)
           → olemassa oleva HERMES_HOME (LLM-avaimet, profiilit)
```

- **Henkilöbotti:** oma GCP-projekti + DM
- **Team-botti:** jaettu Chat-space
- **Ei** Cloud Run -embedded agenttia tuotannossa

## Aloitus

1. **[docs/GOOGLE_CHAT_INSTALL.md](docs/GOOGLE_CHAT_INSTALL.md)** — asenna Google Chat (secrets → GCP → host → Chat Console)
2. [docs/MULTI_TENANT.md](docs/MULTI_TENANT.md) — multi-tenant arkkitehtuuri
3. GitHub secrets (kerran, admin): `bash scripts/bootstrap_github_secrets.sh`
4. Kopioi `config/tenants/alice.env.example` → `alice.env` → `TENANT=alice bash scripts/provision_tenant.sh`

## GitHub Actions

| Workflow | Tiedosto | Kuvaus |
|----------|----------|--------|
| **CI** | `.github/workflows/ci.yml` | push/PR → `make validate` + standalone-check |
| **Setup tenant GCP** | `.github/workflows/tenant-gcp.yml` | manuaalinen (`tenant`, `funnel_base_url`) → `infra/setup_tenant_gcp.sh` + artefaktit |

Secrets: `GCP_WIF_PROVIDER`, `GCP_DEPLOY_SA_EMAIL` — ks. [docs/GITHUB_SECRETS.md](docs/GITHUB_SECRETS.md)

## Kehitys

```bash
pip install -r requirements-dev.txt   # pytest; shellcheck: apt-get install shellcheck
make validate                         # pytest + shellcheck (fallback bash -n)
make standalone-check                 # validate + workflowt + docs
bash scripts/verify_tenant.sh alice
```

## Dokumentaatio

- [MULTI_TENANT.md](docs/MULTI_TENANT.md)
- [TAILSCALE.md](docs/TAILSCALE.md)
- [EXISTING_HERMES.md](docs/EXISTING_HERMES.md)
- [DECOMMISSION_CLOUD_RUN.md](docs/DECOMMISSION_CLOUD_RUN.md)
