#!/usr/bin/env python3
"""Read-only Codex local-state probe.

The probe emits metadata only: timestamps, counts, process liveness, and an
inferred active/quiet/unknown status. It does not print prompts, responses,
auth data, or log bodies.
"""

from __future__ import annotations

import argparse
import json
import os
import sqlite3
import time
from pathlib import Path
from typing import Any

from tasklight_signal_bus import append_signal


def pid_alive(pid: object) -> bool:
    if not isinstance(pid, int) or pid <= 0:
        return False
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def safe_age(now: float, timestamp: float | None) -> int | None:
    if timestamp is None:
        return None
    return max(0, int(now - timestamp))


def probe_logs(codex_home: Path, thread_id: str, now: float) -> dict[str, Any]:
    path = codex_home / "logs_2.sqlite"
    result: dict[str, Any] = {
        "path": str(path),
        "readable": False,
        "thread_log_count": 0,
        "last_log_age_sec": None,
        "last_log_ts": None,
        "global_last_log_age_sec": None,
        "global_last_log_ts": None,
    }
    if not path.exists():
        return result
    try:
        con = sqlite3.connect(f"file:{path}?mode=ro", uri=True, timeout=1)
        try:
            row = con.execute(
                "select count(*), max(ts) from logs where thread_id = ?",
                (thread_id,),
            ).fetchone()
            global_row = con.execute("select max(ts) from logs").fetchone()
        finally:
            con.close()
        count = int(row[0] or 0)
        last_ts = float(row[1]) if row and row[1] is not None else None
        global_last_ts = float(global_row[0]) if global_row and global_row[0] is not None else None
        result.update(
            {
                "readable": True,
                "thread_log_count": count,
                "last_log_age_sec": safe_age(now, last_ts),
                "last_log_ts": int(last_ts) if last_ts is not None else None,
                "global_last_log_age_sec": safe_age(now, global_last_ts),
                "global_last_log_ts": int(global_last_ts) if global_last_ts is not None else None,
            }
        )
    except Exception as exc:  # pragma: no cover - diagnostic path
        result["error"] = type(exc).__name__
    return result


def matches_thread(record: dict[str, Any], thread_id: str) -> bool:
    for key in ("conversationId", "threadId", "thread_id", "id"):
        value = record.get(key)
        if isinstance(value, str) and value == thread_id:
            return True
    return False


def probe_processes(codex_home: Path, thread_id: str, now: float) -> dict[str, Any]:
    path = codex_home / "process_manager" / "chat_processes.json"
    result: dict[str, Any] = {
        "path": str(path),
        "readable": False,
        "matching_records": 0,
        "alive_records": 0,
        "last_process_update_age_sec": None,
        "latest_turn_id": None,
        "latest_item_id": None,
    }
    if not path.exists():
        return result
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
        records = payload if isinstance(payload, list) else []
        matches = [record for record in records if isinstance(record, dict) and matches_thread(record, thread_id)]
        alive = [record for record in matches if pid_alive(record.get("osPid"))]
        last_ms = max(
            [record.get("updatedAtMs") for record in matches if isinstance(record.get("updatedAtMs"), int)],
            default=None,
        )
        latest = max(
            matches,
            key=lambda record: record.get("updatedAtMs") if isinstance(record.get("updatedAtMs"), int) else -1,
            default=None,
        )
        result.update(
            {
                "readable": True,
                "matching_records": len(matches),
                "alive_records": len(alive),
                "last_process_update_age_sec": safe_age(now, last_ms / 1000 if last_ms else None),
                "latest_turn_id": latest.get("turnId") if latest else None,
                "latest_item_id": latest.get("itemId") if latest else None,
            }
        )
    except Exception as exc:  # pragma: no cover - diagnostic path
        result["error"] = type(exc).__name__
    return result


