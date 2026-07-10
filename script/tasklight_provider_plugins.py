#!/usr/bin/env python3
"""Run explicitly enabled local usage-provider plugins without a shell."""

from __future__ import annotations

import argparse
import json
import os
import stat
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


DEFAULT_STATE_DIR = Path.home() / ".66tasklight"
ALLOWED_HEALTH = {"ok", "warning", "disabled", "unavailable"}


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def state_dir() -> Path:
    return Path(os.environ.get("TASKLIGHT_STATE_DIR", str(DEFAULT_STATE_DIR))).expanduser()


def provider_root(root: Path) -> Path:
    return Path(os.environ.get("TASKLIGHT_PROVIDER_PLUGIN_DIR", str(root / "providers"))).expanduser()


def atomic_write(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(payload, ensure_ascii=True, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    os.replace(tmp, path)


def validate_manifest(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError("manifest must be an object")
    plugin_id = str(payload.get("id") or "")
    if not plugin_id or not all(char.isalnum() or char in "_-" for char in plugin_id):
        raise ValueError("provider id must contain only letters, digits, underscore, or dash")
    executable = Path(str(payload.get("executable") or "")).expanduser()
    if not executable.is_absolute() or not executable.is_file() or not os.access(executable, os.X_OK):
        raise ValueError("provider executable must be an absolute executable file")
    details = executable.stat()
    if details.st_uid != os.getuid() or details.st_mode & stat.S_IWOTH:
        raise ValueError("provider executable must be user-owned and not world-writable")
    payload["id"] = plugin_id
    payload["executable"] = str(executable.resolve())
    return payload


def normalize_snapshot(manifest: dict[str, Any], raw: dict[str, Any]) -> dict[str, Any]:
    health = str(raw.get("health") or "unavailable")
    if health not in ALLOWED_HEALTH:
        health = "unavailable"
    remaining = raw.get("remaining_percent")
    if not isinstance(remaining, int) or not 0 <= remaining <= 100:
        remaining = None
    return {
        "id": manifest["id"],
        "display_name": str(manifest.get("display_name") or manifest["id"])[:80],
        "health": health,
        "quota_text": str(raw.get("quota_text") or "Q?")[:32],
        "remaining_percent": remaining,
        "is_low_quota": bool(raw.get("is_low_quota", remaining is not None and remaining < 20)),
        "updated_at": str(raw.get("updated_at") or now_iso()),
        "diagnostic_only": True,
        "source_label": str(raw.get("source_label") or f"plugin:{manifest['id']}")[:120],
        "freshness_label": str(raw.get("freshness_label") or "unknown freshness")[:80],
        "conflict_label": None if raw.get("conflict_label") is None else str(raw.get("conflict_label"))[:160],
    }


def unavailable_snapshot(manifest: dict[str, Any], reason: str) -> dict[str, Any]:
    return normalize_snapshot(manifest, {
        "health": "unavailable",
        "quota_text": "Q?",
        "source_label": f"plugin:{manifest['id']}",
        "freshness_label": "probe unavailable",
        "conflict_label": reason[:160],
    })


def run_once(root: Path | None = None) -> dict[str, Any]:
    root = root or state_dir()
    providers = provider_root(root)
    manifests = providers / "manifests"
    snapshots = providers / "snapshots"
    manifest_paths = sorted(manifests.glob("*.json")) if manifests.exists() else []
    if not manifest_paths:
        return {"schema_version": "0.1", "updated_at": now_iso(), "provider_count": 0, "providers": []}
    snapshots.mkdir(parents=True, exist_ok=True)
    results: list[dict[str, Any]] = []
    for path in manifest_paths:
        try:
            manifest = validate_manifest(path)
        except (OSError, ValueError, json.JSONDecodeError):
            continue
        if not bool(manifest.get("enabled", False)):
            snapshot = normalize_snapshot(manifest, {"health": "disabled", "quota_text": "disabled", "freshness_label": "disabled"})
        else:
            timeout = min(10.0, max(0.2, float(manifest.get("timeout_seconds") or 2)))
            try:
                completed = subprocess.run(
                    [manifest["executable"]],
                    text=True,
                    capture_output=True,
                    timeout=timeout,
                    check=False,
                    env={"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": str(Path.home())},
                )
                if completed.returncode != 0:
                    raise RuntimeError(f"exit {completed.returncode}")
                raw = json.loads(completed.stdout)
                if not isinstance(raw, dict):
                    raise ValueError("provider output must be a JSON object")
                snapshot = normalize_snapshot(manifest, raw)
            except (OSError, RuntimeError, ValueError, json.JSONDecodeError, subprocess.TimeoutExpired) as exc:
                snapshot = unavailable_snapshot(manifest, str(exc))
        atomic_write(snapshots / f"{manifest['id']}.json", snapshot)
        results.append(snapshot)
    health = {"schema_version": "0.1", "updated_at": now_iso(), "provider_count": len(results), "providers": results}
    atomic_write(providers / "health.json", health)
    return health


def main() -> int:
    parser = argparse.ArgumentParser(description="Run enabled TaskLight provider plugins")
    parser.add_argument("--once", action="store_true", required=True)
    args = parser.parse_args()
    print(json.dumps(run_once(), ensure_ascii=True, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
