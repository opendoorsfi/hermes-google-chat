# AGENTS.md — hermes-google-chat

**Standalone repo:** `opendoorsfi/hermes-google-chat`. **Ei** moderate-monorepo / kommenttimoderointi.

## Vastuunjako

```
Google Chat → Funnel/Caddy → hermes gateway (host VM) → HERMES_HOME (LLM, profiilit)
GCP Console  → Chat app + SA per tenant (HTTP endpoint URL)
GitHub Actions → tenant GCP setup (WIF), ei host-systemd
```

- **Älä** duplikoi LLM-avaimia GCP Secret Manageriin.
- **Älä** sekoita `chat-moderation` / Zapier / Sheet -järjestelmään.
- **Yksi** `hermes gateway` prosessi per Chat-app (tenant).

## Tiedostot

| Asia | Paikka |
|------|--------|
| Tenant manifest | `config/tenants/<id>.env` |
| GCP tenant setup | `infra/setup_tenant_gcp.sh` |
| Host install | `scripts/install_hermes_host.sh` |
| .env generointi | `scripts/print_tenant_env.sh` |

## Ennen muutosta

```bash
make validate
```

Generoidut / paikalliset: `out/`, `config/tenants/*.env` (gitignore).
