# Käyttäjien lisääminen (tavoitetaso)

**Sinä:** annat workspace-sähköpostin (esim. `ipad@info.opendoors.fi`).

**Agentti / GitHub:** hoitaa loput — sinun ei tarvitse ajaa komentoja missään.

## Miten se toimii

1. Sähköposti lisätään tiedostoon `config/tenants/registry.json` (commit + push).
2. GitHub Actions **Sync Chat users** käynnistyy automaattisesti.
3. Workflow:
   - luo tenant-manifestin (`hermes-ipad`, portti, Chat-URL)
   - ajaa GCP-setupin (`setup_tenant_gcp.sh`)
   - yrittää host-synciä self-hosted runnerilla `hermes-host` (jos asennettu)
4. Valmis → Google Chatissa etsit **Hermes (Ipad)** → Message → `Hei`.

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
