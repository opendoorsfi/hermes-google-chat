"""Registry email → tenant manifest tests."""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_registry_json_exists() -> None:
    path = ROOT / "config" / "tenants" / "registry.json"
    assert path.is_file()
    data = json.loads(path.read_text(encoding="utf-8"))
    assert "users" in data
    assert "hosts" in data
    assert "funnel_base_url" in data


def test_ipad_email_mapping() -> None:
    out = subprocess.run(
        ["python3", "scripts/chat_registry.py", "add", "ipad@info.opendoors.fi", "work-h"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=True,
    )
    m = json.loads(out.stdout)
    assert m["TENANT"] == "ipad"
    assert m["GOOGLE_CHAT_ALLOWED_USERS"] == "ipad@info.opendoors.fi"
    assert m["GCP_PROJECT"] == "od-kansiot"
    assert m["SA_NAME"] == "hermes-chat-bot"
    assert m["PORT"] == "8081"
    assert m["HOST"] == "work-h"
    assert m["PLATFORM"] == "linux"
    assert m["CHAT_APP_DISPLAY_NAME"] == "hermes-chat"
    assert "/ipad/api/platforms/google_chat/events" in (
        f"{m['FUNNEL_BASE_URL']}{m['PATH_PREFIX']}/api/platforms/google_chat/events"
    )
    env_path = ROOT / "config" / "tenants" / "ipad.env"
    assert env_path.is_file()
    assert "CHAT_APP_DISPLAY_NAME=hermes-chat" in env_path.read_text(encoding="utf-8")


def test_natalia_mac_mapping() -> None:
    out = subprocess.run(
        ["python3", "scripts/chat_registry.py", "generate-all"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=True,
    )
    assert out.returncode == 0
    env_path = ROOT / "config" / "tenants" / "natalia.env"
    assert env_path.is_file()
    text = env_path.read_text(encoding="utf-8")
    assert "TENANT=natalia" in text
    assert "SA_NAME=hermes-chat-bot" in text
    assert "HOST=natalia-mac" in text
    assert "PLATFORM=darwin" in text
    assert "PORT=8642" in text
    assert "PATH_PREFIX=" in text or 'PATH_PREFIX=""' in text
    assert "FUNNEL_BASE_URL=https://tommis-macbook-pro.tail28712d.ts.net" in text
    host_users = subprocess.run(
        ["python3", "scripts/chat_registry.py", "host-users", "natalia-mac"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=True,
    )
    users = json.loads(host_users.stdout)
    assert len(users) == 1
    assert users[0]["TENANT"] == "natalia"
    events = f"{users[0]['FUNNEL_BASE_URL']}/api/platforms/google_chat/events"
    assert events == "https://tommis-macbook-pro.tail28712d.ts.net/api/platforms/google_chat/events"


def test_sync_workflow_exists() -> None:
    wf = (ROOT / ".github" / "workflows" / "sync-chat-users.yml").read_text(encoding="utf-8")
    host_wf = (ROOT / ".github" / "workflows" / "host-sync.yml").read_text(encoding="utf-8")
    assert "registry.json" in wf
    assert "workflow_dispatch" in wf
    assert "self-hosted" in host_wf
    assert "repair_mac_chat.sh" in host_wf or "sync_mac_from_registry.sh" in host_wf
    assert "ensure_chat_sa_artifact.sh" in wf or "hermes-chat-bot-sa.json" in wf
    assert 'SKIP_SA_KEY: "1"' not in wf


def test_hub_json_od_kansiot() -> None:
    out = subprocess.run(
        ["python3", "scripts/chat_registry.py", "hub-json"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=True,
    )
    h = json.loads(out.stdout)
    assert h["gcp_project"] == "od-kansiot"
    assert h["chat_app_display_name"] == "hermes-chat"
    assert "ipad@info.opendoors.fi" in h["allowed_users"]
    assert h["transport"] == "http"
    assert h["chat_inbound_host"] == "natalia-mac"
    assert h["primary_tenant"] == "natalia"
    assert h["chat_http_events_url"] == (
        "https://tommis-macbook-pro.tail28712d.ts.net/api/platforms/google_chat/events"
    )


def test_inbound_url_command() -> None:
    out = subprocess.run(
        ["python3", "scripts/chat_registry.py", "inbound-url"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=True,
    )
    assert out.stdout.strip() == (
        "https://tommis-macbook-pro.tail28712d.ts.net/api/platforms/google_chat/events"
    )


def test_ensure_tenant_sa_script_exists() -> None:
    path = ROOT / "scripts" / "ensure_tenant_sa.sh"
    assert path.is_file()
    text = path.read_text(encoding="utf-8")
    assert "Secret Manager" in text or "secrets versions access" in text
    assert "gh run download" in text
