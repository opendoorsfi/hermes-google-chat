# Runbook — hermes-google-chat

## Bot ei vastaa ("hola" → hiljaisuus)

1. **Pub/Sub subscription — undelivered messages?**
   ```bash
   bash scripts/verify_pubsub.sh
   ```
   - Jos viestejä kertyy mutta Hermes ei käsittele → SA / credentials
   - Jos nolla viestejä → Chat API ei julkaise topicille

2. **Topic IAM**
   - `chat-api-push@system.gserviceaccount.com` → `roles/pubsub.publisher` **topicilla**

3. **Subscription IAM**
   - `hermes-chat-bot@...` → `roles/pubsub.subscriber` + `roles/pubsub.viewer`

4. **Cloud Run**
   - `min-instances >= 1`
   - Logit: `[GoogleChat] Connected` tai `Config validation failed`

5. **Chat API Configuration**
   - Connection = Cloud Pub/Sub, oikea topic-polku

## 403 Forbidden outbound (HTTP-tila)

- **Inbound toimii, outbound ei:** `~/.hermes/secrets/google-chat-sa.json` puuttuu tai vanha väärä avain.
  ADC (`gcloud auth application-default login`) **ei riitä** — Hermes tarvitsee `hermes-chat-bot@<projekti>.iam.gserviceaccount.com` JSON-avaimen.
  ```bash
  gcloud auth login   # kerran Macilla
  bash scripts/refresh_chat_sa.sh natalia --restart
  ```
- Pub/Sub→HTTP Console-muutos / uusi DM → aloita uusi keskustelu Find apps → hermes-chat
- Botti poistettu spacesta → lisää uudelleen
- App poistettu käytöstä Consolesta

## Rate limit

Chat API ~60 viestiä / space / min. Hermes backoffaa; lyhennä vastauksia.

## google-cloud-pubsub puuttuu

Dockerissa: `pip install google-cloud-pubsub` (Dockerfile tekee tämän).
Ilman sitä virhe voi näyttää "invalid SA" — harhaanjohtava.

## GOOGLE_CHAT_ALLOWED_USERS

Käyttäjän email ei listalla → viesti hylätään. Päivitä env ja redeploy.

## LLM-virheet

- Tarkista Secret `hermes-llm-api-key`
- Cloud Run logit: provider timeout / 401

## Deploy epäonnistuu (GitHub Actions)

- WIF: `GCP_WIF_PROVIDER`, `GCP_DEPLOY_SA_EMAIL`
- Artifact Registry API enabled
- Deploy SA: `roles/run.admin`, `roles/artifactregistry.writer`

## Ero moderate-repoon

| Oire moderate | Hermes-google-chat |
|---------------|-------------------|
| 401 Invalid signature (HMAC) | Ei HMAC — ei relevantti |
| Apps Script 405 | Ei Apps Script |
| webhook_secret puuttuu | Ei webhook_secret |

## Liitteet (vaihe 2)

Käyttäjä: `/setup-files` DM:ssä. Katso Hermes Google Chat -dokumentaatio.
