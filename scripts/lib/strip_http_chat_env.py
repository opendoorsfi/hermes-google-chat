#!/usr/bin/env python3
"""Poista HTTP-inbound rivit ~/.hermes/.env:stä — ne estävät Pub/Sub-pullin."""
from __future__ import annotations

import pathlib
import sys

HTTP_KEYS = (
    "GOOGLE_CHAT_HTTP_EVENTS_URL",
    "GOOGLE_CHAT_HTTP_EVENTS_AUDIENCE",
    "GOOGLE_CHAT_HTTP_EVENTS_SERVICE_ACCOUNT_EMAIL",
    "API_SERVER_ENABLED",
    "API_SERVER_HOST",
    "API_SERVER_PORT",
    "API_SERVER_KEY",
    "GATEWAY_PROXY_URL",
    "GATEWAY_PROXY_KEY",
)


def strip_http_lines(text: str) -> tuple[str, list[str]]:
    removed: list[str] = []
    out: list[str] = []
    skip_markers = ("# --- Google Chat mac bootstrap ---", "# --- end Google Chat mac bootstrap ---")
    in_mac_block = False
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("# --- Google Chat mac bootstrap"):
            in_mac_block = True
            removed.append(line)
            continue
        if in_mac_block:
            removed.append(line)
            if stripped.startswith("# --- end Google Chat mac bootstrap"):
                in_mac_block = False
            continue
        key = line.split("=", 1)[0].strip() if "=" in line else ""
        if key in HTTP_KEYS or key == "HERMES_CHAT_TRANSPORT" and "http" in line.lower():
            removed.append(line)
            continue
        out.append(line)
    new = "\n".join(out).rstrip() + ("\n" if out else "")
    return new, removed


def main() -> int:
    path = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else pathlib.Path.home() / ".hermes" / ".env")
    if not path.is_file():
        print(f"OK: {path} puuttuu")
        return 0
    text = path.read_text(encoding="utf-8")
    new_text, removed = strip_http_lines(text)
    if not removed:
        print("OK: ei HTTP-Chat-rivejä poistettavaksi")
        return 0
    path.write_text(new_text, encoding="utf-8")
    print(f"Poistettu {len(removed)} HTTP-Chat-rivi(ä) (Pub/Sub-tila):")
    for line in removed[:12]:
        print(f"  - {line}")
    if len(removed) > 12:
        print(f"  ... +{len(removed) - 12} riviä")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
