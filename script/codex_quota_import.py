#!/usr/bin/env python3
"""Import sanitized Codex quota text into quota_state.json."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import tempfile
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any


SCHEMA_VERSION = "0.2"
DEFAULT_STATE_DIR = Path.home() / ".66tasklight"
WINDOW_RE = re.compile(
    r"(?P<label>\d+\s*(?:分钟|小时|天|周))\s+(?P<percent>\d{1,3})%\s*(?P<reset>(?:\d{1,2}:\d{2})|(?:\d{1,2}月\d{1,2}日))?"
)
RESET_RE = re.compile(r"(?P<count>\d+)\s*次\s*可用\s*重置")


def state_dir() -> Path:
    return Path(os.environ.get("TASKLIGHT_STATE_DIR", str(DEFAULT_STATE_DIR))).expanduser()


def quota_state_path(root: Path | None = None) -> Path:
    root = root or state_dir()
    return Path(os.environ.get("TASKLIGHT_QUOTA_STATE_PATH", str(root / "quota_state.json"))).expanduser()


def now_iso() -> str:
    return datetime.now().astimezone().replace(microsecond=0).isoformat()


def atomic_write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False, sort_keys=True, indent=2)
        handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(tmp_name, path)


def health_for_percent(percent: int | None) -> str:
    if percent is None:
        return "unknown"
    if percent >= 50:
        return "ok"
    if percent >= 20:
        return "watch"
    if percent >= 5:
        return "low"
    return "critical"


def recommendation_for_status(status: str) -> str:
    return {
        "ok": "normal",
        "watch": "watch_usage",
        "low": "reduce_parallel_tasks",
        "critical": "avoid_new_heavy_tasks",
    }.get(status, "normal")


def parse_duration_mins(label: str) -> int | None:
    compact = label.replace(" ", "")
    match = re.match(r"(?P<num>\d+)(?P<unit>分钟|小时|天|周)", compact)
    if not match:
        return None
    number = int(match.group("num"))
    unit = match.group("unit")
    if unit == "分钟":
        return number
    if unit == "小时":
        return number * 60
    if unit == "天":
        return number * 1440
    if unit == "周":
        return number * 10080
    return None


def format_window_label(mins: int | None, fallback: str) -> str:
    if mins is None:
        return fallback.replace(" ", "")
    if mins % 10080 == 0:
        return f"{mins // 10080}周"
    if mins % 1440 == 0:
        return f"{mins // 1440}天"
    if mins % 60 == 0:
        return f"{mins // 60}小时"
    return f"{mins}分钟"


def parse_reset_at(label: str | None) -> str | None:
    if not label:
        return None
    now = datetime.now().astimezone()
    if re.match(r"^\d{1,2}:\d{2}$", label):
        hour, minute = [int(part) for part in label.split(":", 1)]
        candidate = now.replace(hour=hour, minute=minute, second=0, microsecond=0)
        if candidate <= now:
            candidate += timedelta(days=1)
        return candidate.isoformat()
    match = re.match(r"^(?P<month>\d{1,2})月(?P<day>\d{1,2})日$", label)
    if match:
        candidate = now.replace(month=int(match.group("month")), day=int(match.group("day")), hour=0, minute=0, second=0, microsecond=0)
        if candidate <= now:
            candidate = candidate.replace(year=candidate.year + 1)
        return candidate.isoformat()
    return None


def window_selection_reason(window: dict[str, Any], *, selected: bool = False, candidate_count: int = 1) -> str:
    bucket_id = str(window.get("bucket_id") or "").lower()
    if bucket_id == "codex":
        base = "account_codex_bucket"
    elif "codex" in bucket_id and not bucket_id.startswith("codex_"):
        base = "account_codex_like_bucket"
    elif bucket_id.startswith("codex_"):
        base = "model_specific_codex_bucket"
    elif bucket_id:
        base = "non_codex_fallback_bucket"
    else:
        base = "manual_or_unknown_bucket"
    if selected:
        return f"selected_{base}_from_{candidate_count}_candidate{'s' if candidate_count != 1 else ''}"
    return f"raw_{base}"


def normalized_raw_windows(windows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    clean = [dict(window) for window in windows if isinstance(window.get("remaining_percent"), int)]
    for window in clean:
        window["health"] = health_for_percent(window.get("remaining_percent"))
        window.setdefault("selection_reason", window_selection_reason(window))
    clean.sort(
        key=lambda item: (
            item.get("window_duration_mins") if item.get("window_duration_mins") is not None else 10**9,
            display_bucket_priority(item),
            str(item.get("bucket_id") or ""),
        )
    )
    return clean


def normalize_windows(windows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Return display windows for backwards-compatible callers."""
    return select_display_windows(normalized_raw_windows(windows))


