#!/usr/bin/env python3
"""Run the 66TaskLight Self-Review Arbiter Phase 1."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

from _shared import atomic_write_json, now_iso, project_root, report_directory


AUDITORS = [
    "git_diff_auditor",
    "state_projector_auditor",
    "hook_bridge_auditor",
    "launch_agent_auditor",
    "swift_ui_auditor",
    "signal_bus_auditor",
    "docs_consistency_auditor",
]


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Run 66TaskLight Self-Review Arbiter")
    parser.add_argument("--task-id", required=True)
    parser.add_argument("--task-type", dest="task_types", action="append", default=[])
    parser.add_argument("--scope-file")
    parser.add_argument("--review-path", dest="review_paths", action="append", default=[])
    parser.add_argument("--exclude-path", dest="exclude_paths", action="append", default=[])
    parser.add_argument("--evidence-profile", choices=["fast", "full", "release"], default="full")
    parser.add_argument("--mode", choices=["final"], default="final")
    return parser


def run_json(argv: list[str]) -> Any:
    completed = subprocess.run(argv, cwd=str(project_root()), text=True, capture_output=True, check=False)
    if completed.returncode != 0:
        raise SystemExit(completed.stderr.strip() or completed.stdout.strip() or f"command failed: {' '.join(argv)}")
    try:
        return json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"invalid json from {' '.join(argv)}: {exc}") from exc


def main() -> None:
    args = build_parser().parse_args()
    script_root = Path(__file__).resolve().parent
    with tempfile.TemporaryDirectory(prefix="tasklight-self-review-") as temp_dir:
        temp_root = Path(temp_dir)
        baseline_path = temp_root / "baseline.json"
        evidence_path = temp_root / "evidence.json"
        auditors_path = temp_root / "auditors.json"
        safety_path = temp_root / "safety.json"
        score_path = temp_root / "score.json"
        reflection_path = temp_root / "reflection.json"

        task_type_args = [arg for item in args.task_types for arg in ("--task-type", item)]
        scope_args = []
        if args.scope_file:
            scope_args.extend(["--scope-file", args.scope_file])
        for item in args.review_paths:
            scope_args.extend(["--review-path", item])
        for item in args.exclude_paths:
            scope_args.extend(["--exclude-path", item])

        baseline = run_json([sys.executable, str(script_root / "collect_baseline.py"), "--task-id", args.task_id, *task_type_args, *scope_args])
        atomic_write_json(baseline_path, baseline)

        evidence = run_json(
            [
                sys.executable,
                str(script_root / "collect_evidence.py"),
                "--task-id",
                args.task_id,
                "--evidence-profile",
                args.evidence_profile,
                *task_type_args,
                *scope_args,
            ]
        )
        atomic_write_json(evidence_path, evidence)

        auditor_results = []
        for auditor_name in AUDITORS:
            auditor_payload = run_json(
                [
                    sys.executable,
                    str(script_root / "auditors" / f"{auditor_name}.py"),
                    "--baseline-json",
                    str(baseline_path),
                    "--evidence-json",
                    str(evidence_path),
                    *task_type_args,
                ]
            )
            auditor_results.append(auditor_payload)
        atomic_write_json(auditors_path, auditor_results)

        safety = run_json(
            [
                sys.executable,
                str(script_root / "safety_boundary_check.py"),
                "--baseline-json",
                str(baseline_path),
                "--evidence-json",
                str(evidence_path),
                "--auditors-json",
                str(auditors_path),
            ]
        )
        atomic_write_json(safety_path, safety)

        score = run_json(
            [
                sys.executable,
                str(script_root / "score_candidate.py"),
                "--baseline-json",
                str(baseline_path),
                "--evidence-json",
                str(evidence_path),
                "--auditors-json",
                str(auditors_path),
                "--safety-json",
                str(safety_path),
            ]
        )
        atomic_write_json(score_path, score)

        reflection = run_json(
            [
                sys.executable,
                str(script_root / "reflect_on_result.py"),
                "--auditors-json",
                str(auditors_path),
                "--score-json",
                str(score_path),
            ]
        )
        atomic_write_json(reflection_path, reflection)

        report_info = run_json(
            [
                sys.executable,
                str(script_root / "write_report.py"),
                "--task-id",
                args.task_id,
                *task_type_args,
                "--baseline-json",
                str(baseline_path),
                "--evidence-json",
                str(evidence_path),
                "--score-json",
                str(score_path),
                "--reflection-json",
                str(reflection_path),
                "--auditors-json",
                str(auditors_path),
                "--safety-json",
                str(safety_path),
            ]
        )

    payload = {
        "schema_version": "0.1",
        "finished_at": now_iso(),
        "task_id": args.task_id,
        "task_types": args.task_types,
        "evidence_profile": args.evidence_profile,
        "decision": score.get("decision"),
        "total_score": score.get("total_score"),
        "review_scope": baseline.get("review_scope"),
        "report_dir": report_info.get("report_dir"),
        "final_review_path": report_info.get("final_review_path"),
        "scope_summary_path": report_info.get("scope_summary_path"),
    }
    print(json.dumps(payload, ensure_ascii=True, sort_keys=True, indent=2))


if __name__ == "__main__":
    main()
