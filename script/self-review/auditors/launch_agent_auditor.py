#!/usr/bin/env python3
"""Audit LaunchAgent and trust change scope."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from _shared import load_json, now_iso  # noqa: E402


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Audit LaunchAgent change scope")
    parser.add_argument("--baseline-json", required=True)
    parser.add_argument("--evidence-json", required=True)
    parser.add_argument("--task-type", nargs="*", default=[])
    return parser


def main() -> None:
    args = build_parser().parse_args()
    baseline = load_json(Path(args.baseline_json), {})
    changed = [str(path) for path in (((baseline.get("git") or {}).get("changed_files")) or [])]
    hits = [path for path in changed if any(token in path for token in ("launch_agent", "LaunchAgent", "hooks_trust", ".plist"))]
    findings = []
    if hits:
        findings.append(
            {
                "failure_type": "launch_agent_unhealthy",
                "message": "launch or trust surface changed in this review scope",
                "evidence": hits,
                "root_cause": "resident process or trust surface changed",
                "next_bounded_action": "keep human review on this task even if smoke evidence passes",
                "decision": "NEEDS_HUMAN_REVIEW",
            }
        )
    payload = {
        "auditor_id": "launch_agent_auditor",
        "checked_at": now_iso(),
        "summary": {"changed_files": hits, "needs_human_review": bool(hits)},
        "findings": findings,
    }
    print(json.dumps(payload, ensure_ascii=True, sort_keys=True, indent=2))


if __name__ == "__main__":
    main()
