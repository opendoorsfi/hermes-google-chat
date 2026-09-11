#!/usr/bin/env bash
# Tulosta Google Chat API Console -kentät (kopioi → Save).
# Google ei tarjoa API:ta Configuration-muutoksiin — tämä on ainoa tapa vaihtaa HTTP:ksi.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HUB="$(python3 "${ROOT}/scripts/chat_registry.py" hub-json)"
python3 -c "
import json, sys
h = json.loads(sys.argv[1])
url = h['chat_http_events_url']
print('=== Google Chat API Console (yksi Save) ===')
print()
print(h['console_url'])
print()
print('| Kenttä | Arvo |')
print('|--------|------|')
print('| App status | Live |')
print(f\"| App name | {h['chat_app_display_name']} |\")
print('| Functionality | Receive 1:1 + Join spaces |')
if h.get('transport') == 'http':
    print('| Connection | HTTP endpoint URL |')
    print(f'| URL | {url} |')
    print(f'| Authentication audience | HTTP endpoint URL → {url} |')
else:
    print('| Connection | Cloud Pub/Sub |')
    print(f\"| Topic | projects/{h['gcp_project']}/topics/{h['pubsub_topic']} |\")
print(f\"| Visibility | {h['allowed_users']} |\")
print()
print(f\"Tallenna → Google Chat: Find apps → {h['chat_app_display_name']} → **aloita UUSI keskustelu** → Hei\")
print('Gmail-projekti: kirjaudu Chatissa samalla tilillä kuin GCP (esim. opendoorsfinland@gmail.com).')
print('(Pub/Sub→HTTP Console-muutos poistaa botin vanhasta DM:stä — vanha thread ei toimi)')
print()
print('Smoke (pitää olla 401 ilman tokenia):')
print(f'  curl -sS -o /dev/null -w \"%{{http_code}}\" -X POST {url} -H \"Content-Type: application/json\" -d \"{{}}\"')
" "${HUB}"
