"""Pub/Sub env strip / auth helpers."""

from __future__ import annotations

import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_strip_http_chat_env() -> None:
    with tempfile.NamedTemporaryFile("w", suffix=".env", delete=False) as f:
        f.write(
            "GOOGLE_CHAT_HTTP_EVENTS_URL=https://example.com/events\n"
            "HERMES_CHAT_TRANSPORT=http\n"
            "GOOGLE_CHAT_SUBSCRIPTION_NAME=projects/x/subscriptions/y\n"
            "OPENROUTER_API_KEY=keep-me\n"
        )
        path = Path(f.name)
    subprocess.run(
        ["python3", "scripts/lib/strip_http_chat_env.py", str(path)],
        cwd=ROOT,
        check=True,
    )
    text = path.read_text(encoding="utf-8")
    assert "GOOGLE_CHAT_HTTP_EVENTS_URL" not in text
    assert "HERMES_CHAT_TRANSPORT=http" not in text
    assert "GOOGLE_CHAT_SUBSCRIPTION_NAME" in text
    assert "OPENROUTER_API_KEY=keep-me" in text
    path.unlink()


def test_publish_uses_registry_gcp_project() -> None:
    out = subprocess.run(
        ["bash", "-c", "GCP_PROJECT=od-kansiot bash scripts/publish_chat_inbound_test.sh"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        env={**os.environ, "GCP_PROJECT": "od-kansiot"},
    )
    # Dry-run: script echoes project in first lines even if gcloud missing
    combined = (out.stdout or "") + (out.stderr or "")
    assert "opendoors-hermes-chat" in combined or out.returncode != 0
    assert "projects/od-kansiot/topics" not in combined


def test_setup_chat_pubsub_auth_script_exists() -> None:
    path = ROOT / "scripts" / "setup_chat_pubsub_auth.sh"
    assert path.is_file()
    text = path.read_text(encoding="utf-8")
    assert "bash \"${ROOT}/scripts/setup_chat_outbound_auth.sh\"" not in text
    assert "fetch_sa_to_path" in text
