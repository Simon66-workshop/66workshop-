#!/usr/bin/env python3
"""Turn self-review findings into structured reflection output."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from _shared import config_dir, load_json, now_iso


DEFAULT_DO_NOT_TOUCH = "Do not touch Hook Bridge, State Projector precedence, or LuckyCat UI runtime semantics in this phase."


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Reflect on self-review outcome")
    parser.add_argument("--auditors-json", required=True)
    parser.add_argument("--score-json", required=True)
    return parser


def main() -> None:
    args = build_parser().parse_args()
    auditors = load_json(Path(args.auditors_json), [])
    score = load_json(Path(args.score_json), {})
    taxonomy = load_json(config_dir() / "reflection-taxonomy.json", {})
    failures: list[dict[str, Any]] = []
    for auditor in auditors:
        for finding in auditor.get("findings") or []:
            if isinstance(finding, dict) and finding.get("failure_type"):
                failures.append(finding)

    items = []
    for finding in failures:
        failure_type = str(finding.get("failure_type"))
        meta = (taxonomy.get("failures") or {}).get(failure_type, {})
        items.append(
            {
                "failure_type": failure_type,
                "severity": meta.get("severity", "medium"),
                "summary": meta.get("summary", finding.get("message", failure_type)),
                "evidence": finding.get("evidence") or [],
                "root_cause": finding.get("root_cause") or finding.get("message") or "needs further triage",
                "next_bounded_action": finding.get("next_bounded_action") or "Collect tighter local evidence before changing state logic.",
                "do_not_touch_next": finding.get("do_not_touch_next") or DEFAULT_DO_NOT_TOUCH,
                "decision": finding.get("decision") or meta.get("default_decision") or score.get("decision", "NO_AUTO_APPLY"),
                "scope": finding.get("scope") or "in_scope",
            }
        )

    payload = {
        "schema_version": "0.1",
        "reflected_at": now_iso(),
        "decision": score.get("decision", "NO_AUTO_APPLY"),
        "items": items,
    }
    print(json.dumps(payload, ensure_ascii=True, sort_keys=True, indent=2))


if __name__ == "__main__":
    main()
