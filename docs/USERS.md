# Käyttäjien lisääminen (tavoitetaso)

**Sinä:** annat workspace-sähköpostin (esim. `ipad@info.opendoors.fi`).

**Agentti / GitHub:** hoitaa loput — sinun ei tarvitse ajaa komentoja missään.

## Eri botit — älä sekoita moderointiin

| Chat-app | GCP-projekti | Repo |
|----------|--------------|------|
| **Moderointi** (kommentit, Sheet) | moderate-projekti | `opendoorsfi/moderate` |
| **Hermes (Ipad)** (LLM-avustaja) | `od-azuracast-sync` | `opendoorsfi/hermes-google-chat` |

Jos Chatissa näkyy vain moderointi-botti, etsit väärää appia. Hermes-botti luodaan projektiin **`od-azuracast-sync`** nimellä **Hermes (Ipad)**.

## Lisää botti GitHub Hubista (automaattinen)

1. Avaa **Actions** → **Sync Chat users** → **Run workflow**
2. Syötä sähköposti: `ipad@info.opendoors.fi` → **Run workflow**
3. Hub tekee automaattisesti:
   - registry + manifestit
   - Pub/Sub topic/sub + IAM
   - service account + Secret Manager
   - artefaktin `CHAT_APP_SETUP.md` (tarkat Console-arvot)

**Yksi Console-Save** on pakollinen (Google ei tarjoa API:ta appin rekisteröintiin Chatissa):

https://console.cloud.google.com/apis/api/chat.googleapis.com/hangouts-chat?project=od-azuracast-sync

Kopioi arvot workflow-summarystä tai artefaktista → **Save** → Chatissa **Find apps** → **Hermes (Ipad)**.

## Miten se toimii

1. Sähköposti lisätään tiedostoon `config/tenants/registry.json` (commit + push).
2. GitHub Actions **Sync Chat users** käynnistyy automaattisesti.
3. Workflow:
   - luo tenant-manifestin (`hermes-ipad`, portti, Chat-URL)
   - ajaa GCP-setupin (`setup_tenant_gcp.sh`)
   - yrittää host-synciä self-hosted runnerilla `hermes-host` (jos asennettu)
4. **Create Hermes Chat app** -workflow luo Pub/Sub-resurssit + Console-ohjeen.
5. Console-Save (kerran) → Google Chatissa etsit **Hermes (Ipad)** → Message → `Hei`.

## macOS-host (Natalia)

Käyttäjä voi olla omalla Macilla (`hosts.natalia-mac` registryssä). Ei sudo/Caddy — suora Hermes-gateway + Tailscale Funnel.

**Kerran Macilla** (tai self-hosted runner `hermes-host` tekee automaattisesti):

```bash
git clone git@github.com:opendoorsfi/hermes-google-chat.git ~/hermes-google-chat
cd ~/hermes-google-chat
bash scripts/bootstrap_hermes_mac.sh natalia@info.opendoors.fi
```

Chat HTTP URL (root, ei `/natalia/`-prefixiä):  
`https://natalia.tail28712d.ts.net/api/platforms/google_chat/events`

Runner Macilla: aseta label `hermes-host` + `self-hosted`, env `HERMES_REGISTRY_HOST=natalia-mac`.

**SA JSON:** ei manuaalista latausta — GitHub Actions luo avaimen, tallentaa Secret Manageriin + artefaktiin; bootstrap/`ensure_tenant_sa.sh` hakee sen (`gh`, `gcloud`, tai host-runner).

## Infra (kerran, ei käyttäjäkohtaista)

| Asia | Kuka | Missä |
|------|------|--------|
| `gcp_project` + `funnel_base_url` registryssä | Infra / agentti (kerran) | `config/tenants/registry.json` |
| Self-hosted runner `hermes-host` | Infra (kerran) | Hermes-isäntäpalvelin |
| WIF | Repossa workflow-env (tai GitHub secrets) | `.github/workflows/sync-chat-users.yml` |

Käyttäjä ei koske GitHubiin, GCP:hen eikä palvelimeen.

## Uusi käyttäjä — agentille

```
Lisää Google Chat -käyttäjä: someone@info.opendoors.fi
```

Agentti commitoi registryyn → push → workflow.

## Poista käyttäjä

Poista email `registry.json` → `users`-listasta, commit, push. (GCP-projekti jää — poisto erikseen tarvittaessa.)
