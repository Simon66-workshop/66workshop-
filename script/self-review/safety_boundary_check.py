#!/usr/bin/env python3
"""Evaluate hard safety boundaries for Self-Review Arbiter."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any

from _shared import (
    build_artifacts_in_paths,
    classify_dirty_paths_with_unknown,
    config_dir,
    load_json,
    now_iso,
    path_has_auth_secret_risk,
    project_root,
)


AUTH_PATH_PATTERN = r"(?:~\/)?\.codex\/auth\.json"
RULE_REGEXES = {
    "no_external_api": (
        re.compile(r"\brequests\.(get|post|put|patch|delete)\(", re.MULTILINE),
        re.compile(r"\burllib\.request\.", re.MULTILINE),
        re.compile(r"\bsubprocess\.(run|Popen)\([^\n]{0,160}\b(curl|wget)\b", re.MULTILINE),
    ),
    "no_codex_auth_read": (
        re.compile(rf"open\([^\n]{{0,160}}{AUTH_PATH_PATTERN}", re.MULTILINE),
        re.compile(rf"read_text\([^\n]{{0,160}}{AUTH_PATH_PATTERN}", re.MULTILINE),
        re.compile(rf"Path\([^\n]{{0,160}}{AUTH_PATH_PATTERN}[^\n]{{0,160}}\)\.(read_text|open)\(", re.MULTILINE),
        re.compile(rf"load_json\([^\n]{{0,160}}{AUTH_PATH_PATTERN}", re.MULTILINE),
    ),
    "no_sensitive_output": (
        re.compile(r"\b(print|pprint|json\.dump|json\.dumps)\([^\n]{0,160}\b(prompt_text|response_text|raw_log_body|auth_token)\b", re.MULTILINE),
        re.compile(r"\blines\.append\([^\n]{0,160}\b(prompt_text|response_text|raw_log_body|auth_token)\b", re.MULTILINE),
    ),
    "no_auto_commit_push": (
        re.compile(r"\bsubprocess\.(run|Popen)\([^\n]{0,200}\bgit\b[^\n]{0,120}\b(commit|push)\b", re.MULTILINE),
        re.compile(r'^\s*git (commit|push)\b', re.MULTILINE),
        re.compile(r'exec_command\(\s*\{[^\n]{0,200}"cmd":\s*"[^"]*\bgit (commit|push)\b', re.MULTILINE),
    ),
}


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Run self-review safety boundary checks")
    parser.add_argument("--baseline-json", required=True)
    parser.add_argument("--evidence-json", required=True)
    parser.add_argument("--auditors-json", required=True)
    return parser


def scan_changed_files(paths: list[str]) -> dict[str, list[str]]:
    hits = {key: [] for key in RULE_REGEXES}
    for raw_path in paths:
        path = project_root() / raw_path
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        for rule_id, regexes in RULE_REGEXES.items():
            if any(regex.search(text) for regex in regexes):
                hits[rule_id].append(raw_path)
    return hits


def scan_auth_secret_out_of_scope(paths: list[str]) -> list[str]:
    risky: list[str] = []
    hits = scan_changed_files(paths)
    hard_rules = {"no_codex_auth_read", "no_sensitive_output"}
    for path in paths:
        if path_has_auth_secret_risk(path):
            risky.append(path)
            continue
        if any(path in hits.get(rule_id, []) for rule_id in hard_rules):
            risky.append(path)
    return sorted(set(risky))


def find_auditor(auditors: list[dict[str, Any]], auditor_id: str) -> dict[str, Any]:
    for item in auditors:
        if item.get("auditor_id") == auditor_id:
            return item
    return {}


def main() -> None:
    args = build_parser().parse_args()
    baseline = load_json(Path(args.baseline_json), {})
    evidence = load_json(Path(args.evidence_json), {})
    auditors = load_json(Path(args.auditors_json), [])
    boundaries = load_json(config_dir() / "global-safety-boundary.json", {})
    changed_files = [str(path) for path in (((baseline.get("git") or {}).get("changed_files")) or [])]
    out_of_scope_dirty_files = [str(path) for path in (((baseline.get("git") or {}).get("out_of_scope_dirty_files")) or [])]
    scan_hits = scan_changed_files(changed_files)
    staged_files = [str(path) for path in (((baseline.get("git") or {}).get("staged_files")) or [])]
    out_of_scope = classify_dirty_paths_with_unknown(out_of_scope_dirty_files)
    out_of_scope_auth_secret_files = scan_auth_secret_out_of_scope(out_of_scope_dirty_files)
    state_auditor = find_auditor(auditors, "state_projector_auditor")
    swift_auditor = find_auditor(auditors, "swift_ui_auditor")
    git_auditor = find_auditor(auditors, "git_diff_auditor")
    required_commands = evidence.get("required_commands") if isinstance(evidence.get("required_commands"), dict) else {}

    checks: list[dict[str, Any]] = []
    for item in boundaries.get("rules") or []:
        if not isinstance(item, dict):
            continue
        rule_id = str(item.get("rule_id"))
        passed = True
        detail = "ok"
        if rule_id == "no_build_artifacts_staged":
            artifacts = build_artifacts_in_paths(staged_files)
            passed = not artifacts
            detail = "none" if passed else ", ".join(artifacts)
        elif rule_id in scan_hits:
            hits = scan_hits[rule_id]
            passed = not hits
            detail = "none" if passed else ", ".join(hits)
        elif rule_id == "verify_only_done_green":
            passed = bool((state_auditor.get("summary") or {}).get("verify_only_done_green", True))
            detail = "verify gate preserved" if passed else "done green path violated"
        elif rule_id == "stop_never_done_verified":
            passed = bool((state_auditor.get("summary") or {}).get("stop_never_done_verified", True))
            detail = "stop did not map to done_verified" if passed else "stop mapped to done_verified"
        elif rule_id == "stop_preserves_done_unverified":
            passed = bool((state_auditor.get("summary") or {}).get("stop_preserves_done_unverified", True))
            detail = "stop still maps to pending path" if passed else "stop pending path missing"
        elif rule_id == "process_observer_only_not_running":
            passed = bool((state_auditor.get("summary") or {}).get("process_observer_only_not_running", True))
            detail = "process-only guard intact" if passed else "process-only drove running"
        elif rule_id == "global_private_probe_not_running":
            passed = bool((state_auditor.get("summary") or {}).get("global_private_probe_not_running", True))
            detail = "global private guard intact" if passed else "global private drove running"
        elif rule_id == "swift_ui_reads_ui_state_first":
            passed = bool((swift_auditor.get("summary") or {}).get("ui_state_first", False))
            detail = "Swift UI reads ui_state first" if passed else "Swift UI ui_state-first contract unclear"
        checks.append(
            {
                "rule_id": rule_id,
                "level": item.get("level"),
                "description": item.get("description"),
                "passed": passed,
                "detail": detail,
            }
        )

    check_all = required_commands.get("check_all") if isinstance(required_commands, dict) else {}
    required_failures = [
        command_id
        for command_id, result in required_commands.items()
        if isinstance(result, dict) and not result.get("passed", False)
    ]
    if out_of_scope_auth_secret_files:
        hard_gate_failed = True
    else:
        hard_gate_failed = bool(required_failures) or (isinstance(check_all, dict) and not check_all.get("passed", False)) or any(not item["passed"] for item in checks if item.get("level") == "hard_gate")

    scope_decision = "PASS"
    if out_of_scope_auth_secret_files:
        scope_decision = "REJECT"
    elif out_of_scope["launch_trust"] or out_of_scope["unknown"]:
        scope_decision = "NEEDS_HUMAN_REVIEW"
    elif out_of_scope["ordinary"]:
        scope_decision = "CONDITIONAL_PASS"
    elif not (baseline.get("review_scope") or {}).get("enabled", False):
        scope_decision = "WHOLE_WORKTREE"

    payload = {
        "schema_version": "0.1",
        "checked_at": now_iso(),
        "checks": checks,
        "scan_hits": scan_hits,
        "build_artifacts_staged": build_artifacts_in_paths(staged_files),
        "required_command_failures": required_failures,
        "out_of_scope_dirty_files": out_of_scope_dirty_files,
        "out_of_scope_launch_trust_files": out_of_scope["launch_trust"],
        "out_of_scope_auth_secret_files": out_of_scope_auth_secret_files,
        "out_of_scope_unknown_files": out_of_scope["unknown"],
        "hard_gate_failed": hard_gate_failed,
        "summary": {
            "check_all_passed": bool((check_all or {}).get("passed", False)),
            "required_evidence_complete": not required_failures,
            "ui_state_first": bool((swift_auditor.get("summary") or {}).get("ui_state_first", False)),
            "launch_human_review": bool((git_auditor.get("summary") or {}).get("launch_or_trust_changed", False)),
            "visual_human_review": bool((git_auditor.get("summary") or {}).get("visual_ui_changed", False)),
            "scope_decision": scope_decision,
        },
    }
    print(json.dumps(payload, ensure_ascii=True, sort_keys=True, indent=2))


if __name__ == "__main__":
    main()
