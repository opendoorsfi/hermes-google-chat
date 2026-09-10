"""Validate hermes-google-chat config examples (no secrets in repo)."""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_env_example_has_required_keys() -> None:
    text = (ROOT / "config" / "hermes.env.example").read_text(encoding="utf-8")
    required = (
        "GOOGLE_CHAT_PROJECT_ID",
        "HERMES_CHAT_TRANSPORT",
        "GOOGLE_CHAT_HTTP_EVENTS_URL",
        "GOOGLE_CHAT_ALLOWED_USERS",
    )
    for key in required:
        assert key in text, f"missing {key} in hermes.env.example"


def test_no_real_secrets_in_repo() -> None:
    forbidden_patterns = ("OPENROUTER_API_KEY=sk-", "BEGIN PRIVATE KEY")
    skip_dirs = {".git", "tests", ".pytest_cache"}
    for path in ROOT.rglob("*"):
        if path.is_dir() or any(p in skip_dirs for p in path.parts):
            continue
        if path.suffix in {".pyc", ".png", ".jpg"}:
            continue
        if path.stat().st_size > 500_000:
            continue
        try:
            content = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        for pat in forbidden_patterns:
            assert pat not in content, f"possible secret in {path}"


def test_profile_opendoors_exists() -> None:
    profile = ROOT / "profiles" / "opendoors" / "config.yaml"
    assert profile.is_file()
    assert "Open Doors" in profile.read_text(encoding="utf-8")


def test_dockerfile_installs_pubsub() -> None:
    dockerfile = (ROOT / "deploy" / "Dockerfile").read_text(encoding="utf-8")
    assert "google-cloud-pubsub" in dockerfile
    assert "uv pip install" in dockerfile


def test_deploy_http_transport() -> None:
    deploy = (ROOT / "deploy" / "cloudrun" / "deploy.sh").read_text(encoding="utf-8")
    assert "--no-invoker-iam-check" in deploy
    assert "HERMES_CHAT_TRANSPORT" in deploy
    assert 'HERMES_CHAT_TRANSPORT:-http' in deploy
    assert "/api/platforms/google_chat/events" in deploy


def test_setup_defaults_to_http() -> None:
    setup = (ROOT / "infra" / "setup_gcp.sh").read_text(encoding="utf-8")
    assert 'HERMES_CHAT_TRANSPORT="${HERMES_CHAT_TRANSPORT:-http}"' in setup
    assert "chat-api-push@system.gserviceaccount.com" in setup
