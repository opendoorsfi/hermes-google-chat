# od-kansiot — käynnistys (sinulle)

PR merged. GitHub Hub yrittää synkata automaattisesti — **se epäonnistuu** kunnes alla olevat kolme admin-askelta on tehty.

## 1. GCP bootstrap (sinä, kerran)

Koneella jossa `gcloud auth login` + admin `od-kansiot`:

```bash
git clone git@github.com:opendoorsfi/hermes-google-chat.git
cd hermes-google-chat && git pull origin main
export GCP_PROJECT=od-kansiot
bash scripts/bootstrap_od_kansiot_project.sh
```

Kopioi tulostus: `GCP_WIF_PROVIDER=projects/...`

## 2. GitHub secrets (sinä, kerran)

Repo → Settings → Secrets and variables → Actions:

| Secret | Arvo |
|--------|------|
| `GCP_WIF_PROVIDER` | bootstrapin tulostama |
| `GCP_DEPLOY_SA_EMAIL` | `github-hermes-deploy@od-kansiot.iam.gserviceaccount.com` |

Tai: `bash scripts/bootstrap_github_secrets.sh --wif` (gh auth + admin-oikeudet).

## 3. Aja Hub uudelleen

https://github.com/opendoorsfi/hermes-google-chat/actions/workflows/sync-chat-users.yml  
→ **Run workflow** → email: `ipad@info.opendoors.fi`  
→ pitää olla **vihreä**.

## 4. Console Save (sinä, kerran)

https://console.cloud.google.com/apis/api/chat.googleapis.com/hangouts-chat?project=od-kansiot

| Kenttä | Arvo |
|--------|------|
| App name | `hermes-chat` |
| Connection | Pub/Sub → `projects/od-kansiot/topics/hermes-chat-events` |
| Visibility | `ipad@info.opendoors.fi` (+ muut) |
| Status | Live → **Save** |

## 5. Host work-h

Gateway + SA JSON projektista `od-kansiot`. Tarkista: `hermes gateway` → `[GoogleChat] Connected`.

## 6. Testaa

https://chat.google.com/ → **hermes-chat** → `Hei`

---

Uusi käyttäjä jatkossa: kerro agentille email → Hub hoitaa loput.
