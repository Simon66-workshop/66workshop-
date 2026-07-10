#!/usr/bin/env python3
"""Read Codex quota buckets from the local app-server and write quota_state.json."""

from __future__ import annotations

import argparse
import json
import select
import subprocess
import time
from pathlib import Path
from typing import Any

from codex_appserver_bridge import codex_bin, send_jsonrpc
from codex_quota_import import atomic_write_json, normalize_appserver_response, preserve_last_known_good_appserver_quota, quota_state_path


def read_rate_limits(timeout: float) -> dict:
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
                "clientInfo": {"name": "66tasklight-quota-probe", "version": "0.1"},
                "capabilities": {"experimentalApi": True},
            },
        )
        send_jsonrpc(proc, 2, "account/rateLimits/read", {})
        deadline = time.time() + max(1.0, timeout)
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
                if isinstance(message, dict) and message.get("id") == 2:
                    result = message.get("result")
                    if isinstance(result, dict):
                        return result
                    raise RuntimeError("account/rateLimits/read returned no result")
    finally:
        if proc is not None:
            proc.terminate()
            try:
                proc.wait(timeout=1)
            except subprocess.TimeoutExpired:
                proc.kill()
    raise RuntimeError("account/rateLimits/read timed out")


def reset_payload_has_details(resets: Any) -> bool:
    if not isinstance(resets, dict):
        return False
    credits = resets.get("credits")
    detail_count = resets.get("detail_count")
    try:
        parsed_detail_count = int(detail_count) if detail_count is not None else 0
    except (TypeError, ValueError):
        parsed_detail_count = 0
    try:
        total_count = int(resets.get("total_count")) if resets.get("total_count") is not None else 0
    except (TypeError, ValueError):
        total_count = 0
    return bool(credits) or parsed_detail_count > 0 or bool(resets.get("next_expiry")) or total_count > 0


def preserve_existing_manual_resets(payload: dict[str, Any], output: Path) -> dict[str, Any]:
    if reset_payload_has_details(payload.get("manual_resets")):
        return payload
    try:
        existing = json.loads(output.read_text(encoding="utf-8"))
    except (FileNotFoundError, OSError, json.JSONDecodeError):
        return payload
    if not isinstance(existing, dict):
        return payload
    existing_resets = existing.get("manual_resets")
    if reset_payload_has_details(existing_resets):
        payload = dict(payload)
        payload["manual_resets"] = existing_resets
    return payload


def main() -> int:
    parser = argparse.ArgumentParser(description="Probe local Codex app-server quota buckets")
    parser.add_argument("--timeout", type=float, default=3.0)
    parser.add_argument("--output")
    parser.add_argument("--print-json", action="store_true")
    args = parser.parse_args()

    output = Path(args.output).expanduser() if args.output else quota_state_path()
    payload = preserve_existing_manual_resets(normalize_appserver_response(read_rate_limits(args.timeout)), output)
    payload = preserve_last_known_good_appserver_quota(payload, output)
    atomic_write_json(output, payload)
    if args.print_json:
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True, indent=2))
    else:
        print(f"STATUS=ok quota_status={payload['quota_status']} effective_remaining_percent={payload['effective_remaining_percent']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
