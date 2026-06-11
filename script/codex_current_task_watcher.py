#!/usr/bin/env python3
"""Detached lease watcher for the current Codex thread binding.

The watcher fuses local Codex signals and only refreshes managed heartbeat when
the fusion decision says the signal is authoritative enough.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path


def parse_ts(value: object) -> datetime | None:
    if not value:
        return None
    normalized = str(value).replace("Z", "+00:00")
    try:
        return datetime.fromisoformat(normalized)
    except ValueError:
        return None


def now_string() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def write_payload(path: Path, payload: dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=True, sort_keys=True, indent=2)
        handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(tmp_name, path)
    dir_fd = os.open(path.parent, os.O_DIRECTORY)
    try:
        os.fsync(dir_fd)
    finally:
        os.close(dir_fd)


def release_idle_binding(path: Path, tasklight_bin: str, payload: dict[str, object]) -> None:
    task_id = payload.get("task_id")
    if task_id:
        subprocess.run(
            [tasklight_bin, "release", "--task-id", str(task_id)],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    now = now_string()
    payload["status"] = "released"
    payload["released_at"] = now
    payload["updated_at"] = now
    payload["watch_pid"] = None
    write_payload(path, payload)


def probe_private_state(probe_script: str, thread_id: str) -> dict[str, object]:
    if not probe_script or not thread_id:
        return {"inferred_status": "unknown", "evidence": ["private_probe:missing_config"]}
    completed = subprocess.run(
        ["python3", probe_script, "--thread-id", thread_id],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        timeout=3,
    )
    if completed.returncode not in (0, 2):
        return {"inferred_status": "unknown", "evidence": [f"private_probe:returncode={completed.returncode}"]}
    try:
        return json.loads(completed.stdout)
    except json.JSONDecodeError:
        return {"inferred_status": "unknown", "evidence": ["private_probe:invalid_json"]}


def appserver_bridge_path(probe_script: str) -> str:
    configured = os.environ.get("TASKLIGHT_APPSERVER_BRIDGE")
    if configured:
        return configured
    if probe_script:
        return str(Path(probe_script).with_name("codex_appserver_bridge.py"))
    return ""


def probe_appserver_state(appserver_script: str, thread_id: str) -> list[dict[str, object]]:
    if os.environ.get("TASKLIGHT_APPSERVER_DISABLED") == "1":
        return []
    if not appserver_script or not Path(appserver_script).exists():
        return []
    timeout = os.environ.get("TASKLIGHT_APPSERVER_LISTEN_SECONDS", "0.5")
    args = ["python3", appserver_script, "--listen", "--timeout", timeout, "--thread-id", thread_id]
    completed = subprocess.run(
        args,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        timeout=max(2.0, float(timeout) + 1.5),
    )
    if completed.returncode != 0:
        return []
    try:
        parsed = json.loads(completed.stdout)
    except json.JSONDecodeError:
        return []
    if isinstance(parsed, list):
        return [item for item in parsed if isinstance(item, dict)]
    if isinstance(parsed, dict):
        return [parsed]
    return []


def signal_spool_dir(binding_path: Path) -> Path:
    configured = os.environ.get("TASKLIGHT_SIGNAL_SPOOL_DIR")
    if configured:
        return Path(configured).expanduser()
    return binding_path.parent.parent / "signals"


def load_new_hook_signals(spool_dir: Path, thread_id: str, payload: dict[str, object]) -> list[dict[str, object]]:
    offsets = payload.get("signal_spool_offsets")
    if not isinstance(offsets, dict):
        offsets = {}
    paths = [
        spool_dir / f"{thread_id}.jsonl",
        spool_dir / "unknown.jsonl",
    ]
    signals: list[dict[str, object]] = []
    for path in paths:
        if not path.exists():
            continue
        previous = int(offsets.get(str(path), 0) or 0)
        size = path.stat().st_size
        if previous > size:
            previous = 0
        with path.open("r", encoding="utf-8") as handle:
            handle.seek(previous)
            for line in handle:
                line = line.strip()
                if not line:
                    continue
                try:
                    signal = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if not isinstance(signal, dict):
                    continue
                if signal.get("thread_id") not in {None, thread_id}:
                    continue
                signals.append(signal)
            offsets[str(path)] = handle.tell()
    payload["signal_spool_offsets"] = offsets
    return signals


def signal_status(signal: dict[str, object]) -> str:
    event_type = str(signal.get("event_type") or "")
    inferred = str(signal.get("inferred_status") or "")
    source = str(signal.get("source") or "")
    confidence = float(signal.get("confidence") or 0)
    thread_scoped = bool(signal.get("thread_scoped"))
    if event_type in {"blocked", "approval_pending", "tool_failed", "command_failed", "error"}:
        return "blocked"
    if event_type in {"turn_completed", "stop", "verified"}:
        return "terminal"
    if event_type in {"task_started", "heartbeat", "turn_started", "item_started"}:
        return "active"
    if event_type == "private_active":
        return "active" if thread_scoped and confidence >= 0.70 else "unknown"
    if event_type in {"private_quiet", "appserver_quiet", "quiet"} or inferred == "quiet":
        return "quiet"
    if inferred in {"active", "observed_active"}:
        if source == "codex_private_probe" or "sources" in signal:
            return "active" if thread_scoped and confidence >= 0.70 else "unknown"
        return "active"
    return "unknown"


def update_quiet_count(signals: list[dict[str, object]], previous: int) -> int:
    statuses = [signal_status(signal) for signal in signals]
    if any(status in {"active", "blocked", "terminal"} for status in statuses):
        return 0
    if any(status == "quiet" for status in statuses):
        return previous + 1
    return previous


def heartbeat_task(tasklight_bin: str, payload: dict[str, object], probe: dict[str, object]) -> None:
    task_id = payload.get("task_id")
    if not task_id:
        return
    phase = payload.get("phase") or "codex_session"
    progress = payload.get("progress")
    if progress is None:
        progress = 0.12
    subprocess.run(
        [tasklight_bin, "heartbeat", "--task-id", str(task_id), "--phase", str(phase), "--progress", str(progress)],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    now = now_string()
    payload["updated_at"] = now
    payload["private_status"] = probe.get("inferred_status")
    payload["private_checked_at"] = now
    payload["private_evidence"] = probe.get("evidence", [])[:6] if isinstance(probe.get("evidence"), list) else []


def fuse_signals(fusion_script: str, signals: list[dict[str, object]], quiet_count: int) -> dict[str, object]:
    if not fusion_script:
        return {"decision": "short_lease", "inferred_status": "unknown", "confidence": 0, "evidence": ["fusion:missing_config"]}
    completed = subprocess.run(
        ["python3", fusion_script, "--input", "-", "--quiet-count", str(quiet_count)],
        input=json.dumps(signals, ensure_ascii=True),
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        timeout=3,
    )
    if completed.returncode != 0:
        return {"decision": "short_lease", "inferred_status": "unknown", "confidence": 0, "evidence": [f"fusion:returncode={completed.returncode}"]}
    try:
        return json.loads(completed.stdout)
    except json.JSONDecodeError:
        return {"decision": "short_lease", "inferred_status": "unknown", "confidence": 0, "evidence": ["fusion:invalid_json"]}


def main() -> int:
    if len(sys.argv) != 8:
        print(
            "usage: codex_current_task_watcher.py <binding_path> <tasklight_bin> <interval> <active_lease_seconds> <thread_id> <probe_script> <fusion_script>",
            file=sys.stderr,
        )
        return 2

    path = Path(sys.argv[1])
    tasklight_bin = sys.argv[2]
    interval = float(sys.argv[3])
    active_lease_seconds = float(sys.argv[4])
    thread_id = sys.argv[5]
    probe_script = sys.argv[6]
    fusion_script = sys.argv[7]

    while True:
        time.sleep(interval)
        if not path.exists():
            return 0
        payload = json.loads(path.read_text(encoding="utf-8"))
        if payload.get("status") != "active":
            return 0
        if not payload.get("task_id"):
            release_idle_binding(path, tasklight_bin, payload)
            return 0

        probe = probe_private_state(probe_script, thread_id)
        signals: list[dict[str, object]] = []
        signals.extend(load_new_hook_signals(signal_spool_dir(path), thread_id, payload))
        signals.extend(probe_appserver_state(appserver_bridge_path(probe_script), thread_id))
        signals.append(probe)
        quiet_count = int(payload.get("quiet_count") or 0)
        quiet_count = update_quiet_count(signals, quiet_count)
        decision = fuse_signals(fusion_script, signals, quiet_count)
        payload["quiet_count"] = quiet_count
        payload["last_fusion_decision"] = decision.get("decision")
        payload["last_signal_confidence"] = decision.get("confidence")
        payload["last_signal_source"] = decision.get("signal_source")
        payload["last_source_quality"] = decision.get("source_quality")
        payload["last_inferred_status"] = decision.get("inferred_status")
        payload["last_signal_count"] = len(signals)
        payload["task_identity"] = decision.get("task_identity") or payload.get("task_identity")

        if decision.get("decision") == "refresh_managed_heartbeat":
            heartbeat_task(tasklight_bin, payload, decision)
            write_payload(path, payload)
            continue
        if decision.get("decision") == "release_binding":
            payload["private_status"] = probe.get("inferred_status")
            payload["private_evidence"] = decision.get("evidence", [])[:6] if isinstance(decision.get("evidence"), list) else []
            release_idle_binding(path, tasklight_bin, payload)
            return 0
        if decision.get("decision") in {"short_lease", "observed_only"}:
            payload["private_status"] = probe.get("inferred_status")
            payload["private_evidence"] = decision.get("evidence", [])[:6] if isinstance(decision.get("evidence"), list) else []
            write_payload(path, payload)

        updated_at = parse_ts(payload.get("updated_at"))
        if updated_at is None:
            release_idle_binding(path, tasklight_bin, payload)
            return 0
        idle_seconds = datetime.now(timezone.utc).timestamp() - updated_at.timestamp()
        if idle_seconds > active_lease_seconds:
            release_idle_binding(path, tasklight_bin, payload)
            return 0


if __name__ == "__main__":
    raise SystemExit(main())
