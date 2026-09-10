#!/usr/bin/env python3
"""Poista Pub/Sub-inbound rivit ~/.hermes/.env:stä — ne estävät HTTP-callbackit.

Hermes google_chat -adapter: jos GOOGLE_CHAT_SUBSCRIPTION_NAME on asetettu,
se ohittaa GOOGLE_CHAT_HTTP_EVENTS_URL:n kokonaan.
"""
from __future__ import annotations

import pathlib
import re
import sys

PUBSUB_KEYS = (
    "GOOGLE_CHAT_SUBSCRIPTION_NAME",
    "GOOGLE_CHAT_SUBSCRIPTION",
)


def strip_pubsub_lines(text: str) -> tuple[str, list[str]]:
    removed: list[str] = []
    out: list[str] = []
    for line in text.splitlines():
        key = line.split("=", 1)[0].strip() if "=" in line else ""
        if key in PUBSUB_KEYS:
            removed.append(line)
            continue
        out.append(line)
    return "\n".join(out).rstrip() + ("\n" if text.endswith("\n") or out else ""), removed


def main() -> int:
    path = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else pathlib.Path.home() / ".hermes" / ".env")
    if not path.is_file():
        print(f"OK: {path} puuttuu — ei mitään poistettavaa")
        return 0
    text = path.read_text(encoding="utf-8")
    new_text, removed = strip_pubsub_lines(text)
    if not removed:
        print("OK: ei GOOGLE_CHAT_SUBSCRIPTION_* rivejä")
        return 0
    path.write_text(new_text, encoding="utf-8")
    print(f"Poistettu {len(removed)} Pub/Sub-rivi(ä) → HTTP-tila voi toimia:")
    for line in removed:
        print(f"  - {line}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
