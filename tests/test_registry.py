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
    assert "funnel_base_url" in data


def test_ipad_email_mapping() -> None:
    out = subprocess.run(
        ["python3", "scripts/chat_registry.py", "add", "ipad@info.opendoors.fi"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=True,
    )
    m = json.loads(out.stdout)
    assert m["TENANT"] == "ipad"
    assert m["GOOGLE_CHAT_ALLOWED_USERS"] == "ipad@info.opendoors.fi"
    assert m["GCP_PROJECT"] == "hermes-ipad"
    assert m["PORT"] == "8081"
    assert m["CHAT_APP_DISPLAY_NAME"] == "Hermes (Ipad)"
    assert "/ipad/api/platforms/google_chat/events" in (
        f"{m['FUNNEL_BASE_URL']}{m['PATH_PREFIX']}/api/platforms/google_chat/events"
    )
    env_path = ROOT / "config" / "tenants" / "ipad.env"
    assert env_path.is_file()
    assert 'CHAT_APP_DISPLAY_NAME="Hermes (Ipad)"' in env_path.read_text(encoding="utf-8")


def test_sync_workflow_exists() -> None:
    wf = (ROOT / ".github" / "workflows" / "sync-chat-users.yml").read_text(encoding="utf-8")
    assert "registry.json" in wf
    assert "workflow_dispatch" in wf
    assert "self-hosted" in wf
