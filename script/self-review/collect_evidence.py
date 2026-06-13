#!/usr/bin/env python3
"""Run required and optional self-review evidence commands."""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path
from types import SimpleNamespace
from typing import Any, Callable

from _shared import (
    apply_scope_to_git_payload,
    build_artifacts_in_paths,
    build_review_scope,
    classify_dirty_paths_with_unknown,
    config_dir,
    fixture_command_result,
    git_lines,
    git_status_entries,
    is_staged_status,
    load_json,
    now_iso,
    project_root,
    run_command,
    run_subprocess,
    sanitize_status_line,
)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Collect self-review evidence")
    parser.add_argument("--task-id", required=True)
    parser.add_argument("--task-type", dest="task_types", action="append", default=[])
    parser.add_argument("--scope-file")
    parser.add_argument("--review-path", dest="review_paths", action="append", default=[])
    parser.add_argument("--exclude-path", dest="exclude_paths", action="append", default=[])
    parser.add_argument("--evidence-profile", choices=["fast", "full", "release"], default="full")
    return parser


def fixture_or_live_result(command_id: str, argv: list[str], runner: Callable[[], dict[str, Any]], required: bool) -> dict[str, Any]:
    fixture = fixture_command_result(command_id)
    if fixture is not None:
        return {
            "command_id": command_id,
            "argv": argv,
            "mode": "fixture",
            "exit_code": int(fixture.get("exit_code", 0)),
            "duration_sec": float(fixture.get("duration_sec", 0.0)),
            "passed": int(fixture.get("exit_code", 0)) == 0,
            "key_values": fixture.get("key_values") if isinstance(fixture.get("key_values"), dict) else {},
            "status_line": fixture.get("status_line"),
            "line_count": int(fixture.get("line_count", 0)),
            "required": required,
        }
    return runner()


def evidence_mode_env(command_id: str) -> dict[str, str] | None:
    if command_id in {"smoke_self_review", "smoke_self_review_scope"}:
        return {"TASKLIGHT_SELF_REVIEW_EVIDENCE_MODE": "1"}
    return None


def command_result_from_completed(command_id: str, argv: list[str], started_at: float, completed: Any, *, required: bool, key_values: dict[str, Any] | None = None, status_line: str | None = None) -> dict[str, Any]:
    output = "\n".join(part for part in [getattr(completed, "stdout", ""), getattr(completed, "stderr", "")] if part).strip()
    return {
        "command_id": command_id,
        "argv": argv,
        "mode": "live",
        "exit_code": completed.returncode,
        "duration_sec": round(time.time() - started_at, 3),
        "passed": completed.returncode == 0,
        "key_values": key_values or {},
        "status_line": status_line if status_line is not None else sanitize_status_line(output),
        "line_count": len(output.splitlines()) if output else 0,
        "required": required,
    }


def run_py_compile(required: bool) -> dict[str, Any]:
    files = sorted(
        {
            *{str(path) for path in (project_root() / "script" / "self-review").glob("*.py")},
            *{str(path) for path in (project_root() / "script" / "self-review" / "auditors").glob("*.py")},
        }
    )
    argv = [sys.executable, "-m", "py_compile", *files]

    def runner() -> dict[str, Any]:
        started = time.time()
        completed = run_subprocess(argv, cwd=project_root())
        return command_result_from_completed(
            "py_compile_self_review",
            argv,
            started,
            completed,
            required=required,
            key_values={"compiled_files": files},
            status_line="py_compile_self_review: ok" if completed.returncode == 0 else "py_compile_self_review: failed",
        )

    return fixture_or_live_result("py_compile_self_review", argv, runner, required)


