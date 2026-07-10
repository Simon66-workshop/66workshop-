#!/usr/bin/env python3
"""Import sanitized reset-credit fixtures without credentials or network access."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
from typing import Any

from codex_quota_import import (
    SCHEMA_VERSION,
    atomic_write_json,
    normalize_reset_credits_payload,
    now_iso,
    quota_state_path,
)

def normalize_response(raw: Any) -> dict[str, Any]:
    if isinstance(raw, list):
        return normalize_reset_credits_payload({"credits": raw})
    if not isinstance(raw, dict):
        return normalize_reset_credits_payload(None)
    for key in ("rateLimitResetCredits", "resetCredits", "reset_credits", "credits", "items", "data", "results"):
        value = raw.get(key)
        if isinstance(value, list):
            return normalize_reset_credits_payload({"credits": value})
    return normalize_reset_credits_payload(raw)


def existing_quota_state(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    return payload if isinstance(payload, dict) else {}


def merge_reset_payload(existing: dict[str, Any], resets: dict[str, Any], *, source: str) -> dict[str, Any]:
    warnings = existing.get("warnings") if isinstance(existing.get("warnings"), list) else []
    merged_warnings = list(warnings)
    windows = existing.get("display_windows") if isinstance(existing.get("display_windows"), list) else []
    if not windows and "reset_credits_probe_only_no_quota_windows" not in merged_warnings:
        merged_warnings.append("reset_credits_probe_only_no_quota_windows")
    return {
        "schema_version": existing.get("schema_version") or SCHEMA_VERSION,
        "source": existing.get("source") or source,
        "source_confidence": existing.get("source_confidence", 0.8),
        "captured_at": now_iso(),
        "fresh": True,
        "quota_status": existing.get("quota_status") or "unknown",
        "raw_windows": existing.get("raw_windows") if isinstance(existing.get("raw_windows"), list) else [],
        "display_windows": windows,
        "windows": existing.get("windows") if isinstance(existing.get("windows"), list) else windows,
        "manual_resets": resets,
        "effective_remaining_percent": existing.get("effective_remaining_percent"),
        "recommendation": existing.get("recommendation") or "normal",
        "warnings": merged_warnings,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Import a sanitized reset-credit fixture without credentials or network access")
    parser.add_argument("--output")
    parser.add_argument("--fixture", required=True, help="Read a sanitized local fixture")
    parser.add_argument("--print-json", action="store_true", help="Print sanitized quota state only")
    args = parser.parse_args()

    output = Path(args.output).expanduser() if args.output else quota_state_path()
    source = "codex_reset_credits_fixture"
    try:
        raw = json.loads(Path(args.fixture).expanduser().read_text(encoding="utf-8"))
        resets = normalize_response(raw)
        payload = merge_reset_payload(existing_quota_state(output), resets, source=source)
        atomic_write_json(output, payload)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"STATUS=error reason={type(exc).__name__}")
        return 1

    if args.print_json:
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True, indent=2))
    else:
        total = resets.get("total_count")
        available = resets.get("available_count")
        next_expiry = resets.get("next_expiry") or "unknown"
        print(f"STATUS=ok available_count={available} total_count={total} next_expiry={next_expiry}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
