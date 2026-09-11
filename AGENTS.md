# AGENTS.md — hermes-google-chat

**Standalone repo:** `opendoorsfi/hermes-google-chat`. **Ei** moderate-monorepo / kommenttimoderointi.

## GCP-projekti

| Projekti | Käyttö |
|----------|--------|
| **`opendoors-hermes-chat`** | Hermes Google Chat (yksi app `opendoors-hermes-chat`, monta käyttäjää) |
| `od-azuracast-sync` | AzuraCast + moderointi — **älä käytä Hermesille** |

Lähde: `config/tenants/registry.json` → `gcp_project`, `chat_app_display_name`, `github_deploy_sa`.

**Älä** luota env-muuttujaan `GCP_PROJECT=od-kansiot` (vanha org/secret). Skriptit ja Actions lukevat projektin registrystä.

## Vastuunjako

```
Google Chat → Pub/Sub (opendoors-hermes-chat) → hermes gateway (Cloud Run tai host) → HERMES_HOME
GitHub Actions → registry.json → Sync Chat users → GCP + Cloud Run deploy
GCP Console → Chat app Configuration (kerran, app: opendoors-hermes-chat)
```

- **Älä** duplikoi LLM-avaimia GCP Secret Manageriin jos gateway on hostilla (`~/.hermes`).
- Cloud Run -embedded gateway tarvitsee `hermes-llm-api-key` (GitHub secret `OPENROUTER_API_KEY`).
- **Älä** sekoita `chat-moderation` / Zapier / Sheet -järjestelmään.
- **Yksi** Chat-app projektissa, **monta** käyttäjää registryssä.

## Tiedostot

| Asia | Paikka |
|------|--------|
| Käyttäjät + GCP-projekti | `config/tenants/registry.json` |
| Tenant manifest | `config/tenants/<id>.env` (generoitu) |
| GCP bootstrap (kerran) | `scripts/bootstrap_gcp_project.sh` |
| WIF | `scripts/setup_github_wif.sh` |
| Hub workflow | `.github/workflows/sync-chat-users.yml` |
| Cloud Run gateway | `.github/workflows/deploy-cloudrun-gateway.yml` |

## Ennen muutosta

```bash
make validate
```

Generoidut / paikalliset: `out/`, `config/tenants/*.env` (gitignore).
