#!/usr/bin/env python3
"""Audit self-review docs and config presence."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from _shared import config_dir, load_json, now_iso, project_root, self_review_docs_dir  # noqa: E402


REQUIRED_DOCS = [
    "66TASKLIGHT_SELF_REVIEW_ENGINE.md",
    "66TASKLIGHT_REVIEW_MATRIX.md",
    "66TASKLIGHT_FAILURE_TAXONOMY.md",
    "66TASKLIGHT_TASK_TEMPLATE.md",
]

REQUIRED_CONFIGS = [
    "global-safety-boundary.json",
    "task-type-registry.json",
    "scoring-rubrics.json",
    "reflection-taxonomy.json",
    "evidence-requirements.json",
    "iteration-policy.json",
    "human-review-policy.json",
]


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Audit self-review docs consistency")
    parser.add_argument("--baseline-json", required=True)
    parser.add_argument("--evidence-json", required=True)
    parser.add_argument("--task-type", nargs="*", default=[])
    return parser


def main() -> None:
    args = build_parser().parse_args()
    docs_present = all((self_review_docs_dir() / name).exists() for name in REQUIRED_DOCS)
    config_present = all((config_dir() / name).exists() for name in REQUIRED_CONFIGS)
    findings = []
    if not docs_present or not config_present:
        findings.append(
            {
                "failure_type": "missing_evidence",
                "message": "self-review docs or config files are missing",
                "evidence": REQUIRED_DOCS + REQUIRED_CONFIGS,
                "root_cause": "review surface is incomplete",
                "next_bounded_action": "restore the missing self-review doc or config files before acceptance",
                "decision": "REJECT",
            }
        )
    payload = {
        "auditor_id": "docs_consistency_auditor",
        "checked_at": now_iso(),
        "summary": {
            "docs_present": docs_present,
            "config_present": config_present,
        },
        "findings": findings,
    }
    print(json.dumps(payload, ensure_ascii=True, sort_keys=True, indent=2))


if __name__ == "__main__":
    main()
