#!/usr/bin/env python3
"""Collect sanitized baseline context for Self-Review Arbiter."""

from __future__ import annotations

import argparse
import json
from typing import Any

from _shared import (
    apply_scope_to_git_payload,
    build_review_scope,
    fixture_baseline_overrides,
    changed_file_paths,
    git_lines,
    git_status_entries,
    load_signal_records,
    now_iso,
    project_root,
    staged_file_paths,
    state_dir,
    summarize_signal_bus,
    summarize_tasks,
    summarize_ui_state,
)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Collect sanitized self-review baseline")
    parser.add_argument("--task-id", required=True)
    parser.add_argument("--task-type", dest="task_types", action="append", default=[])
    parser.add_argument("--scope-file")
    parser.add_argument("--review-path", dest="review_paths", action="append", default=[])
    parser.add_argument("--exclude-path", dest="exclude_paths", action="append", default=[])
    return parser


def git_summary() -> dict[str, Any]:
    branch = git_lines("rev-parse", "--abbrev-ref", "HEAD")
    head = git_lines("rev-parse", "--short", "HEAD")
    return {
      "branch": branch[0] if branch else "unknown",
      "head": head[0] if head else "unknown",
      "status_entries": git_status_entries(),
      "changed_files": changed_file_paths(),
      "staged_files": staged_file_paths(),
    }


def main() -> None:
    args = build_parser().parse_args()
    signals = load_signal_records()
    overrides = fixture_baseline_overrides()
    scope = build_review_scope(
        args.task_id,
        scope_file=args.scope_file,
        review_paths=args.review_paths,
        exclude_paths=args.exclude_paths,
    )
    git_payload = git_summary()
    override_git = overrides.get("git") if isinstance(overrides.get("git"), dict) else {}
    if override_git:
        git_payload.update(override_git)
    git_payload = apply_scope_to_git_payload(git_payload, scope)
    payload = {
        "schema_version": "0.1",
        "collected_at": now_iso(),
        "task_id": args.task_id,
        "task_types": args.task_types,
        "project_root": str(project_root()),
        "state_dir": str(state_dir()),
        "review_scope": scope,
        "git": git_payload,
        "ui_state_summary": summarize_ui_state(),
        "signal_bus_summary": summarize_signal_bus(signals),
        "task_summary": summarize_tasks(),
    }
    print(json.dumps(payload, ensure_ascii=True, sort_keys=True, indent=2))


if __name__ == "__main__":
    main()
