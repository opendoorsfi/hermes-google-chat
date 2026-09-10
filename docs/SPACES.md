# Google Chat -spacet

## Suositus: erillinen Hermes-space

Moderate-repon kommenttimoderointi käyttää spacea `spaces/AAQA4is7Y6Y` ja erillistä Chat-appia
(`chat-moderation`). **Hermes-botille oma space** välttää sekaannuksen korttien ja bottien välillä.

## Konfigurointi

```bash
# config/hermes.env.example → Secret Manager / Cloud Run env
GOOGLE_CHAT_HOME_CHANNEL=spaces/AAAAxxxxxxxx
GOOGLE_CHAT_BOOTSTRAP_SPACES=spaces/AAAAxxxxxxxx
```

Space-ID löytyy Chat-URL:sta tai API:sta kun botti on lisätty spaceen.

## Asennus spaceen

1. Google Chat → **+ New chat** → etsi app-nimi (Chat API Configuration → App name)
2. Lisää spaceen tai aloita DM
3. Ensimmäinen viesti → Hermes saa `ADDED_TO_SPACE` / `MESSAGE` Pub/Subiin
4. Tarkista Cloud Run -logit: `[GoogleChat] Connected`

## bootstrap_space.sh

```bash
export GCP_PROJECT=od-hermes-chat
bash scripts/bootstrap_space.sh
```

Tulostaa ohjeet ja tarkistaa Pub/Sub-metriikat.

## kanava-ux

Kun `opendoorsfi/kanava-ux` on luettavissa, päivitä tämä tiedosto kanava-UX:n virallisella
space-ID:llä ja näkyvyysasetuksilla.
