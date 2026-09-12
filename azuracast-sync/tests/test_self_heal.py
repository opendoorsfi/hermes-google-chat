"""Self-heal AzuraCast sync script tests."""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_self_heal_script_exists() -> None:
    path = ROOT / "scripts" / "self_heal_azuracast.sh"
    assert path.is_file()
    text = path.read_text(encoding="utf-8")
    assert "--apply" in text
    assert "api/status" in text


def test_registry_has_urls() -> None:
    import json

    reg = json.loads((ROOT / "config" / "registry.json").read_text(encoding="utf-8"))
    assert reg["gcp_project"] == "od-azuracast-sync"
    assert "radio.opendoors.fi" in reg["azuracast_base_url"]
    assert "azuracast-sync" in reg["cloud_run_url"]


def test_registry_json_valid() -> None:
    import json

    json.loads((ROOT / "config" / "registry.json").read_text(encoding="utf-8"))
