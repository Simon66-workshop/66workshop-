#!/usr/bin/env python3
"""Convert Codex hook events into tasklight signal JSON."""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from pathlib import Path
from typing import Any


EVENT_NAME_KEYS = (
    "hook",
    "event",
    "type",
    "eventName",
    "event_name",
    "hookEventName",
    "hook_event_name",
    "hookName",
    "hook_name",
)

EVENT_NAME_ALIASES = {
    "sessionstart": "sessionStart",
    "session_start": "sessionStart",
    "sessionStart": "sessionStart",
    "userpromptsubmit": "userPromptSubmit",
    "user_prompt_submit": "userPromptSubmit",
    "userPromptSubmit": "userPromptSubmit",
    "pretooluse": "preToolUse",
    "pre_tool_use": "preToolUse",
    "preToolUse": "preToolUse",
    "permissionrequest": "permissionRequest",
    "permission_request": "permissionRequest",
    "permissionRequest": "permissionRequest",
    "posttooluse": "postToolUse",
    "post_tool_use": "postToolUse",
    "postToolUse": "postToolUse",
    "stop": "stop",
    "Stop": "stop",
}


def read_event(path: str) -> dict[str, Any]:
    raw = sys.stdin.read() if path == "-" else Path(path).read_text(encoding="utf-8")
    payload = json.loads(raw)
    if not isinstance(payload, dict):
        raise ValueError("hook event must be a JSON object")
    return payload


def first_value(event: dict[str, Any], keys: tuple[str, ...]) -> Any:
    for key in keys:
        value = event.get(key)
        if value not in (None, ""):
            return value
    nested = event.get("run")
    if isinstance(nested, dict):
        for key in keys:
            value = nested.get(key)
            if value not in (None, ""):
                return value
    return None


def normalize_hook_name(value: Any) -> str:
    if value is None:
        return ""
    raw = str(value)
    candidates = (
        raw,
        raw.replace("-", "_"),
        raw[:1].lower() + raw[1:] if raw else raw,
        raw.lower(),
        raw.replace("-", "_").lower(),
    )
    for candidate in candidates:
        normalized = EVENT_NAME_ALIASES.get(candidate)
        if normalized:
            return normalized
    return raw


def hook_name(event: dict[str, Any]) -> str:
    return normalize_hook_name(first_value(event, EVENT_NAME_KEYS))


def scoped_value(event: dict[str, Any], snake: str, camel: str) -> Any:
    return event.get(snake) or event.get(camel)


def event_failed(event: dict[str, Any]) -> bool:
    exit_code = event.get("exit_code")
    if exit_code is None:
        exit_code = event.get("exitCode")
    status = str(event.get("status") or "").lower()
    return event.get("success") is False or exit_code not in (None, 0) or status in {"failed", "error"}


def to_signal(event: dict[str, Any]) -> dict[str, Any]:
    name = hook_name(event)
    event_type = "unknown"
    reason = None
    message = None
    if name in {"sessionStart", "userPromptSubmit"}:
        event_type = "turn_started"
    elif name == "preToolUse":
        event_type = "item_started"
    elif name == "permissionRequest":
        event_type = "approval_pending"
        reason = "needs_human_review"
        message = "Codex hook requested permission"
    elif name == "postToolUse":
        event_type = "tool_failed" if event_failed(event) else "item_completed"
        if event_type == "tool_failed":
            reason = "codex_exit_failed"
            message = "Codex hook reported tool failure"
    elif name == "stop":
        event_type = "stop"

    thread_id = scoped_value(event, "thread_id", "threadId") or os.environ.get("CODEX_THREAD_ID")
    turn_id = scoped_value(event, "turn_id", "turnId")
    item_id = scoped_value(event, "item_id", "itemId")

    return {
        "source": "codex_hook",
        "event_type": event_type,
        "thread_id": thread_id,
        "turn_id": turn_id,
        "item_id": item_id,
        "event_time": event.get("event_time") or int(time.time()),
        "confidence": 0.85 if event_type != "unknown" else 0.0,
        "thread_scoped": bool(thread_id),
        "turn_scoped": bool(turn_id),
        "source_quality": "codex_hook_event" if event_type != "unknown" else "codex_hook_unknown",
        "reason": reason,
        "message": message,
        "evidence": [f"codex_hook:{name}"] if name else [],
        "conflicts": [] if event_type != "unknown" else ["unknown_hook_event"],
        "raw_event_ref": name,
    }


def append_spool(spool_dir: Path, signal: dict[str, Any]) -> Path:
    thread_id = signal.get("thread_id") or "unknown"
    spool_dir.mkdir(parents=True, exist_ok=True)
    path = spool_dir / f"{thread_id}.jsonl"
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(signal, ensure_ascii=True, sort_keys=True, separators=(",", ":")) + "\n")
    return path


def main() -> int:
    parser = argparse.ArgumentParser(description="Convert Codex hook event JSON to tasklight signal JSON")
    parser.add_argument("--event-json")
    parser.add_argument("--spool-dir")
    parser.add_argument("--health", action="store_true", help="Run a read-only health check and exit")
    args = parser.parse_args()

    if args.health:
        payload = {
            "ok": True,
            "tool": "codex_hook_event",
            "mode": "health",
            "writes_task_state": False,
            "supports_event_json": True,
            "supports_spool": True,
        }
        print(json.dumps(payload, ensure_ascii=True, sort_keys=True, indent=2))
        return 0

    if not args.event_json:
        parser.error("--event-json is required unless --health is used")

    signal = to_signal(read_event(args.event_json))
    if args.spool_dir:
        path = append_spool(Path(args.spool_dir).expanduser(), signal)
        signal["spool_path"] = str(path)
    print(json.dumps(signal, ensure_ascii=True, sort_keys=True, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
