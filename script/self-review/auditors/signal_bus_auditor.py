#!/usr/bin/env python3
"""Audit signal bus hygiene."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from _shared import load_json, now_iso  # noqa: E402


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Audit signal bus hygiene")
    parser.add_argument("--baseline-json", required=True)
    parser.add_argument("--evidence-json", required=True)
    parser.add_argument("--task-type", nargs="*", default=[])
    return parser


def main() -> None:
    args = build_parser().parse_args()
    baseline = load_json(Path(args.baseline_json), {})
    signals = baseline.get("signal_bus_summary") if isinstance(baseline.get("signal_bus_summary"), dict) else {}
    record_count = int(signals.get("record_count") or 0)
    recent_sources = set(signals.get("recent_source_set") or [])
    findings = []
    if record_count == 0:
        findings.append(
            {
                "failure_type": "missing_evidence",
                "message": "signal bus has no recent records",
                "evidence": ["signal_bus_summary.record_count=0"],
                "root_cause": "runtime evidence path is empty",
                "next_bounded_action": "collect fresh local signal bus evidence before accepting runtime claims",
                "decision": "REJECT",
            }
        )
    elif recent_sources == {"unknown"}:
        findings.append(
            {
                "failure_type": "signal_bus_pollution",
                "message": "signal bus is dominated by unknown source records",
                "evidence": ["signal_bus_summary.recent_source_set=unknown"],
                "root_cause": "sanitized signal classification is too weak",
                "next_bounded_action": "inspect signal normalization before broadening projector precedence",
                "decision": "CONDITIONAL_PASS",
            }
        )
    payload = {
        "auditor_id": "signal_bus_auditor",
        "checked_at": now_iso(),
        "summary": {
            "record_count": record_count,
            "recent_source_set": sorted(recent_sources),
            "good_signal_hygiene": record_count > 0 and recent_sources != {"unknown"},
        },
        "findings": findings,
    }
    print(json.dumps(payload, ensure_ascii=True, sort_keys=True, indent=2))


if __name__ == "__main__":
    main()
