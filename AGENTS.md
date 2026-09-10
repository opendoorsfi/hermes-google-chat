# AGENTS.md — hermes-google-chat

**Standalone repo:** `opendoorsfi/hermes-google-chat`. **Ei** moderate-monorepo / kommenttimoderointi.

## GCP-projekti

| Projekti | Käyttö |
|----------|--------|
| **`od-kansiot`** | Hermes Google Chat (yksi app `hermes-chat`, monta käyttäjää) |
| `od-azuracast-sync` | AzuraCast + moderointi — **älä käytä Hermesille** |

Lähde: `config/tenants/registry.json` → `gcp_project`, `chat_app_display_name`, `github_deploy_sa`.

## Vastuunjako

```
Google Chat → Pub/Sub (od-kansiot) → hermes gateway (host) → HERMES_HOME
GitHub Actions → registry.json → Sync Chat users → GCP + host-sync
GCP Console → Chat app Configuration (kerran, app: hermes-chat)
```

- **Älä** duplikoi LLM-avaimia GCP Secret Manageriin.
- **Älä** sekoita `chat-moderation` / Zapier / Sheet -järjestelmään.
- **Yksi** Chat-app projektissa, **monta** käyttäjää registryssä.

## Tiedostot

| Asia | Paikka |
|------|--------|
| Käyttäjät + GCP-projekti | `config/tenants/registry.json` |
| Tenant manifest | `config/tenants/<id>.env` (generoitu) |
| GCP bootstrap (kerran) | `scripts/bootstrap_od_kansiot_project.sh` |
| WIF | `scripts/setup_github_wif.sh` |
| Hub workflow | `.github/workflows/sync-chat-users.yml` |

## Ennen muutosta

```bash
make validate
```

Generoidut / paikalliset: `out/`, `config/tenants/*.env` (gitignore).
