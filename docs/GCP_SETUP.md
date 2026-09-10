# GCP-asennus

## Esivaatimukset

- Google Workspace (Chat-appit eivät toimi Gmail-only -tilillä)
- `gcloud` CLI, projektin Owner tai riittävät IAM-oikeudet
- GitHub repo + WIF (deploy)

## Vaiheet

### 1. Projekti

```bash
export GCP_PROJECT=od-hermes-chat
export GCP_REGION=europe-north1
gcloud config set project "$GCP_PROJECT"
```

### 2. Infra-skripti

```bash
bash infra/setup_gcp.sh
```

Luo:

- API:t (Run, Pub/Sub, Chat, Secret Manager, Artifact Registry)
- Service account `hermes-chat-bot`
- Topic `hermes-chat-events`, subscription `hermes-chat-events-sub`
- IAM: `chat-api-push@system.gserviceaccount.com` → Publisher topicille
- IAM: runtime SA → Subscriber + Viewer subscriptionille
- Secret Manager -placeholderit

### 3. SA-avain Secret Manageriin

```bash
# Luo avain (vain jos setup_gcp ei tee sitä automaattisesti)
gcloud iam service-accounts keys create /tmp/sa.json \
  --iam-account=hermes-chat-bot@${GCP_PROJECT}.iam.gserviceaccount.com

gcloud secrets versions add hermes-google-chat-sa-json --data-file=/tmp/sa.json
rm /tmp/sa.json
```

> Cloud Run käyttää mieluummin Workload Identity / attached SA. Pub/Sub subscriber
> vaatii SA:n subscription-IAM:issa. Hermes adapter lukee JSON-polun
> `GOOGLE_APPLICATION_CREDENTIALS`.

### 4. LLM-avaimet

```bash
echo -n "$OPENROUTER_API_KEY" | gcloud secrets versions add hermes-llm-api-key --data-file=-
```

### 5. Chat API

Katso [`infra/chat_api_config.md`](../infra/chat_api_config.md).

### 6. Ensimmäinen deploy

GitHub Actions tai paikallisesti:

```bash
export GCP_PROJECT GCP_REGION
bash deploy/cloudrun/deploy.sh
```

### 7. Verifiointi

```bash
bash scripts/verify_pubsub.sh
# Lähetä "hola" Chatissa → Cloud Run logit: [GoogleChat] Connected
```
