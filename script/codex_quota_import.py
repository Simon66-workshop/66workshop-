#!/usr/bin/env python3
"""Import sanitized Codex quota text into quota_state.json."""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import subprocess
import tempfile
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Any


SCHEMA_VERSION = "0.2"
DEFAULT_STATE_DIR = Path.home() / ".66tasklight"
WINDOW_RE = re.compile(
    r"(?P<label>\d+\s*(?:分钟|小时|天|周))\s+(?P<percent>\d{1,3})%\s*(?P<reset>(?:\d{1,2}:\d{2})|(?:\d{1,2}月\d{1,2}日))?"
)
RESET_RE = re.compile(r"(?P<count>\d+)\s*次\s*可用\s*重置")
RESET_CREDIT_STATUSES = {"available", "redeemed", "redeeming", "expired", "used"}


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


def remaining_percent_from_used(value: Any) -> tuple[int, int] | None:
    """Normalize AppServer usage using the same integer the client presents.

    Some AppServer builds return a fractional ``usedPercent``. Rounding that
    number first can produce a one-point disagreement with the visible
    remaining quota. Round the remaining value once, then derive the paired
    used value so both fields always add up to one hundred.
    """
    try:
        used = float(value)
    except (TypeError, ValueError):
        return None
    remaining = int(math.floor(max(0.0, min(100.0, 100.0 - used)) + 0.5))
    remaining = max(0, min(100, remaining))
    return remaining, 100 - remaining


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


def parse_date_like(value: Any) -> str | None:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        try:
            return datetime.fromtimestamp(float(value), tz=datetime.now().astimezone().tzinfo).date().isoformat()
        except (OverflowError, OSError, ValueError):
            return None
    text = str(value).strip()
    if not text:
        return None
    match = re.match(r"^(?P<date>\d{4}-\d{2}-\d{2})", text)
    if match:
        return match.group("date")
    try:
        return datetime.fromisoformat(text.replace("Z", "+00:00")).astimezone().date().isoformat()
    except ValueError:
        return text


def parse_datetime_like(value: Any) -> str | None:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        try:
            return datetime.fromtimestamp(float(value), tz=datetime.now().astimezone().tzinfo).replace(microsecond=0).isoformat()
        except (OverflowError, OSError, ValueError):
            return None
    text = str(value).strip()
    if not text:
        return None
    if re.match(r"^\d{4}-\d{2}-\d{2}$", text):
        return text
    try:
        return datetime.fromisoformat(text.replace("Z", "+00:00")).astimezone().replace(microsecond=0).isoformat()
    except ValueError:
        return parse_date_like(text)


def normalize_redeemed(value: Any, status: str | None = None) -> bool | None:
    if isinstance(value, bool):
        return value
    if value is None:
        lowered = (status or "").lower()
        if lowered in {"redeemed", "used"}:
            return True
        if lowered in {"available", "expired"}:
            return False
        return None
    lowered = str(value).strip().lower()
    if lowered in {"yes", "y", "true", "1", "redeemed", "used"}:
        return True
    if lowered in {"no", "n", "false", "0", "available", "unredeemed"}:
        return False
    return None


