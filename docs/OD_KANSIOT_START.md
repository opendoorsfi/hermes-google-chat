# od-kansiot — käynnistys (sinulle)

PR merged. GitHub Hub yrittää synkata automaattisesti — **se epäonnistuu** kunnes alla olevat kolme admin-askelta on tehty.

## 1. GCP bootstrap (kerran)

### Vaihtoehto A — GitHub (suositus)

1. Luo `od-kansiot`-projektissa SA avain (Owner tai riittävät roolit) — **kerran**
2. Repo → Settings → Secrets → `GCP_BOOTSTRAP_SA_JSON` = koko JSON
3. Actions → **Bootstrap od-kansiot (kerran)** → Run workflow
4. Summary → kopioi `GCP_WIF_PROVIDER` + `GCP_DEPLOY_SA_EMAIL` → secrets

### Vaihtoehto B — Cloud Shell

```bash
git clone https://github.com/opendoorsfi/hermes-google-chat.git
cd hermes-google-chat && export GCP_PROJECT=od-kansiot
bash scripts/bootstrap_od_kansiot_project.sh
```

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
