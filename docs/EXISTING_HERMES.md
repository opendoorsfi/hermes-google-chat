# Google Chat → olemassa oleva Hermes

**Tavoite:** Chat käyttää jo pyörivää Hermes-asennusta (profiilit, LLM-avaimet, agentit).
Ei erillistä “toista Hermes-aivoa” Cloud Runissa.

## Kolme tapaa (valitse yksi)

| Tapa | Missä agentti ajaa | LLM-avaimet | Inbound Chat |
|------|-------------------|-------------|--------------|
| **A. Pub/Sub suoraan** | Olemassa oleva `hermes gateway` | `~/.hermes/.env` (kuten nyt) | Pub/Sub pull — ei julkista URL:ia |
| **B. HTTP suoraan** | Olemassa oleva gateway + julkinen HTTPS | `~/.hermes/.env` | Chat → suoraan Hermeksen URL:iin |
| **C. Proxy-relay (Cloud Run)** | Olemassa oleva API server (`:8642`) | Remote Hermes | Chat → Cloud Run (ohut) → `GATEWAY_PROXY_URL` |

Cloud Run `hermes-gateway` **embedded**-moodi (nykyinen oletus repossa) on vain vaihtoehto D —
käytä sitä vain jos et halua ajaa gatewayä muualla.

---

## A. Pub/Sub → olemassa oleva Hermes (suositus jos org sallii)

Hermes yhdistää **ulos** GCP:hen — sama malli kuin Telegram/Slack. Ei tarvita Cloud Runia eikä OpenRouter-avainta Secret Manageriin.

### 1. GCP-infra (jo olemassa projektissa `od-azuracast-sync`)

- Topic: `hermes-chat-events`
- Subscription: `hermes-chat-events-sub`
- SA: `hermes-chat-bot@od-azuracast-sync.iam.gserviceaccount.com`

Aja tarvittaessa: `bash infra/setup_gcp.sh` (`HERMES_CHAT_TRANSPORT=pubsub`).

### 2. Chat API Console

- Connection: **Cloud Pub/Sub**
- Topic: `projects/od-azuracast-sync/topics/hermes-chat-events`
- Topic IAM: publisher = Chat-appin Connection settings -sivulta näkyvä SA  
  (ei välttämättä `chat-api-push@…` — org voi vaatia `gcp-sa-gsuiteaddons`-tiliä)

### 3. Olemassa oleva Hermes (`~/.hermes/.env`)

```bash
bash scripts/print_existing_hermes_env.sh --transport pubsub
```

Lisää tulostus `~/.hermes/.env`:ään. Tarvitset SA JSON -avaimen subscriber-oikeudella
(tai aja Hermes GCP-VM:llä attached SA:lla).

### 4. Käynnistä gateway

```bash
hermes gateway
# → [GoogleChat] Connected; subscription=…
```

LLM-avaimet ja profiilit tulevat **olemassa olevasta** `HERMES_HOME`:sta — ei mitään uutta avainta GCP:hen.

---

## B. HTTP → olemassa oleva Hermes (julkinen URL)

Jos Hermes-gateway kuuntelee jo HTTPS:ää (reverse proxy, Cloudflare Tunnel, jne.):

1. Olemassa olevaan `~/.hermes/.env`:

```bash
bash scripts/print_existing_hermes_env.sh --transport http \
  --public-url https://hermes.sinun-palvelin.fi
```

2. Chat API Console → **HTTP endpoint URL**:

```
https://hermes.sinun-palvelin.fi/api/platforms/google_chat/events
```

3. `hermes gateway` (tai systemd/docker jolla se jo pyörii)

---

## C. Proxy-relay: Cloud Run vain Chatille, agentti remote

Käytä kun Hermes pyörii kotona/VM:llä **API server -tilassa** mutta sillä ei ole julkista Chat-endpointia.

```
Google Chat → Cloud Run (proxy gateway) → GATEWAY_PROXY_URL → sinun Hermes :8642
```

### Remote Hermes (missä agentit jo ovat)

`~/.hermes/.env`:

```env
API_SERVER_ENABLED=true
API_SERVER_HOST=0.0.0.0
API_SERVER_PORT=8642
API_SERVER_KEY=<vahva-satunnainen>   # sama kuin GATEWAY_PROXY_KEY relayssä
# OPENROUTER_API_KEY / profiilit — jo olemassa, ei muutosta
```

Remote pitää olla **saavutettavissa Cloud Runista** (julkinen IP, Tailscale subnet router, Cloudflare Tunnel jne.).

### Cloud Run relay (ei LLM-avainta)

```bash
export GCP_PROJECT=od-azuracast-sync
export GCP_REGION=europe-north1
export HERMES_GATEWAY_MODE=proxy
export GATEWAY_PROXY_URL=https://hermes.sinun-palvelin.fi:8642
export GATEWAY_PROXY_KEY=<sama kuin API_SERVER_KEY>
bash deploy/cloudrun/deploy.sh
```

Chat Console HTTP endpoint = Cloud Run URL (`out/deploy.env` → `CHAT_HTTP_EVENTS_URL`).

---

## Poista embedded-moodi (valinnainen)

Jos siirryt täysin olemassa olevaan Hermekseen:

```bash
gcloud run services delete hermes-gateway \
  --project=od-azuracast-sync --region=europe-north1 --quiet
```

Secret `hermes-llm-api-key` ei ole enää tarpeen proxy/pubsub-direct -poluissa.

---

## Useita agentteja / profiileja

Hermes reitittää profiileja omalla logiikallaan (`hermes -p profiili`, multi-profile gateway).
Google Chat -adapteri lukee **reititetyn profiilin** `.env`:n — kopioi `GOOGLE_CHAT_*` jokaiselle
profiilille joka saa vastata Chatissa, tai pidä yksi “chat-profiili” gatewayssä.

Katso upstream: [Google Chat setup](https://hermes-agent.nousresearch.com/docs/user-guide/messaging/google_chat).
