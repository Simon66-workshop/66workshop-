#!/usr/bin/env python3
"""Audit hook bridge health evidence."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from _shared import load_json, now_iso  # noqa: E402


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Audit hook bridge evidence")
    parser.add_argument("--baseline-json", required=True)
    parser.add_argument("--evidence-json", required=True)
    parser.add_argument("--task-type", nargs="*", default=[])
    return parser


def main() -> None:
    args = build_parser().parse_args()
    evidence = load_json(Path(args.evidence_json), {})
    required = evidence.get("required_commands") if isinstance(evidence.get("required_commands"), dict) else {}
    check = required.get("check_hook_bridge_launch_agent") if isinstance(required.get("check_hook_bridge_launch_agent"), dict) else {}
    key_values = check.get("key_values") if isinstance(check.get("key_values"), dict) else {}
    status = str(key_values.get("STATUS") or ("ok" if check.get("passed") else "unknown"))
    findings = []
    if status not in {"ok", "unknown"}:
        findings.append(
            {
                "failure_type": "launch_agent_unhealthy",
                "message": f"hook bridge launch status is {status}",
                "evidence": [f"check_hook_bridge_launch_agent.STATUS={status}"],
                "root_cause": "resident bridge health is not clean",
                "next_bounded_action": "repair LaunchAgent residency before claiming stable runtime truth",
                "decision": "NEEDS_HUMAN_REVIEW",
            }
        )
    payload = {
        "auditor_id": "hook_bridge_auditor",
        "checked_at": now_iso(),
        "summary": {
            "launch_status": status,
            "launch_status_ok": status == "ok",
        },
        "findings": findings,
    }
    print(json.dumps(payload, ensure_ascii=True, sort_keys=True, indent=2))


if __name__ == "__main__":
    main()
