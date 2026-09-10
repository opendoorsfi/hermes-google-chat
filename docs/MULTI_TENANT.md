# Multi-tenant Hermes Google Chat

**Oma repo:** [`opendoorsfi/hermes-google-chat`](https://github.com/opendoorsfi/hermes-google-chat) — erillään
[`opendoorsfi/moderate`](https://github.com/opendoorsfi/moderate) kommenttimoderoinnista.

## Malli

| Tyyppi | Käyttö | GCP-projekti | Linux-käyttäjä |
|--------|--------|--------------|----------------|
| **personal** | DM, oma assistentti | `hermes-alice` | `hermes-alice` |
| **team** | Jaettu Chat-space | `hermes-team` | `hermes-team` |

Inbound: **HTTP** → Tailscale Funnel → Caddy (path per tenant) → `hermes gateway` (localhost).

LLM-avaimet: **vain** `/home/<user>/.hermes/.env` — ei GCP:ssä.

## Pikakäynti

```bash
# 1. Kopioi tenant manifest
cp config/tenants/alice.env.example config/tenants/alice.env
# Muokkaa FUNNEL_BASE_URL, GOOGLE_CHAT_ALLOWED_USERS

# 2. GCP (GitHub Actions tai paikallinen gcloud)
TENANT=alice bash infra/setup_tenant_gcp.sh

# 3. Chat API Console — ks. out/tenants/alice/CHAT_CONSOLE_CHECKLIST.md

# 4. Host VM
sudo bash scripts/install_hermes_host.sh --tenant alice
sudo bash scripts/print_tenant_env.sh alice >> /home/hermes-alice/.hermes/.env
# SA JSON → /home/hermes-alice/.hermes/secrets/google-chat-sa.json
sudo systemctl start hermes-gateway@hermes-alice
sudo bash deploy/host/tailscale-funnel.sh

# 5. Verify
bash scripts/verify_tenant.sh alice
```

## Uusi tenant

```bash
cp config/tenants/alice.env.example config/tenants/carol.env
# edit → TENANT=provision_tenant.sh carol
TENANT=carol bash scripts/provision_tenant.sh
```

## Team-space

1. Provision `team` tenant
2. Google Chat → Create space → Manage apps → **Hermes (Team)**
3. Henkilökohtaiset botit vain DM:ään

## GitHub Actions

| Workflow | Tarkoitus |
|----------|-----------|
| **CI** | pytest + shellcheck |
| **Setup tenant GCP** | `workflow_dispatch` → TENANT → `setup_tenant_gcp.sh` |

Host-VM systemd ei ajeta Actionsista — se on palvelimen vastuulla.

## Turvallisuus

- `GOOGLE_CHAT_ALLOWED_USERS` pakollinen (Funnel on julkinen)
- Oma GCP-projekti per botti
- systemd `User=`, `ProtectSystem=strict`
- SA JSON `chmod 600` — ei repoon

Katso myös [TAILSCALE.md](TAILSCALE.md), [EXISTING_HERMES.md](EXISTING_HERMES.md).
