# Erillinen repo (tuotanto)

> **Tila:** export on tehty — tämä repo *on* `opendoorsfi/hermes-google-chat`. Alla olevat
> export/push-ohjeet ovat historiallisia; jäljellä on vain [secrets + WIF](GITHUB_SECRETS.md).

| Repo | Vastuu |
|------|--------|
| **opendoorsfi/hermes-google-chat** | Hermes + Google Chat multi-tenant |
| **opendoorsfi/moderate** | Kommenttimoderointi (Zapier, Sheet, `chat-moderation`) |

Moderate-monorepon Hermes-workflowt on poistettu — älä sekoita repoja.

## Nopea polku

Katso [CREATE_REPO.md](CREATE_REPO.md) — **repo pitää luoda GitHub UI:ssa ensin** (org admin).

```bash
# 1. UI: https://github.com/organizations/opendoorsfi/repositories/new → hermes-google-chat (empty, private)
# 2. Export
bash scripts/export_hermes_google_chat_repo.sh   # moderate-juuresta
cd /tmp/hermes-google-chat-export
git remote add origin git@github.com:opendoorsfi/hermes-google-chat.git
git push -u origin main
# 3. Secrets (CREATE_REPO.md)
```

## Miksi `gh repo create` epäonnistuu

`Resource not accessible by integration` = tokenilla ei ole oikeutta luoda org-repoa.
Ratkaisu: org-admin luo tyhjän repon käsin → push exportista.

## WIF

`HERMES_GITHUB_REPO=opendoorsfi/hermes-google-chat bash scripts/setup_github_wif.sh`
