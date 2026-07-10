#!/usr/bin/env python3
"""Watch local Codex app-server quota updates and refresh quota_state.json.

This watcher is intentionally local-only. It talks to the Codex app-server stdio
transport, never reads auth/cookies/keychain, and falls back to bounded polling
when account/rateLimits/updated notifications are unavailable.
"""

from __future__ import annotations

import argparse
import json
import os
import select
import subprocess
import time
from pathlib import Path
from typing import Any

from codex_appserver_bridge import codex_bin, send_jsonrpc
from codex_quota_appserver_probe import preserve_existing_manual_resets, read_rate_limits
from codex_quota_import import (
    atomic_write_json,
    normalize_appserver_response,
    now_iso,
    preserve_last_known_good_appserver_quota,
    quota_state_path,
)


DEFAULT_STATE_DIR = Path.home() / ".66tasklight"
SCHEMA_VERSION = "0.2"


def state_dir() -> Path:
    return Path(os.environ.get("TASKLIGHT_STATE_DIR", str(DEFAULT_STATE_DIR))).expanduser()


def quota_probe_health_path(root: Path) -> Path:
    return Path(os.environ.get("TASKLIGHT_QUOTA_PROBE_HEALTH_PATH", str(root / "quota_probe_health.json"))).expanduser()


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return None


def event_name(event: dict[str, Any]) -> str:
    return str(event.get("method") or event.get("event") or event.get("type") or event.get("name") or "")


def event_payload(event: dict[str, Any]) -> dict[str, Any] | None:
    params = event.get("params") if isinstance(event.get("params"), dict) else event
    if not isinstance(params, dict):
        return None
    for key in ("result", "payload", "rateLimits", "rateLimitsByLimitId"):
        value = params.get(key)
        if isinstance(value, dict):
            if key in {"rateLimits", "rateLimitsByLimitId"}:
                return {key: value}
            return value
        if isinstance(value, list) and key == "rateLimits":
            return {"rateLimits": value}
    return params if "rateLimits" in params or "rateLimitsByLimitId" in params else None