def run_basic_git_scope_audit(args: argparse.Namespace, required: bool) -> dict[str, Any]:
    scope = build_review_scope(
        args.task_id,
        scope_file=args.scope_file,
        review_paths=args.review_paths,
        exclude_paths=args.exclude_paths,
    )
    argv = [
        "basic_git_scope_audit",
        "--task-id",
        args.task_id,
        "--scope-file",
        str(args.scope_file or ""),
    ]

    def runner() -> dict[str, Any]:
        started = time.time()
        status_entries = git_status_entries()
        branch = git_lines("rev-parse", "--abbrev-ref", "HEAD")
        head = git_lines("rev-parse", "--short", "HEAD")
        raw_git = {
            "branch": branch[0] if branch else "unknown",
            "head": head[0] if head else "unknown",
            "status_entries": status_entries,
        }
        scoped_git = apply_scope_to_git_payload(raw_git, scope)
        risk_classes = classify_dirty_paths_with_unknown(scoped_git.get("out_of_scope_dirty_files") or [])
        scope_decision = "PASS"
        if risk_classes.get("auth_secret"):
            scope_decision = "REJECT"
        elif risk_classes.get("launch_trust"):
            scope_decision = "NEEDS_HUMAN_REVIEW"
        elif risk_classes.get("ordinary") or risk_classes.get("unknown"):
            scope_decision = "CONDITIONAL_PASS"
        elif not scope.get("enabled", False):
            scope_decision = "WHOLE_WORKTREE"
        key_values = {
            "review_scope": scoped_git.get("scope", {}).get("mode"),
            "included_paths": scoped_git.get("scope", {}).get("include") or [],
            "excluded_paths": scoped_git.get("scope", {}).get("exclude") or [],
            "in_scope_changed_files": scoped_git.get("changed_files") or [],
            "out_of_scope_dirty_files": scoped_git.get("out_of_scope_dirty_files") or [],
            "out_of_scope_risk_classes": risk_classes,
            "scope_decision": scope_decision,
            "scope_reason": scoped_git.get("scope", {}).get("reason") or "",
        }
        completed = SimpleNamespace(returncode=0 if scope_decision != "REJECT" else 1, stdout="", stderr="")
        return command_result_from_completed(
            "basic_git_scope_audit",
            argv,
            started,
            completed=completed,
            required=required,
            key_values=key_values,
            status_line="basic_git_scope_audit: ok" if scope_decision != "REJECT" else "basic_git_scope_audit: reject",
        )

    return fixture_or_live_result("basic_git_scope_audit", argv, runner, required)


def run_release_readiness_audit(required: bool) -> dict[str, Any]:
    argv = ["release_readiness_audit"]

    def runner() -> dict[str, Any]:
        started = time.time()
        staged_files = [entry["path"] for entry in git_status_entries() if is_staged_status(str(entry.get("status") or ""))]
        build_artifacts = build_artifacts_in_paths(staged_files)
        ignored_paths: list[str] = []
        check_ignore = run_subprocess(["git", "check-ignore", "-v", "--", "docs/assets", "AppAssets"], cwd=project_root())
        if check_ignore.returncode == 0:
            for line in (check_ignore.stdout or "").splitlines():
                if "\t" not in line:
                    continue
                ignored_paths.append(line.split("\t", 1)[1].strip())
        docs_assets_ignored = any(path == "docs/assets" for path in ignored_paths)
        appassets_ignored = any(path == "AppAssets" for path in ignored_paths)
        release_ready = not build_artifacts and not docs_assets_ignored and not appassets_ignored
        key_values = {
            "staged_build_artifacts": build_artifacts,
            "ignored_paths": sorted(set(ignored_paths)),
            "docs_assets_ignored": docs_assets_ignored,
            "appassets_ignored": appassets_ignored,
            "release_ready": release_ready,
        }
        status_line = "release_readiness_audit: ok" if release_ready else "release_readiness_audit: blocked"
        completed = SimpleNamespace(returncode=0 if release_ready else 1, stdout="", stderr="")
        return command_result_from_completed(
            "release_readiness",
            argv,
            started,
            completed=completed,
            required=required,
            key_values=key_values,
            status_line=status_line,
        )

    return fixture_or_live_result("release_readiness", argv, runner, required)


def command_results(entries: list[dict[str, Any]]) -> dict[str, Any]:
    results: dict[str, Any] = {}
    for entry in entries:
        command_id = str(entry["command_id"])
        path = Path(str(entry["path"]))
        absolute = path if path.is_absolute() else project_root() / path
        if not absolute.exists():
            results[command_id] = {
                "command_id": command_id,
                "argv": [str(absolute)],
                "mode": "missing",
                "exit_code": 127,
                "duration_sec": 0.0,
                "passed": False,
                "key_values": {},
                "status_line": "command missing",
                "line_count": 0,
                "required": bool(entry.get("required", False)),
            }
            continue
        result = run_command(command_id, [str(absolute)], env=evidence_mode_env(command_id))
        result["required"] = bool(entry.get("required", False))
        results[command_id] = result
    return results


