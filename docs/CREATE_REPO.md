# GitHub-repon luonti

> **Tila:** vaiheet 1–4 on tehty (repo on olemassa, sisältö pushattu). Jäljellä: [5. Secrets](#5-secrets-vasta-kun-push-onnistui) ja [6. WIF](#6-wif-gcp-kerran).

Hermes Google Chat kuuluu repoonsa **`opendoorsfi/hermes-google-chat`**.

`gh repo create` vaatii org-admin-oikeudet. Cursor-agentti ja tavallinen `gh`-token eivät aina riitä.

## 1. Luo tyhjä repo (GitHub UI)

1. Avaa https://github.com/organizations/opendoorsfi/repositories/new  
   (tai henkilökohtainen New repository, jos org ei onnistu)
2. **Repository name:** `hermes-google-chat`
3. **Private**
4. **Älä** lisää README, .gitignore tai license (export tuo sisällön)
5. Create repository

## 2. Export moderate-monoreposta

```bash
cd /workspace   # tai oma moderate-kloonisi
git pull
bash scripts/export_hermes_google_chat_repo.sh
cd /tmp/hermes-google-chat-export
git log -1
```

## 3. PAT (fine-grained)

1. https://github.com/settings/tokens?type=beta → **Generate new token**
2. **Repository access:** Only select repositories → `opendoorsfi/hermes-google-chat`
3. **Permissions:** Contents → Read and write
4. Kopioi token (alkaa `ghp_`) — **älä** käytä placeholderia `ghp_xxxx`

```bash
export GH_TOKEN=ghp_oikea_token_tähän
bash scripts/verify_github_repo.sh   # 404 = repo puuttuu tai väärä token
```

## 4. Push

`export GH_TOKEN=...` **ei riitä** yksin — git tarvitsee tokenin URL:ssa tai `gh auth login`:

```bash
cd /tmp/hermes-google-chat-export
git remote remove origin 2>/dev/null || true
git remote add origin "https://x-access-token:${GH_TOKEN}@github.com/opendoorsfi/hermes-google-chat.git"
git push -u origin main
```

Tai push-skripti:

```bash
export GH_TOKEN=ghp_...
bash scripts/push_to_github.sh
```

SSH (jos avaimet kunnossa):

```bash
git remote add origin git@github.com:opendoorsfi/hermes-google-chat.git
git push -u origin main
```

## 5. Secrets (vasta kun push onnistui)

```bash
gh secret set GCP_WIF_PROVIDER --repo opendoorsfi/hermes-google-chat \
  --body 'projects/381850973284/locations/global/workloadIdentityPools/github-pool/providers/github-provider'
gh secret set GCP_DEPLOY_SA_EMAIL --repo opendoorsfi/hermes-google-chat \
  --body 'github-azuracast-deploy@od-azuracast-sync.iam.gserviceaccount.com'
```

404 = repo puuttuu tai ei oikeuksia.

## 6. WIF (GCP, kerran)

```bash
export HERMES_GITHUB_REPO=opendoorsfi/hermes-google-chat
bash scripts/setup_github_wif.sh
```

Workflowt: `.github/workflows/ci.yml`, `tenant-gcp.yml`.
