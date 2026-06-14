#!/usr/bin/env python3
"""Read Codex quota buckets from the local app-server and write quota_state.json."""

from __future__ import annotations

import argparse
import json
import select
import subprocess
import time
from pathlib import Path

from codex_appserver_bridge import codex_bin, send_jsonrpc
from codex_quota_import import atomic_write_json, normalize_appserver_response, quota_state_path


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


def main() -> int:
    parser = argparse.ArgumentParser(description="Probe local Codex app-server quota buckets")
    parser.add_argument("--timeout", type=float, default=3.0)
    parser.add_argument("--output")
    parser.add_argument("--print-json", action="store_true")
    args = parser.parse_args()

    payload = normalize_appserver_response(read_rate_limits(args.timeout))
    output = Path(args.output).expanduser() if args.output else quota_state_path()
    atomic_write_json(output, payload)
    if args.print_json:
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True, indent=2))
    else:
        print(f"STATUS=ok quota_status={payload['quota_status']} effective_remaining_percent={payload['effective_remaining_percent']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
