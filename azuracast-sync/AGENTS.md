# AGENTS.md — azuracast-sync

**Standalone repo (tavoite):** `opendoorsfi/azuracast-sync`. **Ei** Hermes Chat / kommenttimoderointi.

## GCP-projekti

| Projekti | Käyttö |
|----------|--------|
| **`od-azuracast-sync`** | AzuraCast Drive-sync Cloud Run |
| `opendoors-hermes-chat` | Hermes Chat — **älä käytä tähän** |

Lähde: `config/registry.json`.

## Arkkitehtuuri

```
Google Drive (mp3) → Cloud Run azuracast-sync (POST /process) → AzuraCast (radio.opendoors.fi)
GitHub Actions → health-check + self-heal (6h)
Telemetry → Google Sheet "AzuraCast Sync Log"
```

## Itsekorjaus (agentit + CI)

Kun sync/yhteys ei toimi:

1. **Älä ohjeista käyttäjää ajamaan komentoja** — aja CI:ssä tai korjaa repo.
2. Diagnoosi: `bash scripts/self_heal_azuracast.sh`
3. Korjaus: workflow **Self-heal AzuraCast sync** tai `--apply`
4. Tarkistaa: AzuraCast `/api/status`, Cloud Run `/health`, API key (jos secret)
5. Epäonnistuneen health-checkin jälkeen self-heal käynnistyy automaattisesti.
6. Uusi toistuva virhe → päivitä `scripts/self_heal_azuracast.sh`.

## Export standalone-repoon

```bash
bash scripts/export_azuracast_sync_repo.sh
```

## Ennen muutosta

```bash
make -C azuracast-sync validate
```
