# Google Chat API — Configuration

Console: **APIs & Services → Google Chat API → Configuration**

## Oletus: HTTP (ei org-adminia)

Open Doors -orgissa **Domain restricted sharing** estää Pub/Sub-mallin
(`chat-api-push@system.gserviceaccount.com` → topic IAM). Käytä **HTTP endpoint URL** -yhteyttä
(sama periaate kuin `chat-moderation` Cloud Runissa).

| Kenttä | Arvo |
|--------|------|
| App name | Hermes (Open Doors) |
| Description | Hermes Agent — avustaja Google Chatissa |
| Functionality | Receive 1:1 messages, Join spaces and group conversations |
| Connection settings | **HTTP endpoint URL** |
| HTTP endpoint URL | `out/deploy.env` → `CHAT_HTTP_EVENTS_URL` |
| Visibility | Specific people / your Workspace only |

Deploy tulostaa URL:n muodossa:

```
https://hermes-gateway-….run.app/api/platforms/google_chat/events
```

Cloud Run deploy käyttää `--no-invoker-iam-check` + JWT-tarkistusta Hermesissä
(`chat@system.gserviceaccount.com`). **Ei** Pub/Sub topic IAM -oikeuksia.

## Vaihtoehto: Pub/Sub (vaatii org-adminin)

Vain jos org sallii `system.gserviceaccount.com` topic-IAM:issa:

```bash
export HERMES_CHAT_TRANSPORT=pubsub
bash infra/setup_gcp.sh
```

| Kenttä | Arvo |
|--------|------|
| Connection settings | Cloud Pub/Sub |
| Topic | `projects/YOUR_PROJECT/topics/hermes-chat-events` |
| Topic IAM | `chat-api-push@system.gserviceaccount.com` → Pub/Sub Publisher |

## Testaus

1. Asenna app spaceen tai DM
2. Lähetä `hola`
3. Cloud Run logs → `[GoogleChat]` / gateway connected
4. Vastaus Chatissa
