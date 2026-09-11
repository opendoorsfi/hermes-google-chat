"""GitHub Actions must pin GCP_PROJECT from registry, not od-kansiot."""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_load_gcp_env_pins_registry_project(tmp_path: Path) -> None:
    envfile = tmp_path / "github.env"
    outfile = tmp_path / "github.out"
    envfile.write_text("GCP_PROJECT=od-kansiot\nCLOUDSDK_CORE_PROJECT=od-kansiot\n")
    result = subprocess.run(
        ["bash", "scripts/github_actions_load_gcp_env.sh"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=True,
        env={
            **os.environ,
            "GCP_PROJECT": "od-kansiot",
            "CLOUDSDK_CORE_PROJECT": "od-kansiot",
            "GITHUB_ENV": str(envfile),
            "GITHUB_OUTPUT": str(outfile),
        },
    )
    env_text = envfile.read_text(encoding="utf-8")
    out_text = outfile.read_text(encoding="utf-8")
    assert "OK: GCP_PROJECT=opendoors-hermes-chat" in result.stdout
    assert "GCP_PROJECT=opendoors-hermes-chat" in env_text
    assert "CLOUDSDK_CORE_PROJECT=opendoors-hermes-chat" in env_text
    assert "GCP_PROJECT=opendoors-hermes-chat" in out_text
    projects = [
        line.split("=", 1)[1]
        for line in env_text.splitlines()
        if line.startswith("GCP_PROJECT=")
    ]
    assert projects[-1] == "opendoors-hermes-chat"


def test_deploy_workflow_pins_registry_not_env_project() -> None:
    wf = (ROOT / ".github/workflows/deploy-cloudrun-gateway.yml").read_text(encoding="utf-8")
    action = (ROOT / ".github/actions/gcp-wif/action.yml").read_text(encoding="utf-8")
    assert "./.github/actions/gcp-wif" in wf
    assert "pipefail" in wf
    assert "project_id: ${{ env.GCP_PROJECT }}" not in wf
    assert "python3 scripts/chat_registry.py hub-json" in wf
    assert "steps.gcp.outputs.GCP_PROJECT" in action
    assert "project_id: ${{ env.GCP_PROJECT }}" not in action


def test_host_sync_skips_self_hosted_when_cloudrun() -> None:
    wf = (ROOT / ".github/workflows/host-sync.yml").read_text(encoding="utf-8")
    assert "need_host" in wf
    assert "chat_gateway_deploy" in wf
    assert "needs.gate.outputs.need_host" in wf


def test_setup_gcp_retries_concurrent_iam() -> None:
    text = (ROOT / "infra/setup_gcp.sh").read_text(encoding="utf-8")
    assert "gcloud_iam_retry" in text
    assert "concurrent policy" in text


def test_inspect_does_not_steal_pubsub_messages() -> None:
    text = (ROOT / "scripts/inspect_chat_gcp.sh").read_text(encoding="utf-8")
    assert "subscriptions pull" not in text
    assert "Ei pullata" in text


def test_wif_workflows_use_composite() -> None:
    for name in (
        "deploy-cloudrun-gateway.yml",
        "pubsub-health-check.yml",
        "inspect-chat-gcp.yml",
        "send-chat-test.yml",
        "create-chat-app.yml",
        "sync-chat-users.yml",
    ):
        wf = (ROOT / ".github/workflows" / name).read_text(encoding="utf-8")
        assert "./.github/actions/gcp-wif" in wf, name
        assert "project_id: ${{ env.GCP_PROJECT }}" not in wf, name
