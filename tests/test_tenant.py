"""Tenant manifest and script tests."""

from __future__ import annotations

import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_tenant_examples_exist() -> None:
    for name in ("alice", "bob", "team"):
        path = ROOT / "config" / "tenants" / f"{name}.env.example"
        assert path.is_file(), f"missing {path}"
        text = path.read_text(encoding="utf-8")
        for key in ("TENANT=", "GCP_PROJECT=", "PORT=", "PATH_PREFIX=", "FUNNEL_BASE_URL="):
            assert key in text


def test_print_tenant_env_alice() -> None:
    out = subprocess.run(
        ["bash", "scripts/print_tenant_env.sh", "alice"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=True,
    )
    assert "GOOGLE_CHAT_HTTP_EVENTS_URL=" in out.stdout
    assert "/alice/api/platforms/google_chat/events" in out.stdout
    assert "API_SERVER_PORT=8081" in out.stdout


def test_setup_tenant_gcp_script_exists() -> None:
    assert (ROOT / "infra" / "setup_tenant_gcp.sh").is_file()
    text = (ROOT / "infra" / "setup_tenant_gcp.sh").read_text(encoding="utf-8")
    assert "chat.googleapis.com" in text
    assert "Pub/Sub" not in text or "HTTP" in text


def test_caddy_template_has_placeholder() -> None:
    t = (ROOT / "deploy" / "host" / "Caddyfile.template").read_text(encoding="utf-8")
    assert "{{TENANT_BLOCKS}}" in t


def test_systemd_units_exist() -> None:
    assert (ROOT / "deploy" / "systemd" / "hermes-gateway@.service").is_file()
    assert (ROOT / "deploy" / "systemd" / "caddy-hermes.service").is_file()