def normalize_reset_credit(raw: dict[str, Any], index: int = 0) -> dict[str, Any]:
    status = str(raw.get("status") or raw.get("state") or ("redeemed" if raw.get("redeemed") else "available")).strip().lower()
    issued_source = (
        raw.get("issued_date")
        or raw.get("issuedAt")
        or raw.get("issued_at")
        or raw.get("grantedAt")
        or raw.get("granted_at")
        or raw.get("createdAt")
        or raw.get("created_at")
    )
    issued_at = parse_datetime_like(issued_source)
    issued = parse_date_like(issued_source)
    expiry_source = (
        raw.get("expiry_date")
        or raw.get("expiresAt")
        or raw.get("expires_at")
        or raw.get("expiryAt")
        or raw.get("expiry_at")
        or raw.get("expiration")
        or raw.get("expiredAt")
        or raw.get("expired_at")
    )
    expires_at = parse_datetime_like(expiry_source)
    expiry = parse_date_like(expiry_source)
    redeemed = normalize_redeemed(
        raw.get("redeemed")
        if raw.get("redeemed") is not None
        else raw.get("is_redeemed")
        if raw.get("is_redeemed") is not None
        else raw.get("redeemed_at"),
        status,
    )
    return {
        "id": raw.get("id") or raw.get("creditId") or f"reset_credit_{index + 1}",
        "status": status,
        "issued_at": issued_at,
        "issued_date": issued,
        "expires_at": expires_at,
        "expiry_date": expiry,
        "redeemed": redeemed,
        "reset_type": raw.get("resetType") or raw.get("reset_type") or raw.get("type"),
    }


def parse_normalized_datetime(value: Any) -> datetime | None:
    text = parse_datetime_like(value)
    if not text:
        return None
    try:
        parsed = datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        parsed_date = parse_normalized_date(text)
        if parsed_date is None:
            return None
        return datetime.combine(parsed_date, datetime.max.time()).astimezone()
    if parsed.tzinfo is None:
        parsed = parsed.astimezone()
    return parsed.astimezone()


def parse_normalized_date(value: Any) -> date | None:
    text = parse_date_like(value)
    if not text:
        return None
    try:
        return date.fromisoformat(text[:10])
    except ValueError:
        return None


def reset_credit_is_used(credit: dict[str, Any]) -> bool:
    status = str(credit.get("status") or "").lower()
    return credit.get("redeemed") is True or status in {"redeemed", "used", "claimed"}


def reset_credit_is_expired(credit: dict[str, Any], today: date | None = None) -> bool:
    if reset_credit_is_used(credit):
        return False
    expiry_dt = parse_normalized_datetime(credit.get("expires_at") or credit.get("expiry_date") or credit.get("expiresAt") or credit.get("expires_at"))
    if expiry_dt is not None:
        return expiry_dt <= datetime.now().astimezone()
    expiry_date = parse_normalized_date(credit.get("expiry_date") or credit.get("expiresAt") or credit.get("expires_at"))
    if expiry_date is None:
        return False
    return expiry_date <= (today or datetime.now().astimezone().date())


def reset_credit_is_available(credit: dict[str, Any], today: date | None = None) -> bool:
    status = str(credit.get("status") or "").lower()
    if status != "available" or credit.get("redeemed") is True:
        return False
    expiry_dt = parse_normalized_datetime(credit.get("expires_at") or credit.get("expiry_date") or credit.get("expiresAt") or credit.get("expires_at"))
    if expiry_dt is not None:
        return expiry_dt > datetime.now().astimezone()
    expiry_date = parse_normalized_date(credit.get("expiry_date") or credit.get("expiresAt") or credit.get("expires_at"))
    return expiry_date is None or expiry_date > (today or datetime.now().astimezone().date())


def derive_reset_credit_summary(credits: list[dict[str, Any]], today: date | None = None) -> dict[str, Any]:
    today = today or datetime.now().astimezone().date()
    available = [credit for credit in credits if reset_credit_is_available(credit, today)]
    used_count = sum(1 for credit in credits if reset_credit_is_used(credit))
    expired_count = sum(1 for credit in credits if reset_credit_is_expired(credit, today))
    expiring = sorted(
        (
            (
                parse_normalized_datetime(credit.get("expires_at") or credit.get("expiry_date")),
                credit.get("expires_at") or credit.get("expiry_date"),
            )
            for credit in available
            if parse_normalized_datetime(credit.get("expires_at") or credit.get("expiry_date")) is not None
        ),
        key=lambda item: item[0] or datetime.max.replace(tzinfo=datetime.now().astimezone().tzinfo),
    )
    return {
        "total_count": len(credits),
        "available_count": len(available),
        "used_count": used_count,
        "expired_count": expired_count,
        "next_expiry": expiring[0][1] if expiring else None,
    }


