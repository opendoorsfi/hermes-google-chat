"""Self-heal gateway script tests."""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_self_heal_script_exists() -> None:
    path = ROOT / "scripts" / "self_heal_gateway.sh"
    assert path.is_file()
    text = path.read_text(encoding="utf-8")
    assert "--apply" in text
    assert "deploy_pubsub_cloudrun.sh" in text


def test_self_heal_workflow_exists() -> None:
    path = ROOT / ".github" / "workflows" / "self-heal-gateway.yml"
    assert path.is_file()
    text = path.read_text(encoding="utf-8")
    assert "self_heal_gateway.sh" in text
    assert "schedule:" in text
