#!/usr/bin/env python3
"""Score self-review evidence and choose a final decision."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from _shared import config_dir, load_json, now_iso


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Score self-review candidate")
    parser.add_argument("--baseline-json", required=True)
    parser.add_argument("--evidence-json", required=True)
    parser.add_argument("--auditors-json", required=True)
    parser.add_argument("--safety-json", required=True)
    return parser


def find_auditor(auditors: list[dict[str, Any]], auditor_id: str) -> dict[str, Any]:
    for item in auditors:
        if item.get("auditor_id") == auditor_id:
            return item
    return {}


def fraction(passed: int, total: int) -> float:
    if total <= 0:
        return 0.0
    return max(0.0, min(1.0, passed / total))


def score_bucket(weight: int, passed: int, total: int) -> dict[str, Any]:
    ratio = fraction(passed, total)
    return {"weight": weight, "passed": passed, "total": total, "score": round(weight * ratio, 2)}


def main() -> None:
    args = build_parser().parse_args()
    evidence = load_json(Path(args.evidence_json), {})
    auditors = load_json(Path(args.auditors_json), [])
    safety = load_json(Path(args.safety_json), {})
    rubrics = load_json(config_dir() / "scoring-rubrics.json", {})
    weights = rubrics.get("weights") if isinstance(rubrics.get("weights"), dict) else {}
    thresholds = rubrics.get("decision_thresholds") if isinstance(rubrics.get("decision_thresholds"), dict) else {}
    state_auditor = find_auditor(auditors, "state_projector_auditor")
    hook_auditor = find_auditor(auditors, "hook_bridge_auditor")
    swift_auditor = find_auditor(auditors, "swift_ui_auditor")
    docs_auditor = find_auditor(auditors, "docs_consistency_auditor")
    signal_auditor = find_auditor(auditors, "signal_bus_auditor")
    git_auditor = find_auditor(auditors, "git_diff_auditor")

    matrix = (state_auditor.get("matrix") or {}) if isinstance(state_auditor, dict) else {}
    matrix_items = [item for item in matrix.values() if isinstance(item, dict)]
    matrix_passed = sum(1 for item in matrix_items if item.get("judgment") == "pass")
    matrix_known = sum(1 for item in matrix_items if item.get("judgment") in {"pass", "fail"})

    required = evidence.get("required_commands") if isinstance(evidence.get("required_commands"), dict) else {}
    optional = evidence.get("optional_commands") if isinstance(evidence.get("optional_commands"), dict) else {}
    required_passed = sum(1 for item in required.values() if isinstance(item, dict) and item.get("passed"))
    required_total = len(required)
    optional_passed = sum(1 for item in optional.values() if isinstance(item, dict) and item.get("passed"))
    optional_total = len(optional)

    buckets = {
        "state_accuracy": score_bucket(int(weights.get("state_accuracy", 35)), matrix_passed, matrix_known or len(matrix_items)),
        "signal_arbitration": score_bucket(int(weights.get("signal_arbitration", 20)), int((signal_auditor.get("summary") or {}).get("good_signal_hygiene", False)) + int((state_auditor.get("summary") or {}).get("no_weak_signal_promotion", False)), 2),
        "regression_safety": score_bucket(int(weights.get("regression_safety", 15)), required_passed + optional_passed, required_total + optional_total),
        "ui_consistency": score_bucket(int(weights.get("ui_consistency", 10)), int((swift_auditor.get("summary") or {}).get("ui_state_first", False)) + int(not (git_auditor.get("summary") or {}).get("visual_ui_changed", False)), 2),
        "launch_health": score_bucket(int(weights.get("launch_health", 10)), int((hook_auditor.get("summary") or {}).get("launch_status_ok", False)) + int(not (git_auditor.get("summary") or {}).get("launch_or_trust_changed", False)), 2),
        "diagnostic_quality": score_bucket(int(weights.get("diagnostic_quality", 5)), int((docs_auditor.get("summary") or {}).get("docs_present", False)), 1),
        "maintainability": score_bucket(int(weights.get("maintainability", 5)), int((docs_auditor.get("summary") or {}).get("config_present", False)), 1),
    }

    total_score = round(sum(bucket["score"] for bucket in buckets.values()), 2)
    hard_gate_failed = bool(safety.get("hard_gate_failed", False))
    failures = []
    for auditor in auditors:
        for finding in auditor.get("findings") or []:
            if isinstance(finding, dict):
                failures.append(finding)

    failure_kinds = {str(item.get("failure_type")) for item in failures if item.get("failure_type")}
    summary = {
        "hard_gate_failed": hard_gate_failed,
        "visual_human_review": bool((safety.get("summary") or {}).get("visual_human_review", False)),
        "launch_human_review": bool((safety.get("summary") or {}).get("launch_human_review", False)),
        "scope_decision": str((safety.get("summary") or {}).get("scope_decision") or "PASS"),
        "failure_kinds": sorted(failure_kinds),
    }

    if hard_gate_failed or "false_green_done" in failure_kinds or "privacy_boundary_violation" in failure_kinds:
        decision = "REJECT"
    elif summary["scope_decision"] == "REJECT":
        decision = "REJECT"
    elif summary["visual_human_review"] or summary["launch_human_review"] or "launch_agent_unhealthy" in failure_kinds or summary["scope_decision"] == "NEEDS_HUMAN_REVIEW":
        decision = "NEEDS_HUMAN_REVIEW"
    elif summary["scope_decision"] == "CONDITIONAL_PASS":
        decision = "CONDITIONAL_PASS" if total_score >= float(thresholds.get("conditional_pass", 70)) else "REJECT"
    elif total_score >= float(thresholds.get("pass", 90)):
        decision = "PASS"
    elif total_score >= float(thresholds.get("conditional_pass", 70)):
        decision = "CONDITIONAL_PASS"
    else:
        decision = "REJECT"

    payload = {
        "schema_version": "0.1",
        "scored_at": now_iso(),
        "decision": decision,
        "total_score": total_score,
        "buckets": buckets,
        "summary": summary,
    }
    print(json.dumps(payload, ensure_ascii=True, sort_keys=True, indent=2))


if __name__ == "__main__":
    main()
