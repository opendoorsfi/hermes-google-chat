# Tailscale + useita Hermes-koneita

## Mitä Tailscale ratkaisee — ja mitä ei

| | Tailscale auttaa | Tailscale ei auta |
|---|------------------|-------------------|
| Koneiden välinen yhteys | ✅ `100.x.y.z` — gateway → toisen koneen API server | ❌ Google Chat → suoraan tailnet-IP |
| Admin / debug | ✅ SSH mihin tahansa Hermes-koneeseen | |
| Proxy ketju tailnetissä | ✅ VM gateway → `GATEWAY_PROXY_URL=http://100.x.y.z:8642` | |
| Julkinen Chat-endpoint | | ❌ tarvitaan Pub/Sub, Funnel tai Cloud Run |

**Google Chat ei näe Tailscale-verkkoasi.** Chat-palvelimet eivät voi POSTata `100.x.x.x`:ään.
Inbound tulee joko **GCP Pub/Sub:in kautta** (Hermes vetää ulos) tai **julkisen HTTPS:n kautta**.

---

## Suositus: yksi “Chat-isäntä”, muut agenttipalvelimina

Usealla koneella pyöivä Hermes on ok — **Google Chat -adapteri vain yhdellä** (yksi Pub/Sub subscription).

```
                    ┌─────────────────────────────────────┐
  Google Chat ─────►│ GCP Pub/Sub (tai julkinen HTTPS)    │
                    └──────────────┬──────────────────────┘
                                   │
                    ┌──────────────▼──────────────────────┐
                    │ Chat-isäntä (aina päällä, esim. VM) │
                    │  hermes gateway + Google Chat       │
                    │  GATEWAY_PROXY_URL → tailnet        │
                    └──────────────┬──────────────────────┘
                                   │ Tailscale 100.x.y.z
              ┌────────────────────┼────────────────────┐
              ▼                    ▼                    ▼
        Mac (dev)          Vierekone            VM #2
        API server         API server           profiilit / raskaat työt
        :8642                :8642
```

### Chat-isäntä (valitse yksi)

Hyviä ehdokkaita:

1. **Aina päällä oleva VM** (Tailscale + systemd `hermes gateway`) — paras
2. **Viereinen kone** jos 24/7 päällä
3. **Mac** — vain jos usein päällä; uni katkaisee Chatin

### Muut koneet

- `API_SERVER_ENABLED=true`, `API_SERVER_HOST=0.0.0.0`, portti 8642
- Sama `API_SERVER_KEY` kuin Chat-isännän `GATEWAY_PROXY_KEY` (jos isäntä proxyttaa)
- Profiilit ja LLM-avaimet pysyvät kunkin koneen `~/.hermes`:ssa — **ei tarvitse kopioida avaimia GCP:hen**

---

## Tapa 1: Pub/Sub Chat-isännällä (suositus)

Chat-isäntä (VM) vetää viestit GCP:stä — **ei julkista URL:ia, Tailscale riittää hallintaan**.

Chat-isännän `~/.hermes/.env`:

```bash
# Perus Chat (Pub/Sub)
bash scripts/print_existing_hermes_env.sh --transport pubsub

# Jos agentti ajetaan viereisellä koneella tailnetissä:
GATEWAY_PROXY_URL=http://100.x.y.z:8642
GATEWAY_PROXY_KEY=<sama kuin API_SERVER_KEY viereisellä koneella>
```

Viereisellä koneella:

```env
API_SERVER_ENABLED=true
API_SERVER_HOST=0.0.0.0
API_SERVER_PORT=8642
API_SERVER_KEY=<sama avain>
```

Chat-isäntä hoitaa vain Chat-I/O:n; ajattelu tapahtuu tailnetin yli haluamallasi koneella.

---

## Tapa 2: Tailscale Funnel (HTTP ilman Cloud Runia)

Kun org estää Pub/Sub IAM:n mutta haluat HTTP:n suoraan Hermekseen:

1. Valitse kone (esim. VM) jossa `hermes gateway` + HTTP-moodi
2. [Tailscale Funnel](https://tailscale.com/kb/1223/funnel) → julkinen HTTPS esim.  
   `https://hermes-vm.tailXXXX.ts.net`
3. Chat Console → HTTP endpoint:  
   `https://hermes-vm.tailXXXX.ts.net/api/platforms/google_chat/events`

Funnel on **julkinen** — suojaa `GOOGLE_CHAT_ALLOWED_USERS`:lla.

---

## Tapa 3: Cloud Run relay + Funnel API serveriin

Cloud Run **ei ole** Tailscale-verkossasi → `GATEWAY_PROXY_URL=http://100.x.y.z:8642` **ei toimi** suoraan.

Ketju:

```
Google Chat → Cloud Run (julkinen) → Funnel-URL → Hermes API :8642
```

```bash
# API server -koneella: tailscale funnel 8642
# Saat: https://hermes-vm.tailXXXX.ts.net

export HERMES_GATEWAY_MODE=proxy
export GATEWAY_PROXY_URL=https://hermes-vm.tailXXXX.ts.net
bash deploy/cloudrun/deploy.sh
```

Cloud Run hoitaa Chat-JWT:n; agentti ja avaimet pysyvät tailnet-koneellasi.

---

## Yhteenveto

| Setup | Tailscale rooli |
|-------|-----------------|
| Pub/Sub + VM isäntä | Hallinta SSH:lla; ei tarvita julkista inboundia |
| Gateway proxy → 100.x.y.z | **Toimii** — molemmat tailnetissä |
| Cloud Run → 100.x.y.z | **Ei toimi** — käytä Funnelia tai julkista IP:tä |
| Usea Hermes-kone | Yksi Chat-gateway; muut API servereinä tailnetissä |
