# Cloud Run embedded Hermes — poisto

Multi-tenant -mallissa **ei käytetä** Cloud Run -embedded Hermes -agenttia (`hermes-gateway` + `hermes-llm-api-key`).

Poista vanha kokeilu projektista `od-azuracast-sync`:

```bash
gcloud run services delete hermes-gateway \
  --project=od-azuracast-sync \
  --region=europe-north1 \
  --quiet
```

Valinnainen (jos ei muuta käyttöä):

```bash
gcloud secrets delete hermes-llm-api-key --project=od-azuracast-sync --quiet
```

**Kommenttimoderointi** (`chat-moderation` Cloud Run) on erillinen — **älä poista**.
