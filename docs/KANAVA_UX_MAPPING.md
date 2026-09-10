# kanava-ux → Hermes Google Chat -mapping

> **Tila:** `opendoorsfi/kanava-ux` ei ollut luettavissa automaatiolla (404). Tämä dokumentti
> päivitetään heti kun repo on jaettu. Alla on väliaikainen mapping suunnitelman ja julkisen
> Hermes-dokumentaation pohjalta.

## Mitä kanava-ux:stä odotetaan (kun pääsy saadaan)

| kanava-ux-lähde | Hermes-google-chat -kohde |
|-----------------|---------------------------|
| `AGENTS.md` | [`AGENTS.md`](../AGENTS.md) — vastuunjako |
| Kanava / space -määrittely | `GOOGLE_CHAT_HOME_CHANNEL`, [`docs/SPACES.md`](SPACES.md) |
| Profiilit / persona | [`profiles/opendoors/`](../profiles/opendoors/) |
| UX-komennot (slash) | Hermes gateway + profiilin system prompt |
| LLM-provider | Secret Manager → `OPENROUTER_API_KEY` / `OPENAI_API_KEY` |
| Allowed users | `GOOGLE_CHAT_ALLOWED_USERS` |

## Hermes natiivi vs kanava-UX-vaatimus

| Ominaisuus | Hermes Agent | kanava-UX (täydennettävä) |
|------------|--------------|---------------------------|
| Chat-viestit DM/space | Google Chat adapter (Pub/Sub) | Space-ID, tervehdysteksti |
| Threadit | `thread.name` → erillinen session | — |
| Kanban | `/kanban`, `hermes kanban` | Mahd. kanava-UX-komennot Chatissa |
| Card v2 (clarify) | Automaattinen | — |
| Tiedostoliitteet | `/setup-files` per-user OAuth | Vaihe 2 |
| Analytics / kanavat | Ei natiivisti | Mahd. myöhempi integraatio |

## Väliaikainen Open Doors -profiili (geneerinen)

Kunnes kanava-ux-speksi on luettu, käytetään [`profiles/opendoors/config.yaml`](../profiles/opendoors/config.yaml):

- Profiili: `opendoors`
- Kieli: suomi
- Rooli: Open Doors Finland -avustaja (kanava-analytiikka, sisältö, tiimi)
- Ei kommenttimoderointia (se on erillisessä `moderate`-repossa)

## Eri repo — ei duplikointia

| Asia | moderate (`chat-moderation`) | hermes-google-chat |
|------|------------------------------|---------------------|
| Tarkoitus | FB/IG/YT kommenttien hyväksyntä | Hermes-agentti Chatissa |
| Inbound | HTTP `/chat` + JWT | Pub/Sub pull |
| Outbound | Chat REST + Zapier HMAC | Chat REST (Hermes adapter) |
| Space | `spaces/AAQA4is7Y6Y` (moderointi) | **Oma space suositus** (ks. SPACES.md) |

## Seuraava askel kun kanava-ux aukeaa

1. Kloonaa repo ja päivitä tämä tiedosto konkreettisilla viittauksin.
2. Korvaa `profiles/opendoors/` kanava-ux:n profiileilla.
3. Päivitä `config/hermes.env.example` allowed users + home channel.
4. Commit + deploy.
