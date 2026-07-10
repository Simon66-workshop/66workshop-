#!/usr/bin/env python3
"""Create an allowlisted, sanitized TaskLight support bundle."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import zipfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


DEFAULT_STATE_DIR = Path.home() / ".66tasklight"
SAFE_FILES = (
    "state_projector_health.json",
    "hook_bridge_health.json",
    "appserver_thread_watcher_health.json",
    "anomaly_summary.json",
    "providers/health.json",
    "workspace_coverage/run_status.json",
)
SENSITIVE_KEYS = ("token", "secret", "auth", "prompt", "message", "evidence", "command", "cwd", "path", "workspace", "thread_id", "turn_id", "task_id")


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def state_dir() -> Path:
    return Path(os.environ.get("TASKLIGHT_STATE_DIR", str(DEFAULT_STATE_DIR))).expanduser()


def pseudonym(value: Any) -> str:
    return "sha256:" + hashlib.sha256(str(value).encode()).hexdigest()[:12]


def sanitize(value: Any, key: str = "") -> Any:
    lowered = key.lower()
    if any(marker in lowered for marker in SENSITIVE_KEYS):
        if value is None:
            return None
        return pseudonym(value)
    if isinstance(value, dict):
        return {str(k): sanitize(v, str(k)) for k, v in value.items()}
    if isinstance(value, list):
        return [sanitize(item, key) for item in value[:50]]
    if isinstance(value, str):
        return value[:300]
    return value


def load_safe(root: Path, relative: str) -> dict[str, Any] | None:
    try:
        payload = json.loads((root / relative).read_text(encoding="utf-8"))
    except (FileNotFoundError, OSError, json.JSONDecodeError):
        return None
    return sanitize(payload) if isinstance(payload, dict) else None


def create_bundle(output: Path, root: Path | None = None) -> Path:
    root = root or state_dir()
    output.parent.mkdir(parents=True, exist_ok=True)
    files: dict[str, dict[str, Any]] = {}
    for relative in SAFE_FILES:
        payload = load_safe(root, relative)
        if payload is not None:
            files[f"health/{relative.replace('/', '_')}"] = payload
    manifest = {
        "schema_version": "0.1",
        "generated_at": now_iso(),
        "privacy": "sanitized_allowlist_only",
        "raw_logs_included": False,
        "platform": platform.system(),
        "platform_release": platform.release(),
        "machine": platform.machine(),
        "included_files": sorted(files),
    }
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("manifest.json", json.dumps(manifest, ensure_ascii=True, sort_keys=True, indent=2) + "\n")
        for name, payload in files.items():
            archive.writestr(name, json.dumps(payload, ensure_ascii=True, sort_keys=True, indent=2) + "\n")
    return output


def main() -> int:
    parser = argparse.ArgumentParser(description="Create a sanitized TaskLight diagnostic bundle")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    output = create_bundle(Path(args.output).expanduser())
    print(json.dumps({"status": "ok", "output": str(output), "raw_logs_included": False}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