def available_reset_credit_count(credits: list[dict[str, Any]]) -> int:
    return int(derive_reset_credit_summary(credits)["available_count"])


def coerce_reset_credit_items(raw: Any) -> list[dict[str, Any]]:
    if isinstance(raw, list):
        return [item for item in raw if isinstance(item, dict)]
    if not isinstance(raw, dict):
        return []
    for key in ("credits", "items", "data", "results", "rateLimitResetCredits", "resetCredits", "reset_credits"):
        value = raw.get(key)
        if isinstance(value, list):
            return [item for item in value if isinstance(item, dict)]
    return []


def parse_reset_credit_table(text: str) -> list[dict[str, Any]]:
    credits: list[dict[str, Any]] = []
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped.startswith("|") or "---" in stripped:
            continue
        cells = [cell.strip().strip("`") for cell in stripped.strip("|").split("|")]
        if len(cells) < 4:
            continue
        status = cells[0].lower()
        if status not in RESET_CREDIT_STATUSES:
            continue
        credits.append(
            normalize_reset_credit(
                {
                    "status": status,
                    "issued_date": cells[1],
                    "expiry_date": cells[2],
                    "redeemed": cells[3],
                },
                index=len(credits),
            )
        )
    return credits


def normalize_reset_credits_payload(raw: Any) -> dict[str, Any]:
    if not isinstance(raw, (dict, list)):
        return {
            "available_count": None,
            "label": None,
            "total_count": None,
            "used_count": None,
            "expired_count": None,
            "next_expiry": None,
            "credits": [],
            "detail_count": 0,
        }
    raw_dict = raw if isinstance(raw, dict) else {"credits": raw}
    raw_credits = coerce_reset_credit_items(raw)
    credits = [
        normalize_reset_credit(item, index)
        for index, item in enumerate(raw_credits or [])
        if isinstance(item, dict)
    ]
    summary = derive_reset_credit_summary(credits)
    explicit_count = raw_dict.get("availableCount")
    if explicit_count is None:
        explicit_count = raw_dict.get("available_count")
    try:
        available_count = int(explicit_count) if explicit_count is not None else summary["available_count"]
    except (TypeError, ValueError):
        available_count = summary["available_count"] if credits else None
    total_count = raw_dict.get("totalCount", raw_dict.get("total_count", summary["total_count"]))
    used_count = raw_dict.get("usedCount", raw_dict.get("used_count", summary["used_count"]))
    expired_count = raw_dict.get("expiredCount", raw_dict.get("expired_count", summary["expired_count"]))
    next_expiry = raw_dict.get("nextExpiry", raw_dict.get("next_expiry", summary["next_expiry"]))
    return {
        "available_count": available_count,
        "label": f"{available_count}次可用重置" if available_count is not None else None,
        "total_count": total_count,
        "used_count": used_count,
        "expired_count": expired_count,
        "next_expiry": next_expiry,
        "credits": credits,
        "detail_count": len(credits),
    }


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
        "manual_resets": manual_resets or {"available_count": None, "label": None, "credits": []},
        "effective_remaining_percent": effective,
        "recommendation": recommendation_for_status(quota_status),
        "warnings": merged_warnings,
    }


def appserver_quota_payload_usable(payload: Any) -> bool:
    if not isinstance(payload, dict) or payload.get("fresh") is not True:
        return False
    windows = payload.get("display_windows")
    if not isinstance(windows, list) or not windows:
        return False
    for window in windows:
        if not isinstance(window, dict):
            return False
        percent = window.get("remaining_percent")
        if not isinstance(percent, int) or percent < 0 or percent > 100:
            return False
    return isinstance(payload.get("effective_remaining_percent"), int)