def select_display_windows(windows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    clean = [window for window in windows if isinstance(window.get("remaining_percent"), int)]
    grouped: dict[Any, list[dict[str, Any]]] = {}
    for window in clean:
        key = window.get("window_duration_mins") if window.get("window_duration_mins") is not None else window.get("label")
        grouped.setdefault(key, []).append(window)

    selected = [select_display_window(candidates) for _, candidates in grouped.items()]
    selected.sort(key=lambda item: item.get("window_duration_mins") if item.get("window_duration_mins") is not None else 10**9)
    total = len(selected)
    for index, window in enumerate(selected):
        if index == 0:
            window["id"] = "short"
        elif index == total - 1:
            window["id"] = "long"
        else:
            window["id"] = f"window_{index + 1}"
    return selected


def display_bucket_priority(window: dict[str, Any]) -> tuple[int, int]:
    bucket_id = str(window.get("bucket_id") or "").lower()
    if bucket_id == "codex":
        return (0, 0)
    if bucket_id.startswith("codex_"):
        return (2, int(window.get("remaining_percent") or 0))
    if "codex" in bucket_id:
        return (1, int(window.get("remaining_percent") or 0))
    return (3, int(window.get("remaining_percent") or 0))


def select_display_window(candidates: list[dict[str, Any]]) -> dict[str, Any]:
    # Codex UI displays the account-level "codex" bucket when a model-specific
    # bucket shares the same reset window. Match that visible source first.
    selected = dict(sorted(candidates, key=display_bucket_priority)[0])
    selected["selection_reason"] = window_selection_reason(selected, selected=True, candidate_count=len(candidates))
    return selected


def build_quota_state(*, source: str, source_confidence: float, windows: list[dict[str, Any]], manual_resets: dict[str, Any] | None, warnings: list[str] | None = None) -> dict[str, Any]:
    raw_windows = normalized_raw_windows(windows)
    display_windows = select_display_windows(raw_windows)
    if not display_windows:
        raise ValueError("no valid quota windows parsed")
    effective = min(window["remaining_percent"] for window in display_windows)
    quota_status = health_for_percent(effective)
    merged_warnings = list(warnings or [])
    if len(raw_windows) > len(display_windows):
        merged_warnings.append("duplicate_quota_buckets_collapsed_to_display_windows")
    return {
        "schema_version": SCHEMA_VERSION,
        "source": source,
        "source_confidence": source_confidence,
        "captured_at": now_iso(),
        "fresh": True,
        "quota_status": quota_status,
        "raw_windows": raw_windows,
        "display_windows": display_windows,
        "windows": display_windows,
        "manual_resets": manual_resets or {"available_count": None, "label": None},
        "effective_remaining_percent": effective,
        "recommendation": recommendation_for_status(quota_status),
        "warnings": merged_warnings,
    }


def parse_usage_text(text: str, source: str) -> dict[str, Any]:
    windows: list[dict[str, Any]] = []
    warnings: list[str] = []
    for match in WINDOW_RE.finditer(text):
        label = match.group("label").replace(" ", "")
        percent = int(match.group("percent"))
        if percent < 0 or percent > 100:
            raise ValueError(f"invalid percent for {label}")
        reset_label = match.group("reset")
        duration = parse_duration_mins(label)
        windows.append(
                {
                    "id": "",
                    "label": format_window_label(duration, label),
                    "remaining_percent": percent,
                    "used_percent": None,
                    "reset_label": reset_label,
                    "reset_at": parse_reset_at(reset_label),
                    "window_duration_mins": duration,
                    "health": health_for_percent(percent),
                    "bucket_id": "manual",
                    "limit_name": "manual_usage_text",
                    "role": "manual",
                }
            )
    reset_match = RESET_RE.search(text)
    manual_resets = {"available_count": None, "label": None}
    if reset_match:
        count = int(reset_match.group("count"))
        manual_resets = {"available_count": count, "label": f"{count}次可用重置"}
    return build_quota_state(source=source, source_confidence=0.85, windows=windows, manual_resets=manual_resets, warnings=warnings)


def normalize_appserver_response(result: dict[str, Any]) -> dict[str, Any]:
    raw_buckets = result.get("rateLimitsByLimitId")
    if isinstance(raw_buckets, dict):
        buckets = list(raw_buckets.values())
    else:
        buckets = result.get("rateLimits") if isinstance(result.get("rateLimits"), list) else []
    windows: list[dict[str, Any]] = []
    warnings: list[str] = []
    for bucket in buckets:
        if not isinstance(bucket, dict):
            continue
        limit_id = str(bucket.get("limitId") or bucket.get("id") or "").lower()
        limit_name = str(bucket.get("limitName") or bucket.get("name") or "").lower()
        if "codex" not in limit_id and "codex" not in limit_name:
            continue
        for role in ("primary", "secondary"):
            window = bucket.get(role)
            if not isinstance(window, dict):
                continue
            used = window.get("usedPercent")
            try:
                used_percent = int(round(float(used)))
            except (TypeError, ValueError):
                continue
            remaining = max(0, min(100, 100 - used_percent))
            duration = window.get("windowDurationMins")
            try:
                duration_mins = int(duration) if duration is not None else None
            except (TypeError, ValueError):
                duration_mins = None
            resets_at = window.get("resetsAt")
            reset_label = None
            reset_iso = None
            if isinstance(resets_at, (int, float)):
                reset_dt = datetime.fromtimestamp(float(resets_at), tz=datetime.now().astimezone().tzinfo)
                reset_iso = reset_dt.replace(microsecond=0).isoformat()
                reset_label = reset_dt.strftime("%H:%M") if reset_dt.date() == datetime.now().astimezone().date() else f"{reset_dt.month}月{reset_dt.day}日"
            label = format_window_label(duration_mins, role)
            windows.append(
                {
                    "id": role,
                    "label": label,
                    "remaining_percent": remaining,
                    "used_percent": used_percent,
                    "reset_label": reset_label,
                    "reset_at": reset_iso,
                    "window_duration_mins": duration_mins,
                    "health": health_for_percent(remaining),
                    "bucket_id": bucket.get("limitId") or bucket.get("id"),
                    "limit_name": bucket.get("limitName") or bucket.get("name"),
                    "role": role,
                }
            )
    if not windows:
        return {
            "schema_version": SCHEMA_VERSION,
            "source": "codex_appserver",
            "source_confidence": 0.0,
            "captured_at": now_iso(),
            "fresh": True,
            "quota_status": "unknown",
            "raw_windows": [],
            "display_windows": [],
            "windows": [],
            "manual_resets": {"available_count": None, "label": None},
            "effective_remaining_percent": None,
            "recommendation": "normal",
            "warnings": ["no_codex_bucket"],
        }
    return build_quota_state(
        source="codex_appserver",
        source_confidence=0.95 if windows else 0.0,
        windows=windows,
        manual_resets={"available_count": None, "label": None},
        warnings=warnings,
    )


def read_clipboard() -> str:
    completed = subprocess.run(["pbpaste"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, timeout=3)
    return completed.stdout


def main() -> int:
    parser = argparse.ArgumentParser(description="Import sanitized Codex quota usage into quota_state.json")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--text")
    group.add_argument("--from-clipboard", action="store_true")
    group.add_argument("--input-file")
    parser.add_argument("--output")
    parser.add_argument("--print-json", action="store_true")
    args = parser.parse_args()

    if args.text is not None:
        text = args.text
        source = "manual_text_import"
    elif args.from_clipboard:
        text = read_clipboard()
        source = "clipboard_import"
    else:
        text = Path(args.input_file).expanduser().read_text(encoding="utf-8")
        source = "input_file_import"

    payload = parse_usage_text(text, source)
    output = Path(args.output).expanduser() if args.output else quota_state_path()
    atomic_write_json(output, payload)
    if args.print_json:
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True, indent=2))
    else:
        print(f"STATUS=ok quota_status={payload['quota_status']} effective_remaining_percent={payload['effective_remaining_percent']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
