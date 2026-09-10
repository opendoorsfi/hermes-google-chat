# Käyttäjien lisääminen

**Sinä:** annat workspace-sähköpostin. **GitHub Hub** hoitaa GCP + manifestit.

## Projektit — älä sekoita

| Chat-app | GCP-projekti | Repo |
|----------|--------------|------|
| Moderointi | `od-azuracast-sync` (tms.) | `opendoorsfi/moderate` |
| **hermes-chat** | **`od-kansiot`** | `opendoorsfi/hermes-google-chat` |

Yksi Chat-app (**hermes-chat**) palvelee **kaikkia** Hermes-käyttäjiä samassa projektissa.

## Lisää käyttäjä GitHub Hubista

1. https://github.com/opendoorsfi/hermes-google-chat/actions/workflows/sync-chat-users.yml
2. **Run workflow** → email esim. `ipad@info.opendoors.fi`
3. Hub: registry + Pub/Sub + SA + host-sync

## Console (kerran per projekti)

https://console.cloud.google.com/apis/api/chat.googleapis.com/hangouts-chat?project=od-kansiot

| Kenttä | Arvo |
|--------|------|
| App name | **hermes-chat** |
| Connection | Cloud Pub/Sub |
| Topic | `projects/od-kansiot/topics/hermes-chat-events` |
| Visibility | Kaikki registryn käyttäjät (tai Google Group) |
| Status | Live |

## Chatissa

https://chat.google.com/ → Find apps → **hermes-chat** → Message → `Hei`

## Uusi host (Mac / Linux)

Registryssä `hosts`-entry + käyttäjälle `host`-kenttä. Bootstrap:

```bash
bash scripts/bootstrap_hermes_host.sh ipad@info.opendoors.fi   # Linux
bash scripts/bootstrap_hermes_mac.sh natalia@info.opendoors.fi  # macOS
```