def appserver_unusable_reason(payload: dict[str, Any]) -> str:
    schema_status = str(payload.get("source_schema_status") or "")
    if schema_status != "supported":
        return "appserver_schema_changed"
    return "appserver_no_usable_codex_quota"


def preserve_last_known_good_appserver_quota(payload: dict[str, Any], output: Path, reason: str | None = None) -> dict[str, Any]:
    """Fail closed while retaining a visibly stale local-only quota snapshot.

    App-server response shapes can change during ChatGPT Work upgrades. Never
    replace a valid local snapshot with an empty or unrecognized response, and
    never label cached values as fresh.
    """
    if appserver_quota_payload_usable(payload):
        return payload
    try:
        existing = json.loads(output.read_text(encoding="utf-8"))
    except (FileNotFoundError, OSError, json.JSONDecodeError):
        return payload
    if not isinstance(existing, dict) or str(existing.get("source") or "") not in {"codex_appserver", "codex_appserver_cached"}:
        return payload
    if not appserver_quota_payload_usable({**existing, "fresh": True}):
        return payload
    cached = dict(existing)
    cached["source"] = "codex_appserver_cached"
    cached["source_confidence"] = min(float(existing.get("source_confidence") or 0.95), 0.25)
    cached["fresh"] = False
    cached["source_schema_status"] = "degraded"
    cached["last_source_check_at"] = now_iso()
    warnings = [item for item in existing.get("warnings", []) if isinstance(item, str)]
    warning = reason or appserver_unusable_reason(payload)
    if warning not in warnings:
        warnings.append(warning)
    cached["warnings"] = warnings
    return cached


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
    manual_resets = normalize_reset_credits_payload(None)
    reset_credits = parse_reset_credit_table(text)
    if reset_match:
        count = int(reset_match.group("count"))
        manual_resets = {"available_count": count, "label": f"{count}次可用重置"}
    elif reset_credits:
        count = available_reset_credit_count(reset_credits)
        manual_resets = {"available_count": count, "label": f"{count}次可用重置"}
    if reset_credits:
        manual_resets = normalize_reset_credits_payload({"credits": reset_credits, **manual_resets})
    return build_quota_state(source=source, source_confidence=0.85, windows=windows, manual_resets=manual_resets, warnings=warnings)


def normalize_appserver_response(result: dict[str, Any]) -> dict[str, Any]:
    raw_buckets = result.get("rateLimitsByLimitId")
    if isinstance(raw_buckets, dict):
        buckets = list(raw_buckets.values())
        schema = "rate_limits_by_limit_id"
    else:
        buckets = result.get("rateLimits") if isinstance(result.get("rateLimits"), list) else []
        schema = "rate_limits_list" if isinstance(result.get("rateLimits"), list) else "unrecognized"
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
            normalized_usage = remaining_percent_from_used(window.get("usedPercent"))
            if normalized_usage is None:
                continue
            remaining, used_percent = normalized_usage
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
            "fresh": False,
            "quota_status": "unknown",
            "raw_windows": [],
            "display_windows": [],
            "windows": [],
            "manual_resets": normalize_reset_credits_payload(None),
            "effective_remaining_percent": None,
            "recommendation": "normal",
            "warnings": ["appserver_schema_unrecognized" if schema == "unrecognized" else "no_codex_bucket"],
            "source_schema": schema,
            "source_schema_status": "unrecognized" if schema == "unrecognized" else "supported",
        }
    payload = build_quota_state(
        source="codex_appserver",
        source_confidence=0.95 if windows else 0.0,
        windows=windows,
        manual_resets=normalize_reset_credits_payload(
            result.get("rateLimitResetCredits")
            if result.get("rateLimitResetCredits") is not None
            else result.get("resetCredits")
            if result.get("resetCredits") is not None
            else result.get("reset_credits")
        ),
        warnings=warnings,
    )
    payload["source_schema"] = schema
    payload["source_schema_status"] = "supported"
    return payload


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
