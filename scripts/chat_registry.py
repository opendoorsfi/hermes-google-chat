#!/usr/bin/env python3
"""Tenant registry: email → manifest. Source of truth: config/tenants/registry.json."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
REGISTRY_PATH = ROOT / "config" / "tenants" / "registry.json"
TENANTS_DIR = ROOT / "config" / "tenants"
BASE_PORT = 8081
DEFAULT_GCP_PROJECT = "od-kansiot"


def load_registry() -> dict:
    data = json.loads(REGISTRY_PATH.read_text(encoding="utf-8"))
    if "users" not in data:
        raise ValueError("registry.json: missing 'users'")
    return data


def normalize_user(entry: str | dict[str, Any]) -> tuple[str, str | None]:
    if isinstance(entry, str):
        email = entry.strip().lower()
        return email, None
    if isinstance(entry, dict):
        email = str(entry.get("email", "")).strip().lower()
        host = entry.get("host")
        host_id = str(host).strip() if host else None
        return email, host_id
    raise ValueError(f"registry.json: invalid user entry: {entry!r}")


def resolve_host(reg: dict, host_id: str | None) -> dict[str, Any]:
    default_funnel = reg.get("funnel_base_url", "").strip()
    hosts = reg.get("hosts") or {}
    if host_id and host_id in hosts:
        cfg = hosts[host_id]
        return {
            "host_id": host_id,
            "platform": cfg.get("platform", "linux"),
            "funnel_base_url": str(cfg.get("funnel_base_url", default_funnel)).strip(),
            "path_prefix_mode": cfg.get("path_prefix_mode", "tenant"),
            "gateway_port": cfg.get("gateway_port"),
            "bootstrap": cfg.get("bootstrap", ""),
        }
    return {
        "host_id": host_id or "",
        "platform": "linux",
        "funnel_base_url": default_funnel,
        "path_prefix_mode": "tenant",
        "gateway_port": None,
        "bootstrap": "scripts/bootstrap_hermes_host.sh",
    }


def email_to_tenant_id(email: str) -> str:
    local = email.split("@", 1)[0].lower()
    tid = re.sub(r"[^a-z0-9]+", "-", local).strip("-")
    if not tid or not re.match(r"^[a-z0-9][a-z0-9-]{0,30}$", tid):
        raise ValueError(f"invalid tenant id from email: {email}")
    return tid


def display_name(tenant_id: str) -> str:
    parts = tenant_id.replace("-", " ").split()
    label = " ".join(p[:1].upper() + p[1:] for p in parts if p)
    return f"Hermes ({label})"


def allocate_port(index: int) -> int:
    return BASE_PORT + index


def path_prefix(tenant_id: str, path_prefix_mode: str) -> str:
    if path_prefix_mode == "root":
        return ""
    return f"/{tenant_id}"


def sa_name_for_tenant(reg: dict, tenant_id: str) -> str:
    shared = reg.get("shared_chat_sa", "").strip()
    if shared:
        return shared
    return f"hermes-chat-{tenant_id}"


def tenant_manifest(
    email: str,
    index: int,
    host_cfg: dict[str, Any],
    gcp_project: str,
    reg: dict | None = None,
) -> dict[str, str]:
    reg = reg or load_registry()
    tid = email_to_tenant_id(email)
    prefix = path_prefix(tid, host_cfg.get("path_prefix_mode", "tenant"))
    gateway_port = host_cfg.get("gateway_port")
    port = str(gateway_port if gateway_port is not None else allocate_port(index))
    platform = host_cfg.get("platform", "linux")
    linux_user = tid if platform == "darwin" else f"hermes-{tid}"
    manifest: dict[str, str] = {
        "TENANT": tid,
        "GCP_PROJECT": gcp_project,
        "SA_NAME": sa_name_for_tenant(reg, tid),
        "LINUX_USER": linux_user,
        "PORT": port,
        "PATH_PREFIX": prefix,
        "ROLE": "personal",
        "CHAT_APP_DISPLAY_NAME": registry_chat_app_name(reg),
        "GOOGLE_CHAT_ALLOWED_USERS": email.strip().lower(),
        "FUNNEL_BASE_URL": str(host_cfg.get("funnel_base_url", "")).rstrip("/"),
        "HOST": str(host_cfg.get("host_id", "")),
        "PLATFORM": platform,
        "CHAT_TRANSPORT": str(reg.get("default_chat_transport", "pubsub")).strip(),
        "CHAT_PUBSUB_TOPIC": str(reg.get("chat_pubsub_topic", "hermes-chat-events")).strip(),
        "CHAT_PUBSUB_SUB": str(reg.get("chat_pubsub_subscription", "hermes-chat-events-sub")).strip(),
    }
    return manifest


def env_value(value: str) -> str:
    """Shell-safe .env value (spaces, parentheses, etc.)."""
    if re.search(r'[\s#"$`!()\\]', value):
        escaped = value.replace("\\", "\\\\").replace('"', '\\"')
        return f'"{escaped}"'
    return value


def write_env(manifest: dict[str, str]) -> Path:
    TENANTS_DIR.mkdir(parents=True, exist_ok=True)
    path = TENANTS_DIR / f"{manifest['TENANT']}.env"
    lines = [f"{k}={env_value(v)}" for k, v in manifest.items()]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return path


def iter_user_entries(reg: dict | None = None) -> list[tuple[str, str | None]]:
    reg = reg or load_registry()
    entries: list[tuple[str, str | None]] = []
    for entry in reg["users"]:
        email, host_id = normalize_user(entry)
        if email:
            entries.append((email, host_id))
    return entries


def generate_all() -> list[dict[str, str]]:
    reg = load_registry()
    gcp_project = registry_gcp_project(reg)
    manifests = []
    for i, (email, host_id) in enumerate(iter_user_entries(reg)):
        host_cfg = resolve_host(reg, host_id)
        m = tenant_manifest(email, i, host_cfg, gcp_project, reg)
        write_env(m)
        manifests.append(m)
    return manifests


def list_tenant_ids() -> list[str]:
    return [m["TENANT"] for m in generate_all()]


def registry_gcp_project(reg: dict | None = None) -> str:
    reg = reg or load_registry()
    return str(reg.get("gcp_project", DEFAULT_GCP_PROJECT)).strip() or DEFAULT_GCP_PROJECT


def registry_deploy_sa(reg: dict | None = None) -> str:
    reg = reg or load_registry()
    explicit = str(reg.get("github_deploy_sa", "")).strip()
    if explicit:
        return explicit
    return f"github-hermes-deploy@{registry_gcp_project(reg)}.iam.gserviceaccount.com"


def registry_wif_provider(reg: dict | None = None) -> str:
    reg = reg or load_registry()
    return str(reg.get("wif_provider", "")).strip()


def set_gcp_wif(wif: str, deploy_sa: str, *, bootstrap_requested: bool = False) -> dict:
    """Persist WIF + deploy SA after GCP bootstrap (GitHub Actions commits this)."""
    reg = load_registry()
    reg["wif_provider"] = wif.strip()
    reg["github_deploy_sa"] = deploy_sa.strip()
    reg["bootstrap_requested"] = bootstrap_requested
    reg["sync_version"] = int(reg.get("sync_version", 0)) + 1
    REGISTRY_PATH.write_text(json.dumps(reg, indent=2) + "\n", encoding="utf-8")
    return reg


def chat_transport(reg: dict | None = None) -> str:
    reg = reg or load_registry()
    return str(reg.get("default_chat_transport", "pubsub")).strip() or "pubsub"


def all_allowed_users(reg: dict | None = None) -> list[str]:
    reg = reg or load_registry()
    users = [email for email, _ in iter_user_entries(reg)]
    extras = [
        str(e).strip().lower()
        for e in reg.get("extra_allowed_users", [])
        if str(e).strip()
    ]
    for email in extras:
        if email not in users:
            users.append(email)
    return users


def registry_chat_app_name(reg: dict | None = None) -> str:
    reg = reg or load_registry()
    override = str(reg.get("chat_app_display_name", "")).strip()
    if override:
        return override
    users = all_allowed_users(reg)
    if not users:
        return "Hermes"
    gcp_project = registry_gcp_project(reg)
    host_cfg = resolve_host(reg, iter_user_entries(reg)[0][1])
    return tenant_manifest(users[0], 0, host_cfg, gcp_project, reg)["CHAT_APP_DISPLAY_NAME"]


def gateway_host_id(reg: dict | None = None) -> str:
    """Host that runs the shared Hermes gateway (Pub/Sub pull — one process per Chat app)."""
    reg = reg or load_registry()
    explicit = str(reg.get("chat_gateway_host", "")).strip()
    if explicit:
        return explicit
    entries = iter_user_entries(reg)
    if entries:
        return str(entries[0][1] or "").strip()
    return ""


def inbound_host_id(reg: dict | None = None) -> str:
    """Host that receives Google Chat HTTP callbacks (one URL per Chat app)."""
    reg = reg or load_registry()
    if chat_transport(reg) == "pubsub":
        return gateway_host_id(reg)
    explicit = str(reg.get("chat_inbound_host", "")).strip()
    if explicit:
        return explicit
    return gateway_host_id(reg)


def primary_manifest(reg: dict | None = None) -> dict[str, str]:
    """Manifest for the primary Chat gateway (Pub/Sub host or HTTP inbound host)."""
    reg = reg or load_registry()
    gcp_project = registry_gcp_project(reg)
    host_id = inbound_host_id(reg)
    entries = iter_user_entries(reg)
    if not entries:
        raise ValueError("registry.json: no users")
    for i, (email, entry_host) in enumerate(entries):
        if host_id and entry_host == host_id:
            host_cfg = resolve_host(reg, host_id)
            return tenant_manifest(email, i, host_cfg, gcp_project, reg)
    email, entry_host = entries[0]
    host_cfg = resolve_host(reg, entry_host or host_id)
    return tenant_manifest(email, 0, host_cfg, gcp_project, reg)


def inbound_manifest(reg: dict | None = None) -> dict[str, str]:
    """Manifest for the host configured as Chat HTTP inbound (Console URL)."""
    return primary_manifest(reg)


def inbound_events_url(reg: dict | None = None) -> str:
    return chat_events_url(inbound_manifest(reg))


def hub_meta() -> dict[str, str]:
    reg = load_registry()
    users = all_allowed_users(reg)
    transport = chat_transport(reg)
    primary_m = primary_manifest(reg)
    primary = primary_m["TENANT"]
    project = registry_gcp_project(reg)
    events_url = chat_events_url(primary_m)
    topic = str(reg.get("chat_pubsub_topic", "hermes-chat-events")).strip()
    sub = str(reg.get("chat_pubsub_subscription", "hermes-chat-events-sub")).strip()
    return {
        "transport": transport,
        "primary_tenant": primary,
        "chat_gateway_host": gateway_host_id(reg),
        "chat_inbound_host": inbound_host_id(reg),
        "chat_http_events_url": events_url,
        "gcp_project": project,
        "github_deploy_sa": registry_deploy_sa(reg),
        "wif_provider": registry_wif_provider(reg),
        "chat_app_display_name": registry_chat_app_name(reg),
        "allowed_users": ", ".join(users),
        "pubsub_topic": topic,
        "pubsub_sub": sub,
        "pubsub_subscription_full": f"projects/{project}/subscriptions/{sub}",
        "console_url": (
            f"https://console.cloud.google.com/apis/api/chat.googleapis.com/hangouts-chat?project={project}"
        ),
    }


def add_user(email: str, host: str | None = None) -> dict[str, str]:
    reg = load_registry()
    email = email.strip().lower()
    entries = iter_user_entries(reg)
    emails = [e for e, _ in entries]
    if email not in emails:
        if host:
            reg.setdefault("users", []).append({"email": email, "host": host})
        else:
            reg.setdefault("users", []).append(email)
        REGISTRY_PATH.write_text(json.dumps(reg, indent=2) + "\n", encoding="utf-8")
        entries = iter_user_entries(reg)
    idx = next(i for i, (e, _) in enumerate(entries) if e == email)
    host_id = host or entries[idx][1]
    host_cfg = resolve_host(reg, host_id)
    gcp_project = registry_gcp_project(reg)
    m = tenant_manifest(email, idx, host_cfg, gcp_project, reg)
    write_env(m)
    return m


def chat_events_url(manifest: dict[str, str]) -> str:
    base = manifest["FUNNEL_BASE_URL"].rstrip("/")
    prefix = manifest.get("PATH_PREFIX", "").strip("/")
    if prefix:
        return f"{base}/{prefix}/api/platforms/google_chat/events"
    return f"{base}/api/platforms/google_chat/events"


def main() -> int:
    if len(sys.argv) < 2:
        print(
            "Usage: chat_registry.py generate-all|list-ids|add EMAIL [HOST]|matrix-json|hub-json|github-env|inbound-url|summary|host-users HOST",
            file=sys.stderr,
        )
        return 1
    cmd = sys.argv[1]
    if cmd == "generate-all":
        generate_all()
        return 0
    if cmd == "list-ids":
        for tid in list_tenant_ids():
            print(tid)
        return 0
    if cmd == "add":
        if len(sys.argv) < 3:
            print("Usage: chat_registry.py add EMAIL [HOST]", file=sys.stderr)
            return 1
        host = sys.argv[3] if len(sys.argv) > 3 else None
        m = add_user(sys.argv[2], host)
        print(json.dumps(m, indent=2))
        return 0
    if cmd == "hub-json":
        print(json.dumps(hub_meta()))
        return 0
    if cmd == "github-env":
        meta = hub_meta()
        print(f"GCP_PROJECT={meta['gcp_project']}")
        print(f"GCP_DEPLOY_SA_EMAIL={meta['github_deploy_sa']}")
        if meta.get("wif_provider"):
            print(f"GCP_WIF_PROVIDER={meta['wif_provider']}")
        return 0
    if cmd == "set-gcp-wif":
        if len(sys.argv) < 4:
            print("Usage: chat_registry.py set-gcp-wif WIF_PROVIDER DEPLOY_SA_EMAIL", file=sys.stderr)
            return 1
        reg = set_gcp_wif(sys.argv[2], sys.argv[3], bootstrap_requested=False)
        print(json.dumps({"wif_provider": reg["wif_provider"], "github_deploy_sa": reg["github_deploy_sa"]}))
        return 0
    if cmd == "matrix-json":
        ids = list_tenant_ids()
        print(json.dumps({"tenant": ids}))
        return 0
    if cmd == "host-users":
        if len(sys.argv) < 3:
            print("Usage: chat_registry.py host-users HOST_ID", file=sys.stderr)
            return 1
        host_id = sys.argv[2]
        reg = load_registry()
        gcp_project = registry_gcp_project(reg)
        users = []
        for i, (email, entry_host) in enumerate(iter_user_entries(reg)):
            if entry_host == host_id:
                host_cfg = resolve_host(reg, host_id)
                users.append(tenant_manifest(email, i, host_cfg, gcp_project, reg))
        print(json.dumps(users, indent=2))
        return 0
    if cmd == "inbound-url":
        print(inbound_events_url())
        return 0
    if cmd == "summary":
        reg = load_registry()
        gcp_project = registry_gcp_project(reg)
        transport = chat_transport(reg)
        meta = hub_meta()
        if transport == "pubsub":
            print(f"**Chat transport:** Pub/Sub → `{meta['pubsub_subscription_full']}`")
            print(f"**Gateway host:** `{gateway_host_id(reg) or 'default'}` (tenant `{meta['primary_tenant']}`)")
        else:
            inbound_url = inbound_events_url(reg)
            print(f"**Chat inbound (Console HTTP URL):** `{inbound_url}`")
            print(f"**Inbound host:** `{inbound_host_id(reg) or 'default'}`")
        print()
        allowed = ", ".join(all_allowed_users(reg))
        for i, (email, host_id) in enumerate(iter_user_entries(reg)):
            host_cfg = resolve_host(reg, host_id)
            m = tenant_manifest(email, i, host_cfg, gcp_project, reg)
            print(f"## {m['CHAT_APP_DISPLAY_NAME']} (`{m['TENANT']}`)")
            print(f"- Email: `{m['GOOGLE_CHAT_ALLOWED_USERS']}`")
            print(f"- Host: `{m.get('HOST', '') or 'default'}` ({m.get('PLATFORM', 'linux')})")
            print(f"- GCP: `{m['GCP_PROJECT']}`")
            if transport == "pubsub":
                if host_id == gateway_host_id(reg):
                    print(f"- Gateway: **tämä host** (Pub/Sub pull, allowed: `{allowed}`)")
                else:
                    print("- Gateway: ei tällä hostilla (yksi `hermes gateway` per Chat-app)")
            else:
                events = chat_events_url(m)
                print(f"- Chat HTTP URL: `{events}`")
            bootstrap = host_cfg.get("bootstrap") or ""
            if bootstrap:
                print(f"- Host bootstrap: `{bootstrap} {m['GOOGLE_CHAT_ALLOWED_USERS']}`")
            print(f"- Chatissa: Find apps → **{m['CHAT_APP_DISPLAY_NAME']}** → Message → `Hei`")
            print()
        return 0
    print(f"unknown command: {cmd}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
