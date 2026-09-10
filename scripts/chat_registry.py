#!/usr/bin/env python3
"""Tenant registry: email → manifest. Source of truth: config/tenants/registry.json."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REGISTRY_PATH = ROOT / "config" / "tenants" / "registry.json"
TENANTS_DIR = ROOT / "config" / "tenants"
BASE_PORT = 8081


def load_registry() -> dict:
    data = json.loads(REGISTRY_PATH.read_text(encoding="utf-8"))
    if "users" not in data:
        raise ValueError("registry.json: missing 'users'")
    return data


def email_to_tenant_id(email: str) -> str:
    local = email.split("@", 1)[0].lower()
    tid = re.sub(r"[^a-z0-9]+", "-", local).strip("-")
    if not tid or not re.match(r"^[a-z0-9][a-z0-9-]{0,30}$", tid):
        raise ValueError(f"invalid tenant id from email: {email}")
    return tid


def display_name(tenant_id: str) -> str:
    parts = tenant_id.replace("-", " ").split()
    label = " ".join(p[:1].upper() + p[1:] for p in parts if p)
    return f"Hermes ({label})"


def allocate_port(index: int) -> int:
    return BASE_PORT + index


def tenant_manifest(
    email: str, index: int, funnel_base_url: str, gcp_project: str
) -> dict[str, str]:
    tid = email_to_tenant_id(email)
    port = str(allocate_port(index))
    prefix = f"/{tid}"
    return {
        "TENANT": tid,
        "GCP_PROJECT": gcp_project,
        "SA_NAME": f"hermes-chat-{tid}",
        "LINUX_USER": f"hermes-{tid}",
        "PORT": port,
        "PATH_PREFIX": prefix,
        "ROLE": "personal",
        "CHAT_APP_DISPLAY_NAME": display_name(tid),
        "GOOGLE_CHAT_ALLOWED_USERS": email.strip().lower(),
        "FUNNEL_BASE_URL": funnel_base_url.rstrip("/"),
    }


def env_value(value: str) -> str:
    """Shell-safe .env value (spaces, parentheses, etc.)."""
    if re.search(r'[\s#"$`!()\\]', value):
        escaped = value.replace("\\", "\\\\").replace('"', '\\"')
        return f'"{escaped}"'
    return value


def write_env(manifest: dict[str, str]) -> Path:
    TENANTS_DIR.mkdir(parents=True, exist_ok=True)
    path = TENANTS_DIR / f"{manifest['TENANT']}.env"
    lines = [f"{k}={env_value(v)}" for k, v in manifest.items()]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return path


def generate_all() -> list[dict[str, str]]:
    reg = load_registry()
    funnel = reg.get("funnel_base_url", "").strip()
    gcp_project = reg.get("gcp_project", "od-azuracast-sync").strip()
    manifests = []
    for i, email in enumerate(reg["users"]):
        email = email.strip()
        if not email:
            continue
        m = tenant_manifest(email, i, funnel, gcp_project)
        write_env(m)
        manifests.append(m)
    return manifests


def list_tenant_ids() -> list[str]:
    return [m["TENANT"] for m in generate_all()]


def add_user(email: str) -> dict[str, str]:
    reg = load_registry()
    email = email.strip().lower()
    users = [u.strip().lower() for u in reg["users"]]
    if email not in users:
        users.append(email)
        reg["users"] = users
        REGISTRY_PATH.write_text(json.dumps(reg, indent=2) + "\n", encoding="utf-8")
    idx = users.index(email)
    funnel = reg.get("funnel_base_url", "")
    gcp_project = reg.get("gcp_project", "od-azuracast-sync").strip()
    m = tenant_manifest(email, idx, funnel, gcp_project)
    write_env(m)
    return m


def main() -> int:
    if len(sys.argv) < 2:
        print("Usage: chat_registry.py generate-all|list-ids|add EMAIL|matrix-json", file=sys.stderr)
        return 1
    cmd = sys.argv[1]
    if cmd == "generate-all":
        generate_all()
        return 0
    if cmd == "list-ids":
        for tid in list_tenant_ids():
            print(tid)
        return 0
    if cmd == "add":
        if len(sys.argv) < 3:
            print("Usage: chat_registry.py add EMAIL", file=sys.stderr)
            return 1
        m = add_user(sys.argv[2])
        print(json.dumps(m, indent=2))
        return 0
    if cmd == "matrix-json":
        ids = list_tenant_ids()
        print(json.dumps({"tenant": ids}))
        return 0
    if cmd == "summary":
        reg = load_registry()
        funnel = reg.get("funnel_base_url", "")
        gcp_project = reg.get("gcp_project", "od-azuracast-sync").strip()
        for i, email in enumerate(reg["users"]):
            email = email.strip()
            if not email:
                continue
            m = tenant_manifest(email, i, funnel, gcp_project)
            events = f"{m['FUNNEL_BASE_URL']}{m['PATH_PREFIX']}/api/platforms/google_chat/events"
            print(f"## {m['CHAT_APP_DISPLAY_NAME']} (`{m['TENANT']}`)")
            print(f"- Email: `{m['GOOGLE_CHAT_ALLOWED_USERS']}`")
            print(f"- GCP: `{m['GCP_PROJECT']}`")
            print(f"- Chat HTTP URL: `{events}`")
            print(f"- Chatissa: Find apps → **{m['CHAT_APP_DISPLAY_NAME']}** → Message → `Hei`")
            print()
        return 0
    print(f"unknown command: {cmd}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