def probe_session_index(codex_home: Path, thread_id: str, now: float) -> dict[str, Any]:
    path = codex_home / "session_index.jsonl"
    result: dict[str, Any] = {
        "path": str(path),
        "readable": False,
        "found": False,
        "session_updated_age_sec": None,
    }
    if not path.exists():
        return result
    try:
        found_at: float | None = None
        with path.open(encoding="utf-8", errors="ignore") as handle:
            for line in handle:
                if not line.strip():
                    continue
                try:
                    item = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if item.get("id") != thread_id:
                    continue
                updated_at = item.get("updated_at")
                if isinstance(updated_at, str):
                    try:
                        found_at = time.mktime(time.strptime(updated_at.replace("Z", "+0000"), "%Y-%m-%dT%H:%M:%S%z"))
                    except ValueError:
                        found_at = None
                break
        result.update(
            {
                "readable": True,
                "found": found_at is not None,
                "session_updated_age_sec": safe_age(now, found_at),
            }
        )
    except Exception as exc:  # pragma: no cover - diagnostic path
        result["error"] = type(exc).__name__
    return result


def probe_shell_snapshots(codex_home: Path, thread_id: str, now: float) -> dict[str, Any]:
    path = codex_home / "shell_snapshots"
    result: dict[str, Any] = {
        "path": str(path),
        "readable": False,
        "matching_files": 0,
        "last_snapshot_age_sec": None,
    }
    if not path.exists():
        return result
    try:
        matches = list(path.glob(f"{thread_id}.*.sh"))
        last_mtime = max([item.stat().st_mtime for item in matches], default=None)
        result.update(
            {
                "readable": True,
                "matching_files": len(matches),
                "last_snapshot_age_sec": safe_age(now, last_mtime),
            }
        )
    except Exception as exc:  # pragma: no cover - diagnostic path
        result["error"] = type(exc).__name__
    return result


def infer_status(
    logs: dict[str, Any],
    processes: dict[str, Any],
    session: dict[str, Any],
    snapshots: dict[str, Any],
    active_window_sec: int,
    process_window_sec: int,
) -> tuple[str, float, bool, bool, str, str, list[str], list[str]]:
    evidence: list[str] = []
    conflicts: list[str] = []
    thread_scoped = False
    turn_scoped = False
    confidence = 0.0
    source_quality = "unavailable"
    decision = "unknown_short_lease"

    log_age = logs.get("last_log_age_sec")
    global_log_age = logs.get("global_last_log_age_sec")
    turn_id = processes.get("latest_turn_id")

    if isinstance(log_age, int) and log_age <= active_window_sec:
        evidence.append(f"logs_2.sqlite:last_log_age_sec={log_age}")
        thread_scoped = True
        turn_scoped = isinstance(turn_id, str) and bool(turn_id)
        confidence = 0.78 if turn_scoped else 0.72
        source_quality = "thread_private_metadata"
        decision = "refresh_lease"
        return "active", confidence, thread_scoped, turn_scoped, source_quality, decision, evidence, conflicts

    process_age = processes.get("last_process_update_age_sec")
    if processes.get("alive_records", 0) > 0 and isinstance(process_age, int) and process_age <= process_window_sec:
        evidence.append(f"chat_processes.json:alive_records={processes.get('alive_records')}")
        evidence.append(f"chat_processes.json:last_process_update_age_sec={process_age}")
        thread_scoped = True
        turn_scoped = isinstance(turn_id, str) and bool(turn_id)
        confidence = 0.76 if turn_scoped else 0.70
        source_quality = "thread_process_metadata"
        decision = "refresh_lease"
        return "active", confidence, thread_scoped, turn_scoped, source_quality, decision, evidence, conflicts

    if isinstance(global_log_age, int) and global_log_age <= active_window_sec:
        evidence.append(f"logs_2.sqlite:global_last_log_age_sec={global_log_age}")
        conflicts.append("global_log_is_not_thread_scoped")
        return "observed_active", 0.25, False, False, "global_private_metadata", "observed_only", evidence, conflicts

    known = False
    for source, key in (
        (logs, "last_log_age_sec"),
        (processes, "last_process_update_age_sec"),
        (session, "session_updated_age_sec"),
        (snapshots, "last_snapshot_age_sec"),
    ):
        value = source.get(key)
        if isinstance(value, int):
            known = True
            evidence.append(f"{Path(source.get('path', key)).name}:{key}={value}")

    if known:
        return "quiet", 0.55, bool(logs.get("thread_log_count")), False, "stale_private_metadata", "release_binding", evidence, conflicts
    return "unknown", 0.0, False, False, "unavailable", "unknown_short_lease", evidence, conflicts


