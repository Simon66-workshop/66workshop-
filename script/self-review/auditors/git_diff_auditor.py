#!/usr/bin/env python3
"""Audit git diff scope for review routing."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from _shared import build_artifacts_in_paths, classify_dirty_paths_with_unknown, load_json, now_iso, path_has_launch_trust_risk  # noqa: E402


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Audit git diff scope")
    parser.add_argument("--baseline-json", required=True)
    parser.add_argument("--evidence-json", required=True)
    parser.add_argument("--task-type", nargs="*", default=[])
    return parser


def main() -> None:
    args = build_parser().parse_args()
    baseline = load_json(Path(args.baseline_json), {})
    git = baseline.get("git") if isinstance(baseline.get("git"), dict) else {}
    changed_files = [str(item) for item in (git.get("changed_files") or [])]
    staged_files = [str(item) for item in (git.get("staged_files") or [])]
    out_of_scope_dirty_files = [str(item) for item in (git.get("out_of_scope_dirty_files") or [])]
    out_of_scope = classify_dirty_paths_with_unknown(out_of_scope_dirty_files)
    visual_ui_changed = any(path.endswith(".swift") and "TaskLightApp" in path for path in changed_files)
    launch_or_trust_changed = any(path_has_launch_trust_risk(path) for path in changed_files)
    build_artifacts = build_artifacts_in_paths(staged_files)
    findings = []
    if build_artifacts:
        findings.append(
            {
                "failure_type": "missing_evidence",
                "message": "build artifacts are staged",
                "evidence": build_artifacts,
                "root_cause": "working tree contains staged build outputs",
                "next_bounded_action": "unstage build outputs before accepting the task",
                "decision": "REJECT",
            }
        )
    if out_of_scope["ordinary"]:
        findings.append(
            {
                "failure_type": "unrelated_dirty_worktree",
                "message": "out-of-scope dirty files exist",
                "evidence": out_of_scope["ordinary"],
                "root_cause": "working tree contains unrelated dirty files outside the active review scope",
                "next_bounded_action": "keep using a scope file or clean unrelated worktree drift before final acceptance",
                "decision": "CONDITIONAL_PASS",
                "scope": "out_of_scope",
            }
        )
    if out_of_scope["launch_trust"]:
        findings.append(
            {
                "failure_type": "launch_agent_unhealthy",
                "message": "out-of-scope launch/trust files changed",
                "evidence": out_of_scope["launch_trust"],
                "root_cause": "launch or trust changes exist outside the active review scope",
                "next_bounded_action": "route this task through human review even if in-scope evidence is clean",
                "decision": "NEEDS_HUMAN_REVIEW",
                "scope": "out_of_scope",
            }
        )
    if out_of_scope["auth_secret"]:
        findings.append(
            {
                "failure_type": "privacy_boundary_violation",
                "message": "out-of-scope auth/secret files changed",
                "evidence": out_of_scope["auth_secret"],
                "root_cause": "auth or secret related files are dirty outside the active review scope",
                "next_bounded_action": "treat the whole review as blocked until auth/secret drift is explained",
                "decision": "REJECT",
                "scope": "out_of_scope",
            }
        )
    if out_of_scope["unknown"]:
        findings.append(
            {
                "failure_type": "missing_evidence",
                "message": "out-of-scope dirty files could not be classified",
                "evidence": out_of_scope["unknown"],
                "root_cause": "one or more dirty files escaped the known scope classifiers",
                "next_bounded_action": "treat the scope as needing human review until the file class is explained",
                "decision": "NEEDS_HUMAN_REVIEW",
                "scope": "out_of_scope",
            }
        )

    scope_decision = "PASS"
    if out_of_scope["auth_secret"]:
        scope_decision = "REJECT"
    elif out_of_scope["launch_trust"] or out_of_scope["unknown"]:
        scope_decision = "NEEDS_HUMAN_REVIEW"
    elif out_of_scope["ordinary"]:
        scope_decision = "CONDITIONAL_PASS"

    payload = {
        "auditor_id": "git_diff_auditor",
        "checked_at": now_iso(),
        "summary": {
            "changed_file_count": len(changed_files),
            "staged_file_count": len(staged_files),
            "visual_ui_changed": visual_ui_changed,
            "launch_or_trust_changed": launch_or_trust_changed,
            "build_artifacts_staged": build_artifacts,
            "out_of_scope_dirty_files": out_of_scope_dirty_files,
            "out_of_scope_launch_trust_files": out_of_scope["launch_trust"],
            "out_of_scope_auth_secret_files": out_of_scope["auth_secret"],
            "out_of_scope_unknown_files": out_of_scope["unknown"],
            "scope_decision": scope_decision,
        },
        "findings": findings,
    }
    print(json.dumps(payload, ensure_ascii=True, sort_keys=True, indent=2))


if __name__ == "__main__":
    main()
