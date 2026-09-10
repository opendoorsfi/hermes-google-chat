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

1. [docs/MULTI_TENANT.md](docs/MULTI_TENANT.md) — pääohje
2. [docs/STANDALONE_REPO.md](docs/STANDALONE_REPO.md) — oma repo vs moderate
3. Kopioi `config/tenants/alice.env.example` → `alice.env`
4. `TENANT=alice bash scripts/provision_tenant.sh`

## GitHub Actions

| Workflow | Kuvaus |
|----------|--------|
| **CI** | push/PR → pytest + lint |
| **Setup tenant GCP** | manuaalinen → `infra/setup_tenant_gcp.sh` + artefaktit |

Secrets: `GCP_WIF_PROVIDER`, `GCP_DEPLOY_SA_EMAIL` — ks. [docs/GITHUB_SECRETS.md](docs/GITHUB_SECRETS.md)

## Kehitys

```bash
make validate          # pytest + shellcheck
bash scripts/verify_tenant.sh alice
```

## Dokumentaatio

- [MULTI_TENANT.md](docs/MULTI_TENANT.md)
- [TAILSCALE.md](docs/TAILSCALE.md)
- [EXISTING_HERMES.md](docs/EXISTING_HERMES.md)
- [DECOMMISSION_CLOUD_RUN.md](docs/DECOMMISSION_CLOUD_RUN.md)
