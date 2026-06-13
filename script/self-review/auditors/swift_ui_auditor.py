#!/usr/bin/env python3
"""Audit Swift UI read-model contract."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from _shared import load_json, now_iso, project_root  # noqa: E402


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Audit Swift UI contract")
    parser.add_argument("--baseline-json", required=True)
    parser.add_argument("--evidence-json", required=True)
    parser.add_argument("--task-type", nargs="*", default=[])
    return parser


def main() -> None:
    args = build_parser().parse_args()
    store_path = project_root() / "mac" / "66TaskLight" / "Sources" / "TaskLightCore" / "TaskLightStore.swift"
    schema_path = project_root() / "docs" / "algorithms" / "UI_STATE_SCHEMA.md"
    store_text = store_path.read_text(encoding="utf-8")
    schema_text = schema_path.read_text(encoding="utf-8")
    ui_state_first = "loadProjectedUIState" in store_text and "Read `ui_state.json` first." in schema_text
    findings = []
    if not ui_state_first:
        findings.append(
            {
                "failure_type": "fallback_leak",
                "message": "Swift UI ui_state-first contract is unclear",
                "evidence": [str(store_path), str(schema_path)],
                "root_cause": "ui_state-first contract is missing from code or docs",
                "next_bounded_action": "reconfirm ui_state-first read path before accepting UI semantics",
                "decision": "CONDITIONAL_PASS",
            }
        )
    payload = {
        "auditor_id": "swift_ui_auditor",
        "checked_at": now_iso(),
        "summary": {"ui_state_first": ui_state_first},
        "findings": findings,
    }
    print(json.dumps(payload, ensure_ascii=True, sort_keys=True, indent=2))


if __name__ == "__main__":
    main()
