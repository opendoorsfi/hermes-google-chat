# Google Chat — asennus (multi-tenant Hermes)

Tämä ohje kattaa **tuotantomallin**: Google Chat → Tailscale Funnel → Caddy → `hermes gateway` host-VM:llä.
LLM-avaimet pysyvät `~/.hermes/.env`:ssä — **ei** GCP Secret Manageriin.

## Mitä tarvitset

| Tarve | Kuvaus |
|-------|--------|
| Google Workspace | Chat-appit eivät toimi Gmail-only -tilillä |
| GCP-projekti per tenant | Esim. `hermes-alice`, `hermes-team` |
| Host-VM (24/7) | Linux, systemd, Caddy, Hermes CLI |
| Tailscale + Funnel | Julkinen HTTPS Chatille (Chat ei näe tailnet-IP:tä) |
| GitHub repo | `opendoorsfi/hermes-google-chat` + Actions-secrets |

Arkkitehtuuri: [MULTI_TENANT.md](MULTI_TENANT.md), [TAILSCALE.md](TAILSCALE.md).

---

## Vaihe 0 — GitHub Actions (kerran)

Cloud Agent **ei voi** asettaa org-repon secrets — aja **omalla admin-PAT:lla** tai `gh auth login`:

```bash
gh auth login   # tili jolla on repo admin / secrets write
cd /path/to/hermes-google-chat
bash scripts/bootstrap_github_secrets.sh
```

Skripti asettaa (arvot repossa [CREATE_REPO.md](CREATE_REPO.md)):

| Secret | Arvo |
|--------|------|
| `GCP_WIF_PROVIDER` | `projects/381850973284/locations/global/workloadIdentityPools/github-pool/providers/github-provider` |
| `GCP_DEPLOY_SA_EMAIL` | `github-azuracast-deploy@od-azuracast-sync.iam.gserviceaccount.com` |

Jos `gcloud` on kirjautuneena, skripti ajaa myös [setup_github_wif.sh](../scripts/setup_github_wif.sh).

**Deploy-SA tenant-projekteissa** (kerran per projekti):

```bash
bash scripts/bootstrap_github_secrets.sh --grant-tenants hermes-alice,hermes-team
# tai ks. docs/GITHUB_SECRETS.md
```

---

## Vaihe 1 — Tenant manifest

```bash
cp config/tenants/alice.env.example config/tenants/alice.env
```

Muokkaa `config/tenants/alice.env`:

```env
TENANT=alice
GCP_PROJECT=hermes-alice          # luo GCP Console → New Project
LINUX_USER=hermes-alice
PORT=8081
PATH_PREFIX=/alice
ROLE=personal
CHAT_APP_DISPLAY_NAME="Hermes (Alice)"
GOOGLE_CHAT_ALLOWED_USERS=sinä@info.opendoors.fi   # pakollinen — Funnel on julkinen
FUNNEL_BASE_URL=https://hermes-host.tailXXXX.ts.net  # päivitetään vaihe 4 jälkeen
```

`config/tenants/*.env` on gitignoressa — ei commitoida.

---

## Vaihe 2 — GCP tenant (Chat API + service account)

### Vaihtoehto A: GitHub Actions (suositus)