def read_update_event(timeout: float) -> dict[str, Any] | None:
    binary = codex_bin()
    proc: subprocess.Popen[str] | None = None
    try:
        proc = subprocess.Popen(
            [binary, "app-server", "--listen", "stdio://"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
        )
        send_jsonrpc(
            proc,
            1,
            "initialize",
            {
                "clientInfo": {"name": "66tasklight-quota-watcher", "version": "0.2"},
                "capabilities": {"experimentalApi": True},
            },
        )
        deadline = time.time() + max(0.1, timeout)
        while time.time() < deadline:
            if proc.stdout is None or proc.stderr is None:
                break
            ready, _, _ = select.select([proc.stdout, proc.stderr], [], [], min(0.25, max(0, deadline - time.time())))
            for stream in ready:
                line = stream.readline()
                if not line or stream is proc.stderr:
                    continue
                try:
                    message = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if not isinstance(message, dict) or event_name(message) != "account/rateLimits/updated":
                    continue
                payload = event_payload(message)
                if isinstance(payload, dict):
                    return payload
    finally:
        if proc is not None:
            proc.terminate()
            try:
                proc.wait(timeout=1)
            except subprocess.TimeoutExpired:
                proc.kill()
    return None


def fixture_payload(path: Path) -> dict[str, Any]:
    raw = load_json(path)
    if not isinstance(raw, dict):
        raise RuntimeError(f"invalid quota watcher fixture: {path}")
    if event_name(raw) == "account/rateLimits/updated":
        payload = event_payload(raw)
        if isinstance(payload, dict):
            return payload
    return raw


def write_health(path: Path, payload: dict[str, Any]) -> None:
    atomic_write_json(path, payload)


def run_once(args: argparse.Namespace, root: Path) -> dict[str, Any]:
    output = Path(args.output).expanduser() if args.output else quota_state_path(root)
    health_path = Path(args.health).expanduser() if args.health else quota_probe_health_path(root)
    mode = "event"
    last_event_at = None
    last_error = None
    previous_health = load_json(health_path)
    try:
        if args.fixture:
            result = fixture_payload(Path(args.fixture).expanduser())
            mode = "event_fixture"
            last_event_at = now_iso()
        else:
            result = read_update_event(args.event_timeout)
            if result is not None:
                last_event_at = now_iso()
            else:
                mode = "poll_fallback"
                result = read_rate_limits(args.timeout)
        quota_payload = preserve_existing_manual_resets(normalize_appserver_response(result), output)
        quota_payload = preserve_last_known_good_appserver_quota(quota_payload, output)
        atomic_write_json(output, quota_payload)
        fresh = quota_payload.get("fresh") is True
        health = {
            "schema_version": SCHEMA_VERSION,
            "status": "ok" if fresh else "degraded",
            "source": "codex_appserver",
            "mode": mode,
            "last_event_at": last_event_at,
            "last_probe_at": now_iso(),
            "quota_status": quota_payload.get("quota_status"),
            "effective_remaining_percent": quota_payload.get("effective_remaining_percent"),
            "compatibility_status": quota_payload.get("source_schema_status", "unknown"),
            "fallback_active": not fresh,
            "last_success_at": now_iso() if fresh else (previous_health.get("last_success_at") if isinstance(previous_health, dict) else None),
            "last_error": None if fresh else ",".join(quota_payload.get("warnings") or [])[:240],
            "updated_at": now_iso(),
        }
    except Exception as exc:
        last_error = str(exc)[:240]
        fallback_payload = preserve_last_known_good_appserver_quota(
            normalize_appserver_response({}),
            output,
            "appserver_probe_error_cached_snapshot",
        )
        if fallback_payload.get("source") == "codex_appserver_cached":
            atomic_write_json(output, fallback_payload)
            health = {
                "schema_version": SCHEMA_VERSION,
                "status": "degraded",
                "source": "codex_appserver",
                "mode": mode,
                "last_event_at": last_event_at,
                "last_probe_at": now_iso(),
                "quota_status": fallback_payload.get("quota_status"),
                "effective_remaining_percent": fallback_payload.get("effective_remaining_percent"),
                "compatibility_status": "degraded",
                "fallback_active": True,
                "last_success_at": previous_health.get("last_success_at") if isinstance(previous_health, dict) else None,
                "last_error": last_error,
                "updated_at": now_iso(),
            }
            write_health(health_path, health)
            return health
        health = {
            "schema_version": SCHEMA_VERSION,
            "status": "error",
            "source": "codex_appserver",
            "mode": mode,
            "last_event_at": last_event_at,
            "last_probe_at": now_iso(),
            "quota_status": "unknown",
            "effective_remaining_percent": None,
            "compatibility_status": "error",
            "fallback_active": False,
            "last_success_at": previous_health.get("last_success_at") if isinstance(previous_health, dict) else None,
            "last_error": last_error,
            "updated_at": now_iso(),
        }
        write_health(health_path, health)
        raise
    write_health(health_path, health)
    return health


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Watch local Codex quota updates")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--once", action="store_true")
    mode.add_argument("--watch", action="store_true")
    parser.add_argument("--output")
    parser.add_argument("--health")
    parser.add_argument("--fixture")
    parser.add_argument("--timeout", type=float, default=float(os.environ.get("TASKLIGHT_QUOTA_AUTOPROBE_TIMEOUT_SECONDS", "2")))
    parser.add_argument("--event-timeout", type=float, default=float(os.environ.get("TASKLIGHT_QUOTA_WATCH_EVENT_TIMEOUT_SECONDS", "1.5")))
    parser.add_argument("--poll-seconds", type=float, default=float(os.environ.get("TASKLIGHT_QUOTA_WATCH_POLL_SECONDS", "30")))
    parser.add_argument("--print-json", action="store_true")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    root = state_dir()
    root.mkdir(parents=True, exist_ok=True)
    if args.once:
        payload = run_once(args, root)
        if args.print_json:
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True, indent=2))
        else:
            print(f"STATUS={payload.get('status')} mode={payload.get('mode')} quota_status={payload.get('quota_status')} effective_remaining_percent={payload.get('effective_remaining_percent')}")
        return 0
    while True:
        try:
            run_once(args, root)
        except Exception:
            pass
        time.sleep(max(2.0, args.poll_seconds))


if __name__ == "__main__":
    raise SystemExit(main())
