#!/usr/bin/env python3
"""Fuse Codex status signals into one tasklight-safe decision."""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path
from typing import Any


SOURCE_PRIORITY = {
    "explicit": 100,
    "codex_appserver": 90,
    "codex_hook": 80,
    "codex_cloud_stub": 70,
    "codex_private_probe": 40,
    "process_observer": 20,
}

BLOCK_EVENTS = {"blocked", "approval_pending", "tool_failed", "command_failed", "error"}
DONE_EVENTS = {"turn_completed", "stop"}
ACTIVE_EVENTS = {"task_started", "heartbeat", "turn_started", "item_started", "private_active"}
QUIET_EVENTS = {"private_quiet", "appserver_quiet", "quiet"}


def load_json_payload(raw: str) -> list[dict[str, Any]]:
    raw = raw.strip()
    if not raw:
        return []
    try:
        parsed = json.loads(raw)
        if isinstance(parsed, list):
            return [item for item in parsed if isinstance(item, dict)]
        if isinstance(parsed, dict):
            return [parsed]
    except json.JSONDecodeError:
        pass

    signals: list[dict[str, Any]] = []
    for line in raw.splitlines():
        line = line.strip()
        if not line:
            continue
        item = json.loads(line)
        if isinstance(item, dict):
            signals.append(item)
    return signals


def normalize_signal(signal: dict[str, Any]) -> dict[str, Any]:
    if "sources" in signal and "inferred_status" in signal:
        status = signal.get("inferred_status")
        event_type = "private_active" if status in {"active", "observed_active"} else "private_quiet" if status == "quiet" else "unknown"
        return {
            "source": "codex_private_probe",
            "event_type": event_type,
            "thread_id": signal.get("thread_id"),
            "turn_id": signal.get("turn_id"),
            "item_id": signal.get("item_id"),
            "event_time": signal.get("checked_at"),
            "confidence": signal.get("confidence", 0),
            "thread_scoped": bool(signal.get("thread_scoped")),
            "turn_scoped": bool(signal.get("turn_scoped")),
            "source_quality": signal.get("source_quality", "private_metadata"),
            "evidence": signal.get("evidence", []),
            "conflicts": signal.get("conflicts", []),
        }
    return signal


def signal_priority(signal: dict[str, Any]) -> tuple[int, float, float]:
    source = str(signal.get("source") or "")
    confidence = float(signal.get("confidence") or 0)
    event_time = signal.get("event_time")
    try:
        event_ts = float(event_time)
    except (TypeError, ValueError):
        event_ts = 0
    return (SOURCE_PRIORITY.get(source, 0), confidence, event_ts)


def task_identity(signal: dict[str, Any]) -> str | None:
    thread_id = signal.get("thread_id")
    turn_id = signal.get("turn_id")
    task_id = signal.get("task_id")
    if thread_id and turn_id:
        return f"{thread_id}:{turn_id}"
    if task_id:
        return str(task_id)
    if thread_id:
        return str(thread_id)
    if turn_id:
        return f"turn:{turn_id}"
    return None


def base_output(signals: list[dict[str, Any]]) -> dict[str, Any]:
    conflicts: list[str] = []
    evidence: list[str] = []
    for signal in signals:
        for item in signal.get("conflicts", []) or []:
            conflicts.append(str(item))
        for item in signal.get("evidence", []) or []:
            evidence.append(str(item))
    return {
        "inferred_status": "unknown",
        "decision": "short_lease",
        "confidence": 0.0,
        "authoritative": False,
        "evidence": evidence[:12],
        "conflicts": conflicts[:12],
        "task_identity": None,
        "blocker_reason": None,
        "signal_source": None,
        "source_quality": None,
    }


def source_fields(signal: dict[str, Any]) -> dict[str, Any]:
    return {
        "signal_source": signal.get("source"),
        "source_quality": signal.get("source_quality"),
    }


def fuse(signals: list[dict[str, Any]], quiet_count: int = 0) -> dict[str, Any]:
    normalized = [normalize_signal(signal) for signal in signals]
    normalized.sort(key=signal_priority, reverse=True)
    output = base_output(normalized)

    if not normalized:
        output["conflicts"].append("no_signals")
        return output

    for signal in normalized:
        source = signal.get("source")
        event_type = signal.get("event_type")
        confidence = float(signal.get("confidence") or 0)
        identity = task_identity(signal)

        if source == "explicit" and event_type == "verified":
            output.update(
                {
                    "inferred_status": "done_verified",
                    "decision": "ignore",
                    "confidence": max(confidence, 1.0),
                    "authoritative": True,
                    "task_identity": identity,
                    **source_fields(signal),
                }
            )
            return output

        if event_type in BLOCK_EVENTS:
            output.update(
                {
                    "inferred_status": "blocked",
                    "decision": "block_task",
                    "confidence": max(confidence, 0.90 if source in {"explicit", "codex_appserver", "codex_hook"} else confidence),
                    "authoritative": source in {"explicit", "codex_appserver", "codex_hook"},
                    "task_identity": identity,
                    "blocker_reason": signal.get("reason") or ("needs_human_review" if event_type == "approval_pending" else "codex_exit_failed"),
                    **source_fields(signal),
                }
            )
            return output

        if event_type in DONE_EVENTS:
            output.update(
                {
                    "inferred_status": "done_unverified",
                    "decision": "mark_done_unverified",
                    "confidence": max(confidence, 0.85),
                    "authoritative": source in {"codex_appserver", "codex_hook", "explicit"},
                    "task_identity": identity,
                    **source_fields(signal),
                }
            )
            return output

        if event_type in ACTIVE_EVENTS:
            is_private = source == "codex_private_probe"
            allowed_private = (
                is_private
                and bool(signal.get("thread_scoped"))
                and confidence >= 0.70
            )
            authoritative = source in {"explicit", "codex_appserver", "codex_hook"} or allowed_private
            if authoritative:
                output.update(
                    {
                        "inferred_status": "running",
                        "decision": "refresh_managed_heartbeat",
                        "confidence": confidence,
                        "authoritative": source in {"explicit", "codex_appserver", "codex_hook"},
                        "task_identity": identity,
                        **source_fields(signal),
                    }
                )
                return output
            output.update(
                {
                    "inferred_status": "observed_active",
                    "decision": "observed_only",
                    "confidence": confidence,
                    "authoritative": False,
                    "task_identity": identity,
                    **source_fields(signal),
                }
            )
            return output

    if any(signal.get("event_type") in QUIET_EVENTS for signal in normalized):
        output.update(
            {
                "inferred_status": "quiet",
                "decision": "release_binding" if quiet_count >= 3 else "short_lease",
                "confidence": max(float(signal.get("confidence") or 0) for signal in normalized),
                "authoritative": False,
                "task_identity": task_identity(normalized[0]),
                **source_fields(normalized[0]),
            }
        )
        return output

    output["task_identity"] = task_identity(normalized[0])
    return output


def main() -> int:
    parser = argparse.ArgumentParser(description="Fuse Codex task signals")
    parser.add_argument("--input", default="-", help="JSON/JSONL signal input path, or - for stdin")
    parser.add_argument("--quiet-count", type=int, default=0)
    args = parser.parse_args()

    if args.input == "-":
        raw = sys.stdin.read()
    else:
        raw = Path(args.input).read_text(encoding="utf-8")
    signals = load_json_payload(raw)
    print(json.dumps(fuse(signals, quiet_count=args.quiet_count), ensure_ascii=True, sort_keys=True, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