def main() -> None:
    args = build_parser().parse_args()
    requirements = load_json(config_dir() / "evidence-requirements.json", {})
    if args.evidence_profile == "fast":
        required_entries = [
            {"command_id": "py_compile_self_review", "kind": "internal", "required": True},
            {"command_id": "smoke_self_review", "path": "./script/smoke_self_review.sh", "required": True},
            {"command_id": "smoke_self_review_scope", "path": "./script/smoke_self_review_scope.sh", "required": True},
            {"command_id": "basic_git_scope_audit", "kind": "internal", "required": True},
        ]
        optional_entries = requirements.get("optional_commands") if isinstance(requirements.get("optional_commands"), list) else []
    elif args.evidence_profile == "release":
        required_entries = [
            item
            for item in (requirements.get("required_commands") if isinstance(requirements.get("required_commands"), list) else [])
            if isinstance(item, dict)
        ] + [{"command_id": "release_readiness", "kind": "internal", "required": True}]
        optional_entries = requirements.get("optional_commands") if isinstance(requirements.get("optional_commands"), list) else []
    else:
        required_entries = requirements.get("required_commands") if isinstance(requirements.get("required_commands"), list) else []
        optional_entries = requirements.get("optional_commands") if isinstance(requirements.get("optional_commands"), list) else []

    required_results: dict[str, Any] = {}
    for entry in [item for item in required_entries if isinstance(item, dict)]:
        command_id = str(entry["command_id"])
        required = bool(entry.get("required", False))
        kind = str(entry.get("kind") or "script")
        if kind == "internal":
            if command_id == "py_compile_self_review":
                required_results[command_id] = run_py_compile(required)
            elif command_id == "basic_git_scope_audit":
                required_results[command_id] = run_basic_git_scope_audit(args, required)
            elif command_id == "release_readiness":
                required_results[command_id] = run_release_readiness_audit(required)
            else:
                required_results[command_id] = {
                    "command_id": command_id,
                    "argv": [kind, command_id],
                    "mode": "missing",
                    "exit_code": 127,
                    "duration_sec": 0.0,
                    "passed": False,
                    "key_values": {},
                    "status_line": "internal command missing",
                    "line_count": 0,
                    "required": required,
                }
            continue
        path = Path(str(entry["path"]))
        absolute = path if path.is_absolute() else project_root() / path
        if not absolute.exists():
            required_results[command_id] = {
                "command_id": command_id,
                "argv": [str(absolute)],
                "mode": "missing",
                "exit_code": 127,
                "duration_sec": 0.0,
                "passed": False,
                "key_values": {},
                "status_line": "command missing",
                "line_count": 0,
                "required": required,
            }
            continue
        result = run_command(command_id, [str(absolute)], env=evidence_mode_env(command_id))
        result["required"] = required
        required_results[command_id] = result

    optional_results = command_results([item for item in optional_entries if isinstance(item, dict)])

    profile_summary: dict[str, Any] = {
        "evidence_profile": args.evidence_profile,
        "required_command_ids": sorted(required_results.keys()),
        "optional_command_ids": sorted(optional_results.keys()),
        "required_passed": sum(1 for item in required_results.values() if isinstance(item, dict) and item.get("passed")),
        "optional_passed": sum(1 for item in optional_results.values() if isinstance(item, dict) and item.get("passed")),
        "check_all_ran": "check_all" in required_results or "check_all" in optional_results,
    }
    if "basic_git_scope_audit" in required_results:
        profile_summary["basic_git_scope_audit"] = required_results["basic_git_scope_audit"].get("key_values", {})
    if "release_readiness" in required_results:
        profile_summary["release_readiness"] = required_results["release_readiness"].get("key_values", {})

    payload = {
        "schema_version": "0.1",
        "collected_at": now_iso(),
        "task_id": args.task_id,
        "task_types": args.task_types,
        "evidence_profile": args.evidence_profile,
        "profile_summary": profile_summary,
        "required_commands": required_results,
        "optional_commands": optional_results,
    }
    print(json.dumps(payload, ensure_ascii=True, sort_keys=True, indent=2))


if __name__ == "__main__":
    main()
