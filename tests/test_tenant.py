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
    # Hermes: API server oletuksena pois + avain pakollinen → ilman näitä Funnel antaa 502
    assert "API_SERVER_ENABLED=true" in out.stdout
    assert any(
        line.startswith("API_SERVER_KEY=") and len(line) > len("API_SERVER_KEY=") + 16
        for line in out.stdout.splitlines()
    )


def test_mac_bootstrap_enables_api_server() -> None:
    text = (ROOT / "scripts" / "bootstrap_hermes_mac.sh").read_text(encoding="utf-8")
    assert "API_SERVER_ENABLED=true" in text
    assert "API_SERVER_KEY=" in text
    assert "GOOGLE_CHAT_HTTP_EVENTS_SERVICE_ACCOUNT_EMAIL=chat@system.gserviceaccount.com" in text
    assert "ensure_mac_gateway_running.sh" in text
    host_env = (ROOT / "scripts" / "install_hermes_host.sh").read_text(encoding="utf-8")
    assert "API_SERVER_ENABLED=true" in host_env


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


def test_github_workflows_exist() -> None:
    ci = (ROOT / ".github" / "workflows" / "ci.yml").read_text(encoding="utf-8")
    assert "make validate" in ci

    tenant = (ROOT / ".github" / "workflows" / "tenant-gcp.yml").read_text(encoding="utf-8")
    assert "workflow_dispatch" in tenant
    assert "infra/setup_tenant_gcp.sh" in tenant
    assert "secrets.GCP_WIF_PROVIDER" in tenant
    assert "secrets.GCP_DEPLOY_SA_EMAIL" in tenant
    assert 'SKIP_SA_KEY: "1"' in tenant


def test_setup_tenant_gcp_rejects_placeholder_funnel() -> None:
    proc = subprocess.run(
        ["bash", "infra/setup_tenant_gcp.sh"],
        cwd=ROOT,
        env={"PATH": "/usr/bin:/bin", "TENANT": "alice"},
        capture_output=True,
        text=True,
    )
    assert proc.returncode == 1
    assert "placeholder" in proc.stdout


def test_no_monorepo_secrets_target() -> None:
    for script in (ROOT / "scripts").glob("*.sh"):
        text = script.read_text(encoding="utf-8")
        assert "--repo opendoorsfi/moderate" not in text, f"{script.name} viittaa monorepoon"
