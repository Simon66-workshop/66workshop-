#!/usr/bin/env python3
"""Write self-review report artifacts."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from _shared import atomic_write, atomic_write_json, build_scope_summary, load_json, report_directory


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Write self-review report files")
    parser.add_argument("--task-id", required=True)
    parser.add_argument("--task-type", dest="task_types", action="append", default=[])
    parser.add_argument("--baseline-json", required=True)
    parser.add_argument("--evidence-json", required=True)
    parser.add_argument("--score-json", required=True)
    parser.add_argument("--reflection-json", required=True)
    parser.add_argument("--auditors-json", required=True)
    parser.add_argument("--safety-json", required=True)
    return parser


def baseline_markdown(payload: dict[str, Any]) -> str:
    git = payload.get("git") or {}
    ui = payload.get("ui_state_summary") or {}
    signals = payload.get("signal_bus_summary") or {}
    tasks = payload.get("task_summary") or {}
    scope = payload.get("review_scope") or {}
    lines = [
        "# Baseline",
        "",
        f"- task_id: `{payload.get('task_id')}`",
        f"- task_types: `{', '.join(payload.get('task_types') or [])}`",
        f"- review_scope: `{scope.get('mode')}`",
        f"- included_paths: `{', '.join(scope.get('include') or [])}`",
        f"- excluded_paths: `{', '.join(scope.get('exclude') or [])}`",
        f"- branch: `{git.get('branch', 'unknown')}`",
        f"- head: `{git.get('head', 'unknown')}`",
        f"- changed_files: `{len(git.get('changed_files') or [])}`",
        f"- staged_files: `{len(git.get('staged_files') or [])}`",
        f"- out_of_scope_dirty_files: `{len(git.get('out_of_scope_dirty_files') or [])}`",
        f"- ui_global_status: `{ui.get('global_status')}`",
        f"- ui_display_title: `{ui.get('global_display_title')}`",
        f"- writer_status: `{ui.get('writer_status')}`",
        f"- signal_records: `{signals.get('record_count', 0)}`",
        f"- recent_sources: `{', '.join(signals.get('recent_source_set') or [])}`",
        f"- task_count: `{tasks.get('task_count', 0)}`",
    ]
    return "\n".join(lines) + "\n"


def evidence_markdown(payload: dict[str, Any]) -> str:
    profile = payload.get("evidence_profile")
    profile_summary = payload.get("profile_summary") if isinstance(payload.get("profile_summary"), dict) else {}
    lines = ["# Evidence", ""]
    lines.append(f"- evidence_profile: `{profile}`")
    if profile_summary:
        lines.append(f"- required_command_ids: `{', '.join(profile_summary.get('required_command_ids') or [])}`")
        lines.append(f"- optional_command_ids: `{', '.join(profile_summary.get('optional_command_ids') or [])}`")
        lines.append(f"- required_passed: `{profile_summary.get('required_passed', 0)}`")
        lines.append(f"- optional_passed: `{profile_summary.get('optional_passed', 0)}`")
        lines.append(f"- check_all_ran: `{profile_summary.get('check_all_ran')}`")
        if profile_summary.get("basic_git_scope_audit"):
            lines.append(f"- basic_git_scope_audit: `{json.dumps(profile_summary.get('basic_git_scope_audit'), ensure_ascii=True, sort_keys=True)}`")
        if profile_summary.get("release_readiness"):
            lines.append(f"- release_readiness: `{json.dumps(profile_summary.get('release_readiness'), ensure_ascii=True, sort_keys=True)}`")
    lines.append("")
    for label in ("required_commands", "optional_commands"):
        lines.append(f"## {label}")
        commands = payload.get(label) or {}
        for command_id, result in commands.items():
            if not isinstance(result, dict):
                continue
            status = "pass" if result.get("passed") else "fail"
            status_line = result.get("status_line") or "none"
            lines.append(f"- `{command_id}`: `{status}` exit=`{result.get('exit_code')}` line=`{status_line}`")
        lines.append("")
    return "\n".join(lines).strip() + "\n"


def final_review_markdown(task_id: str, task_types: list[str], report_dir: Path, baseline: dict[str, Any], evidence: dict[str, Any], score: dict[str, Any], safety: dict[str, Any], reflection: dict[str, Any], auditors: list[dict[str, Any]], scope_summary: dict[str, Any]) -> str:
    state_auditor = next((item for item in auditors if item.get("auditor_id") == "state_projector_auditor"), {})
    matrix = state_auditor.get("matrix") or {}
    scope = baseline.get("review_scope") or {}
    git = baseline.get("git") or {}
    out_of_scope_risk = scope_summary.get("out_of_scope_risk_classes") if isinstance(scope_summary.get("out_of_scope_risk_classes"), dict) else {}
    lines = [
        f"# Self-Review {task_id}",
        "",
        f"- decision: `{score.get('decision')}`",
        f"- total_score: `{score.get('total_score')}`",
        f"- task_types: `{', '.join(task_types)}`",
        f"- evidence_profile: `{evidence.get('evidence_profile')}`",
        f"- hard_gate_failed: `{safety.get('hard_gate_failed')}`",
        f"- review_scope: `{scope.get('mode')}`",
        f"- included_paths: `{', '.join(scope.get('include') or [])}`",
        f"- excluded_paths: `{', '.join(scope.get('exclude') or [])}`",
        f"- scope_summary_path: `{report_dir / 'scope-summary.json'}`",
        f"- in_scope_changed_files_count: `{len(scope_summary.get('in_scope_changed_files') or [])}`",
        f"- out_of_scope_dirty_files_count: `{len(scope_summary.get('out_of_scope_dirty_files') or [])}`",
        f"- out_of_scope_launch_trust_count: `{len(out_of_scope_risk.get('launch_trust') or [])}`",
        f"- out_of_scope_auth_secret_count: `{len(out_of_scope_risk.get('auth_secret') or [])}`",
        f"- out_of_scope_dirty_files: `{', '.join(git.get('out_of_scope_dirty_files') or [])}`",
        f"- scope_decision: `{(score.get('summary') or {}).get('scope_decision')}`",
        f"- scope_reason: `{scope_summary.get('scope_reason')}`",
        "",
        "## State Accuracy Matrix",
    ]
    for matrix_id, item in matrix.items():
        if not isinstance(item, dict):
            continue
        lines.append(f"- `{matrix_id}`: `{item.get('judgment')}` via `{', '.join(item.get('evidence') or [])}`")
    lines.extend(["", "## Reflection"])
    items = reflection.get("items") or []
    if items:
        for item in items:
            lines.append(f"- `{item.get('failure_type')}`: `{item.get('decision')}` root=`{item.get('root_cause')}`")
    else:
        lines.append("- no_failures_detected")
    lines.extend(["", "## Next Step"])
    if items:
        for item in items[:3]:
            lines.append(f"- `{item.get('next_bounded_action')}`")
    else:
        lines.append("- Keep the engine in review-only mode and use this report as the acceptance gate.")
    return "\n".join(lines) + "\n"


def main() -> None:
    args = build_parser().parse_args()
    baseline = load_json(Path(args.baseline_json), {})
    evidence = load_json(Path(args.evidence_json), {})
    score = load_json(Path(args.score_json), {})
    reflection = load_json(Path(args.reflection_json), {})
    auditors = load_json(Path(args.auditors_json), [])
    safety = load_json(Path(args.safety_json), {})

    report_dir = report_directory(args.task_id)
    scope_summary = build_scope_summary(args.task_id, baseline, safety)
    atomic_write_json(report_dir / "baseline.json", baseline)
    atomic_write(report_dir / "baseline.md", baseline_markdown(baseline))
    atomic_write_json(report_dir / "evidence.json", evidence)
    atomic_write(report_dir / "evidence.md", evidence_markdown(evidence))
    atomic_write_json(report_dir / "scope-summary.json", scope_summary)
    atomic_write_json(report_dir / "auditors.json", auditors)
    atomic_write_json(report_dir / "safety.json", safety)
    atomic_write_json(report_dir / "score.json", score)
    atomic_write_json(report_dir / "reflection.json", reflection)
    atomic_write(report_dir / "final-review.md", final_review_markdown(args.task_id, args.task_types, report_dir, baseline, evidence, score, safety, reflection, auditors, scope_summary))

    print(json.dumps({"report_dir": str(report_dir), "final_review_path": str(report_dir / "final-review.md"), "scope_summary_path": str(report_dir / "scope-summary.json")}, ensure_ascii=True, sort_keys=True, indent=2))


if __name__ == "__main__":
    main()
