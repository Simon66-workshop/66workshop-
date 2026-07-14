#!/usr/bin/env python3
"""Read-only aggregate storage audit for TaskLight state directories."""

from __future__ import annotations

import argparse
import json
import os
import signal
import subprocess
import time
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def now() -> float:
    return time.time()


def iso(timestamp: float | None) -> str | None:
    if timestamp is None:
        return None
    return datetime.fromtimestamp(timestamp, timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def scan_files(directory: Path, *, decode_json: bool = False) -> dict[str, Any]:
    started = time.perf_counter()
    files = sorted(directory.glob("*.json")) if directory.exists() else []
    file_count = 0
    total_bytes = 0
    oldest = None
    newest = None
    recent = {"1d": 0, "7d": 0, "30d": 0}
    statuses: Counter[str] = Counter()
    current = now()
    decode_started = time.perf_counter()
    decode_errors = 0
    for path in files:
        try:
            stat = path.stat()
        except OSError:
            continue
        file_count += 1
        total_bytes += stat.st_size
        oldest = stat.st_mtime if oldest is None else min(oldest, stat.st_mtime)
        newest = stat.st_mtime if newest is None else max(newest, stat.st_mtime)
        age = max(0.0, current - stat.st_mtime)
        for label, seconds in (("1d", 86400), ("7d", 604800), ("30d", 2592000)):
            if age <= seconds:
                recent[label] += 1
        if decode_json:
            try:
                payload = json.loads(path.read_text(encoding="utf-8"))
                statuses[str(payload.get("status") or payload.get("effective_status") or "unknown")] += 1
            except (OSError, json.JSONDecodeError, TypeError):
                decode_errors += 1
                statuses["invalid_json"] += 1
    return {
        "file_count": file_count,
        "total_bytes": total_bytes,
        "oldest_at": iso(oldest),
        "newest_at": iso(newest),
        "recent_counts": recent,
        "status_counts": dict(sorted(statuses.items())),
        "scan_milliseconds": round((time.perf_counter() - started) * 1000, 3),
        "json_decode_milliseconds": round((time.perf_counter() - decode_started) * 1000, 3),
        "json_decode_errors": decode_errors,
    }


def file_stat(directory: Path, suffix: str | None = None) -> dict[str, Any]:
    started = time.perf_counter()
    candidates = sorted(directory.glob(f"*{suffix or ''}")) if directory.exists() else []
    total = 0
    count = 0
    oldest = None
    newest = None
    current = now()
    recent = {"1d": 0, "7d": 0, "30d": 0}
    for path in candidates:
        try:
            stat = path.stat()
        except OSError:
            continue
        count += 1
        total += stat.st_size
        oldest = stat.st_mtime if oldest is None else min(oldest, stat.st_mtime)
        newest = stat.st_mtime if newest is None else max(newest, stat.st_mtime)
        age = max(0.0, current - stat.st_mtime)
        for label, seconds in (("1d", 86400), ("7d", 604800), ("30d", 2592000)):
            if age <= seconds:
                recent[label] += 1
    return {
        "file_count": count,
        "total_bytes": total,
        "oldest_at": iso(oldest),
        "newest_at": iso(newest),
        "recent_counts": recent,
        "scan_milliseconds": round((time.perf_counter() - started) * 1000, 3),
    }


def tail_read(path: Path, max_bytes: int = 96 * 1024) -> dict[str, Any]:
    started = time.perf_counter()
    try:
        with path.open("rb") as handle:
            handle.seek(0, os.SEEK_END)
            size = handle.tell()
            handle.seek(max(0, size - max_bytes))
            data = handle.read()
        return {"file_bytes": size, "tail_bytes": len(data), "read_milliseconds": round((time.perf_counter() - started) * 1000, 3)}
    except OSError:
        return {"file_bytes": 0, "tail_bytes": 0, "read_milliseconds": round((time.perf_counter() - started) * 1000, 3), "status": "unreadable"}


def fallback_dashboard_timing(root: Path) -> dict[str, Any]:
    started = time.perf_counter()
    command = root / "tasklight"
    if not command.exists():
        return {"status": "not_available"}
    process = subprocess.Popen(
        [str(command), "list"],
        env={**os.environ, "TASKLIGHT_STATE_DIR": str(root)},
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    try:
        process.wait(timeout=10)
        return {"status": "ok" if process.returncode == 0 else "failed", "exit_code": process.returncode, "milliseconds": round((time.perf_counter() - started) * 1000, 3)}
    except subprocess.TimeoutExpired:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait()
        return {"status": "timeout", "milliseconds": round((time.perf_counter() - started) * 1000, 3)}


def audit(state_dir: Path, project_root: Path) -> dict[str, Any]:
    return {
        "schema_version": "m7.1",
        "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "mode": "read_only",
        "state_dir": "<tasklight-state-dir>",
        "directories": {
            "tasks": scan_files(state_dir / "tasks", decode_json=True),
            "turn_bindings": scan_files(state_dir / "turn_bindings", decode_json=True),
            "observations": scan_files(state_dir / "observations", decode_json=True),
            "ui_clients": scan_files(state_dir / "ui_clients", decode_json=True),
            "archive_tasks": file_stat(state_dir / "archive" / "tasks", suffix=".json"),
            "archive_bindings": file_stat(state_dir / "archive" / "turn_bindings", suffix=".json"),
        },
        "files": {
            "events": tail_read(state_dir / "events.jsonl"),
            "normalized_signals": tail_read(state_dir / "normalized_signals.jsonl"),
            "ui_event_flow": tail_read(state_dir / "ui_event_flow.jsonl"),
        },
        "fallback_dashboard": fallback_dashboard_timing(project_root),
        "safety": {
            "report_only": True,
            "applied": False,
            "active_files_touched": False,
            "auth_read": False,
            "raw_log_output": False,
        },
    }


def markdown(payload: dict[str, Any]) -> str:
    directories = payload["directories"]
    lines = [
        "# TaskLight State Volume Baseline",
        "",
        f"- Generated: `{payload['generated_at']}`",
        "- Mode: `read_only`",
        "- Real state was not changed.",
        "",
        "## Directory Summary",
        "",
        "| Directory | Files | Bytes | Last 1d | Last 7d | Last 30d | Decode errors | Scan ms |",
        "|---|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for name in ("tasks", "turn_bindings", "observations", "ui_clients"):
        item = directories[name]
        lines.append(
            f"| {name} | {item['file_count']} | {item['total_bytes']} | {item['recent_counts']['1d']} | {item['recent_counts']['7d']} | {item['recent_counts']['30d']} | {item.get('json_decode_errors', 0)} | {item['scan_milliseconds']} |"
        )
    lines += [
        "",
        "## File Tail Timing",
        "",
        "| File | Bytes | Tail bytes | Read ms |",
        "|---|---:|---:|---:|",
    ]
    for name, item in payload["files"].items():
        lines.append(f"| {name} | {item['file_bytes']} | {item['tail_bytes']} | {item['read_milliseconds']} |")
    lines += [
        "",
        "## Fallback Timing",
        "",
        f"- Status: `{payload['fallback_dashboard'].get('status', 'unknown')}`",
        f"- Milliseconds: `{payload['fallback_dashboard'].get('milliseconds', 'n/a')}`",
        "",
        "This is a baseline only. Maintenance remains dry-run/report-only unless a human explicitly invokes `--apply`.",
    ]
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--state-dir", default=os.environ.get("TASKLIGHT_STATE_DIR", str(Path.home() / ".66tasklight")))
    parser.add_argument("--project-root", default=str(Path(__file__).resolve().parents[1]))
    parser.add_argument("--output-json", required=True)
    parser.add_argument("--output-md", required=True)
    args = parser.parse_args()
    payload = audit(Path(args.state_dir).expanduser(), Path(args.project_root).expanduser())
    Path(args.output_json).write_text(json.dumps(payload, ensure_ascii=True, indent=2) + "\n", encoding="utf-8")
    Path(args.output_md).write_text(markdown(payload), encoding="utf-8")
    print(f"storage_audit_status=ok files={sum(item['file_count'] for item in payload['directories'].values())}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
