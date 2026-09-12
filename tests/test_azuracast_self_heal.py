"""AzuraCast sync self-heal (azuracast-sync/) tests."""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
AZ = ROOT / "azuracast-sync"


def test_azuracast_self_heal_script_exists() -> None:
    path = AZ / "scripts" / "self_heal_azuracast.sh"
    assert path.is_file()


def test_azuracast_workflows_exist() -> None:
    assert (ROOT / ".github/workflows/self-heal-azuracast.yml").is_file()
    assert (ROOT / ".github/workflows/azuracast-health-check.yml").is_file()


def test_azuracast_registry() -> None:
    import json

    reg = json.loads((AZ / "config" / "registry.json").read_text(encoding="utf-8"))
    assert reg["cloud_run_service"] == "azuracast-sync"