1. Avaa [Setup tenant GCP](https://github.com/opendoorsfi/hermes-google-chat/actions/workflows/tenant-gcp.yml)
2. **Run workflow**
3. Inputs:
   - `tenant`: `alice`
   - `funnel_base_url`: `https://<tailscale-hostname>.ts.net` (tarkka URL vaihe 4 jälkeen; voit ajaa uudelleen)
   - `gcp_project`: `hermes-alice` (jos eri kuin manifestissa)
4. Lataa artefakti: `gcp.env` + `CHAT_CONSOLE_CHECKLIST.md`

### Vaihtoehto B: Paikallinen gcloud

```bash
# Luo projekti Consolesta tai:
gcloud projects create hermes-alice --organization=YOUR_ORG_ID  # tarvittaessa

export TENANT=alice
export FUNNEL_BASE_URL=https://hermes-host.tail1234.ts.net
bash infra/setup_tenant_gcp.sh
# → out/tenants/alice/hermes-chat-bot-sa.json (jos org policy sallii)
# → out/tenants/alice/CHAT_CONSOLE_CHECKLIST.md
```

---

## Vaihe 3 — Host-VM (Hermes + Caddy)

**Esivalmistelut hostilla:**

```bash
# Hermes CLI (upstream-asennus — ks. Hermes-dokumentaatio)
# Caddy: https://caddyserver.com/docs/install
# Tailscale: https://tailscale.com/download/linux
sudo tailscale up
```

Asenna tenant:

```bash
git clone git@github.com:opendoorsfi/hermes-google-chat.git
cd hermes-google-chat

# Kopioi manifest hostille (tai luo suoraan config/tenants/alice.env)
sudo bash scripts/install_hermes_host.sh --tenant alice
```

Lisää Hermes-env (Chat + HTTP):

```bash
bash scripts/print_tenant_env.sh alice | sudo tee -a /home/hermes-alice/.hermes/.env
```

**Service account JSON** (outbound Chat REST — viestien lähetys):

```bash
sudo cp out/tenants/alice/hermes-chat-bot-sa.json \
  /home/hermes-alice/.hermes/secrets/google-chat-sa.json
sudo chown hermes-alice:hermes-alice /home/hermes-alice/.hermes/secrets/google-chat-sa.json
sudo chmod 600 /home/hermes-alice/.hermes/secrets/google-chat-sa.json
```

Lisää `.env`:ään (tai export gateway-yksikössä):

```env
GOOGLE_APPLICATION_CREDENTIALS=/home/hermes-alice/.hermes/secrets/google-chat-sa.json
```

**LLM-avaimet** — lisää samaan `/home/hermes-alice/.hermes/.env`:ään (jo olemassa oleva Hermes-asennus):

```env
OPENROUTER_API_KEY=<openrouter-avain>
# tai muu provider — Hermes-dokumentaatio
```

Käynnistä gateway:

```bash
sudo systemctl start hermes-gateway@hermes-alice
sudo systemctl status hermes-gateway@hermes-alice
journalctl -u hermes-gateway@hermes-alice -f
```

Odotettu: gateway kuuntelee `127.0.0.1:8081`, ei config validation -virheitä.

---

## Vaihe 4 — Tailscale Funnel (julkinen HTTPS)

```bash
sudo bash deploy/host/tailscale-funnel.sh
```

Skripti tulostaa Funnel base URL:n, esim. `https://hermes-vm.tail1234.ts.net`.

Päivitä manifest:

```bash
# config/tenants/alice.env
FUNNEL_BASE_URL=https://hermes-vm.tail1234.ts.net
```

Päivitä `.env` (tai aja uudelleen):

```bash
bash scripts/print_tenant_env.sh alice | sudo tee -a /home/hermes-alice/.hermes/.env
sudo systemctl restart hermes-gateway@hermes-alice
```

**Verifiointi** (hostilta tai dev-koneelta):

```bash
bash scripts/verify_tenant.sh alice
# OK — endpoint reachable, auth rejected as expected (HTTP 401)
```

401/403 ilman JWT:tä = oikein. Chat lähettää allekirjoitetun JWT:n.

---

## Vaihe 5 — Google Chat API Console

Jokaisella tenantilla **oma GCP-projekti** → oma Chat-app.

1. [Google Cloud Console](https://console.cloud.google.com/) → valitse **`hermes-alice`**
2. **APIs & Services** → **Google Chat API** → **Configuration** (tai **Manage Google Chat apps**)
3. Täytä (tarkemmin: `out/tenants/alice/CHAT_CONSOLE_CHECKLIST.md`):

| Kenttä | Arvo |
|--------|------|
| App status | **Live** (tai Testing + testaajat) |
| App name | `Hermes (Alice)` (= `CHAT_APP_DISPLAY_NAME`) |
| Avatar / Description | Vapaaehtoinen |
| Functionality | ☑ Receive 1:1 messages |
| | ☑ Join spaces and group conversations |
| Connection settings | **HTTP endpoint URL** |
| URL | `https://hermes-vm.tail1234.ts.net/alice/api/platforms/google_chat/events` |
| Visibility | **Specific people** → `GOOGLE_CHAT_ALLOWED_USERS` -emailit |

4. **Save**

> **Huom:** Open Doors -orgissa Pub/Sub-yhteys vaatii org-adminia (`chat-api-push@…` topic IAM).
> Käytä aina **HTTP endpoint URL** -mallia ([chat_api_config.md](../infra/chat_api_config.md)).

---

## Vaihe 6 — Asenna botti Google Chatissa

### Henkilökohtainen (DM)

1. Avaa [Google Chat](https://chat.google.com/)
2. **New chat** (+) → **Find apps** / **Browse apps**
3. Etsi **Hermes (Alice)** (app name Consolesta)
4. **Message** → avaa DM
5. Lähetä: `Hei` tai `hola`

### Team-space

1. **Spaces** → **Create space**
2. Space-asetuksissa → **Apps** → **Add apps** → **Hermes (Team)** (team-tenant)
3. Henkilöbottit (`Hermes (Alice)`) vain DM:ään — älä sekoita moderointi-bottiin ([SPACES.md](SPACES.md))

### Ensimmäinen viesti

- Chat POSTaa HTTP-endpointiin → Caddy → `hermes gateway`
- Hermes tarkistaa JWT:n (`chat@system.gserviceaccount.com`) ja `GOOGLE_CHAT_ALLOWED_USERS`
- Vastaus tulee DM:ään tai spaceen

**Lokit:**

```bash
journalctl -u hermes-gateway@hermes-alice -n 50 --no-pager
sudo journalctl -u caddy-hermes -n 30 --no-pager
```

---

## Vaihe 7 — Useampi tenant (bob, team)

```bash
cp config/tenants/alice.env.example config/tenants/bob.env
# muokkaa PORT=8082, PATH_PREFIX=/bob, GCP_PROJECT=hermes-bob, ...

TENANT=bob bash scripts/provision_tenant.sh --gcp-only   # tai Actions workflow
sudo bash scripts/install_hermes_host.sh --tenant bob    # lisää Caddy-block
sudo bash deploy/host/tailscale-funnel.sh                # uudelleen jos tarpeen
```

Endpointit:

- Alice: `https://<host>.ts.net/alice/api/platforms/google_chat/events`
- Bob: `https://<host>.ts.net/bob/api/platforms/google_chat/events`
- Team: `https://<host>.ts.net/team/api/platforms/google_chat/events`

---

## Vianmääritys

| Oire | Tarkista |
|------|----------|
| Botti ei vastaa | `verify_tenant.sh` → 401 OK? Funnel päällä? `GOOGLE_CHAT_ALLOWED_USERS` sisältää emailisi? |
| HTTP 403 Chatista | Email ei allow-listalla; app Testing-tilassa ilman testaajaa |
| Gateway kaatuu käynnistyksessä | `journalctl -u hermes-gateway@hermes-alice`; puuttuva LLM-avain tai SA JSON |
| Chat Console “endpoint unreachable” | Funnel/Caddy/gateway; testaa `curl -X POST <events_url> -d '{}'` → 401 |
| Outbound viestit fail | SA JSON puuttuu tai väärä projekti |
| Actions workflow fail | Secrets puuttuvat → `bootstrap_github_secrets.sh`; deploy-SA IAM tenant-projektissa |

Katso myös [RUNBOOK.md](RUNBOOK.md), [EXISTING_HERMES.md](EXISTING_HERMES.md) (Pub/Sub / proxy-vaihtoehdot).

---

## Pikakomennot (copy-paste)

```bash
# Secrets (admin-koneella)
bash scripts/bootstrap_github_secrets.sh --grant-tenants hermes-alice

# Tenant end-to-end (gcloud + root hostilla)
TENANT=alice bash scripts/provision_tenant.sh

# Vain tarkistus
bash scripts/verify_tenant.sh alice
```
