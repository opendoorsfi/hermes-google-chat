# AGENTS.md — hermes-google-chat

**Standalone repo:** `opendoorsfi/hermes-google-chat`. **Ei** moderate-monorepo / kommenttimoderointi.

## GCP-projekti

| Projekti | Käyttö |
|----------|--------|
| **`opendoors-hermes-chat`** | Hermes Google Chat (Pub/Sub → Cloud Run gateway) |
| `od-kansiot` | Vanha — **älä käytä Hermesille** |
| `od-azuracast-sync` | AzuraCast Drive-sync — katso `azuracast-sync/` |

Lähde: `config/tenants/registry.json` → `gcp_project`, `chat_app_display_name`, `github_deploy_sa`.

## Vastuunjako

```
Google Chat → Pub/Sub → Cloud Run hermes-gateway (tai host VM)
GitHub Actions → registry.json → Sync Chat users → deploy + self-heal
GCP Console → Chat app Configuration (kerran)
```

- **Älä** duplikoi LLM-avaimia GCP Secret Manageriin (paitsi CI `OPENROUTER_API_KEY` → secret).
- **Älä** sekoita `chat-moderation` / Zapier / Sheet -järjestelmään.
- **Gateway:** `chat_gateway_host: cloudrun` (ei vaadi Mac-runneria).

## Itsekorjaus (agentit + CI)

Kun yhteys ei synny / botti ei vastaa:

1. **Älä ohjeista käyttäjää ajamaan komentoja** — aja itse CI:ssä tai korjaa repo.
2. Aja diagnoosi: `bash scripts/self_heal_gateway.sh`
3. Korjaus CI:ssä: workflow **Self-heal gateway** tai `bash scripts/self_heal_gateway.sh --apply`
4. Tyypilliset korjaukset (automaattiset):
   - GCP-projekti registrystä (`github_actions_load_gcp_env.sh`)
   - Pub/Sub IAM + Cloud Run redeploy
   - `OPENROUTER_API_KEY` GitHub secret → Secret Manager
5. Epäonnistuneen deploy/health-checkin jälkeen **Self-heal** käynnistyy automaattisesti (`workflow_run`).
6. Dokumentoi uusi toistuva virhe → päivitä `scripts/self_heal_gateway.sh` tai `docs/RUNBOOK.md`.

## Tiedostot

| Asia | Paikka |
|------|--------|
| Käyttäjät + GCP-projekti | `config/tenants/registry.json` |
| Tenant manifest | `config/tenants/<id>.env` (generoitu) |
| Cloud Run deploy | `.github/workflows/deploy-cloudrun-gateway.yml` |
| Itsekorjaus | `.github/workflows/self-heal-gateway.yml`, `scripts/self_heal_gateway.sh` |
| GCP bootstrap (kerran) | `scripts/bootstrap_gcp_project.sh` |

## Ennen muutosta

```bash
make validate
```

Generoidut / paikalliset: `out/`, `config/tenants/*.env` (gitignore).