def payload_to_signal(payload: dict[str, Any]) -> dict[str, Any]:
    inferred_status = str(payload.get("inferred_status") or "unknown")
    if inferred_status in {"active", "running"}:
        event_type = "private_active"
    elif inferred_status == "observed_active":
        event_type = "observed_active"
    elif inferred_status == "quiet":
        event_type = "private_quiet"
    else:
        event_type = "unknown"
    return {
        "source": "codex_private_probe",
        "event_type": event_type,
        "thread_id": payload.get("thread_id"),
        "turn_id": payload.get("turn_id"),
        "item_id": payload.get("item_id"),
        "occurred_at": payload.get("checked_at"),
        "confidence": payload.get("confidence", 0.0),
        "thread_scoped": payload.get("thread_scoped"),
        "turn_scoped": payload.get("turn_scoped"),
        "source_quality": payload.get("source_quality"),
        "reason": payload.get("reason"),
        "message": None,
        "evidence": payload.get("evidence") or [],
        "conflicts": payload.get("conflicts") or [],
        "raw_event_ref": "private_probe",
        "status_hint": inferred_status,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Read-only Codex local-state probe")
    parser.add_argument("--thread-id", default=os.environ.get("CODEX_THREAD_ID", ""))
    parser.add_argument("--codex-home", default=os.environ.get("CODEX_HOME", str(Path.home() / ".codex")))
    parser.add_argument("--active-window-sec", type=int, default=int(os.environ.get("CODEX_PRIVATE_ACTIVE_WINDOW_SECONDS", "30")))
    parser.add_argument("--process-window-sec", type=int, default=int(os.environ.get("CODEX_PRIVATE_PROCESS_WINDOW_SECONDS", "120")))
    args = parser.parse_args()

    now = time.time()
    codex_home = Path(args.codex_home).expanduser()
    thread_id = args.thread_id
    if not thread_id:
        payload = {
            "thread_id": None,
            "turn_id": None,
            "item_id": None,
            "inferred_status": "unknown",
            "confidence": 0.0,
            "thread_scoped": False,
            "turn_scoped": False,
            "source_quality": "missing_thread_id",
            "decision": "unknown_short_lease",
            "reason": "missing_thread_id",
            "evidence": [],
            "conflicts": ["missing_thread_id"],
            "sources": {},
        }
        print(json.dumps(payload, ensure_ascii=True, sort_keys=True, indent=2))
        return 2

    logs = probe_logs(codex_home, thread_id, now)
    processes = probe_processes(codex_home, thread_id, now)
    session = probe_session_index(codex_home, thread_id, now)
    snapshots = probe_shell_snapshots(codex_home, thread_id, now)
    inferred_status, confidence, thread_scoped, turn_scoped, source_quality, decision, evidence, conflicts = infer_status(
        logs,
        processes,
        session,
        snapshots,
        args.active_window_sec,
        args.process_window_sec,
    )

    payload = {
        "thread_id": thread_id,
        "turn_id": processes.get("latest_turn_id"),
        "item_id": processes.get("latest_item_id"),
        "codex_home": str(codex_home),
        "checked_at": int(now),
        "inferred_status": inferred_status,
        "confidence": confidence,
        "thread_scoped": thread_scoped,
        "turn_scoped": turn_scoped,
        "source_quality": source_quality,
        "decision": decision,
        "active_window_sec": args.active_window_sec,
        "process_window_sec": args.process_window_sec,
        "evidence": evidence,
        "conflicts": conflicts,
        "sources": {
            "logs": logs,
            "processes": processes,
            "session_index": session,
            "shell_snapshots": snapshots,
        },
    }
    append_signal(payload_to_signal(payload))
    print(json.dumps(payload, ensure_ascii=True, sort_keys=True, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
