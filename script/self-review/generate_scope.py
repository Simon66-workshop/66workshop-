#!/usr/bin/env python3
"""Auto-generate a scoped self-review candidate from the current git diff."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

from _shared import (
    atomic_write,
    atomic_write_json,
    build_artifacts_in_paths,
    dump_json,
    git_lines,
    git_status_entries,
    load_json,
    now_iso,
    normalize_path_list,
    normalize_rel_path,
    path_has_auth_secret_risk,
    path_has_launch_trust_risk,
    path_has_prefix,
    project_root,
    report_directory,
)


FIXTURE_ENV = "TASKLIGHT_SELF_REVIEW_GENERATE_FIXTURE_DIR"
FIXTURE_FILENAMES = (
    "generate-scope-fixture.json",
    "scope-fixture.json",
    "git-scope.json",
)

UNIVERSAL_SCOPE_SEEDS = (
    "script/self-review/",
    "config/self-review/",
    "docs/self-review/",
    "script/smoke_self_review.sh",
    "script/smoke_self_review_scope.sh",
    "script/smoke_self_review_generate_scope.sh",
)

TASK_TYPE_SCOPE_SEEDS: dict[str, tuple[str, ...]] = {
    "state_projector": (
        "script/state_projector.py",
        "script/check_state_projector.sh",
        "script/install_state_projector_launch_agent.sh",
        "script/uninstall_state_projector_launch_agent.sh",
        "script/smoke_state_projector.sh",
        "script/smoke_turn_runtime_arbiter.sh",
        "docs/STATE_PROJECTOR.md",
        "docs/STATUS_PROTOCOL.md",
        "README.md",
        "mac/66TaskLight/Sources/TaskLightCore/TaskLightStore.swift",
        "mac/66TaskLight/Sources/TaskLightCore/TaskLightTypes.swift",
        "mac/66TaskLight/Sources/TaskLightApp/TaskLightViewModel.swift",
    ),
    "hook_bridge": (
        "script/hook_signal_bridge.py",
        "script/check_hook_bridge.sh",
        "script/check_hook_bridge_launch_agent.sh",
        "script/install_hook_bridge_launch_agent.sh",
        "script/uninstall_hook_bridge_launch_agent.sh",
        "script/smoke_hook_signal_bridge.sh",
        "script/smoke_hook_bridge_launch_agent.sh",
        "docs/HOOK_SIGNAL_BRIDGE.md",
        "docs/HOOK_BRIDGE_LAUNCH_AGENT.md",
        "README.md",
    ),
    "appserver_watcher": (
        "script/appserver_thread_watcher.py",
        "script/check_appserver_thread_watcher.sh",
        "script/smoke_appserver_thread_watcher.sh",
        "script/smoke_appserver_bridge.sh",
        "script/codex_appserver_bridge.py",
        "README.md",
    ),
    "observer": (
        "script/check_observer.sh",
        "script/install_observer_launch_agent.sh",
        "script/uninstall_observer_launch_agent.sh",
        "script/smoke_observer_health.sh",
        "script/codex_hook_event.py",
        "script/codex_signal_fusion.py",
        "README.md",
    ),
    "swift_ui": (
        "mac/66TaskLight/Sources/TaskLightApp/",
        "mac/66TaskLight/Sources/TaskLightCore/",
        "mac/66TaskLight/Sources/TaskLightChecks/",
        "docs/LUCKYCAT_FIGMA_COMPONENTS.md",
        "README.md",
    ),
    "launch_agent": (
        "script/check_codex_hooks_trust.py",
        "script/install_codex_hooks_status_bridge.sh",
        "script/install_hooks_for_workspace.sh",
        "script/install_hooks_for_workspaces.sh",
        "script/install_state_projector_launch_agent.sh",
        "script/uninstall_state_projector_launch_agent.sh",
        "script/install_hook_bridge_launch_agent.sh",
        "script/uninstall_hook_bridge_launch_agent.sh",
        "script/install_appserver_thread_watcher_launch_agent.sh",
        "script/uninstall_appserver_thread_watcher_launch_agent.sh",
        "script/install_observer_launch_agent.sh",
        "script/uninstall_observer_launch_agent.sh",
        "script/check_hook_bridge_launch_agent.sh",
        "script/smoke_hook_bridge_launch_agent.sh",
        "docs/CODEX_HOOKS_SETUP.md",
        "docs/CODEX_WORKSPACE_ONBOARDING.md",
        "README.md",
    ),
    "signal_bus": (
        "script/tasklight_signal_bus.py",
        "script/codex_signal_fusion.py",
        "script/smoke_signal_bus.sh",
        "script/smoke_signal_fusion.sh",
        "README.md",
    ),
    "release_audit": (
        "README.md",
        "script/check_all.sh",
        "docs/",
    ),
    "docs": (
        "docs/",
        "README.md",
    ),
}

SECRET_CONTENT_PATTERNS = (
    re.compile(r"\bsk-[A-Za-z0-9_-]{8,}\b"),
    re.compile(r"\bOPENAI_API_KEY\b"),
    re.compile(r"\bbearer\s+[A-Za-z0-9._~+/=-]{8,}\b", re.IGNORECASE),
    re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
)

LAUNCH_CONTENT_PATTERNS = (
    "trust",
    "launch_agent",
    "hook install",
    "workspace coverage",
)

CACHE_ARTIFACT_HINTS = (
    "__pycache__/",
    ".pytest_cache/",
    ".mypy_cache/",
    ".ruff_cache/",
    ".swiftpm/xcode/",
    ".swiftpm/",
    ".xcuserdata/",
    ".DS_Store",
    ".log",
    ".tmp",
    ".swp",
    ".xcresult",
)

ARTIFACT_ROOT_HINTS = (
    "dist/",
    "build/",
    ".build/",
    "DerivedData/",
    ".app/",
    ".dSYM/",
    "__pycache__/",
    ".swiftpm/xcode/",
    ".xcuserdata/",
)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Generate a 66TaskLight self-review scope candidate")
    parser.add_argument("--task-id", required=True)
    parser.add_argument("--task-type", dest="task_types", action="append", default=[])
    parser.add_argument("--output-dir")
    parser.add_argument("--include-current-staged", action="store_true")
    parser.add_argument("--include-unstaged", action="store_true")
    parser.add_argument("--format", choices=["json", "md", "both"], default="both")
    parser.add_argument("--write-scope-file", action="store_true")
    parser.add_argument("--scope-name", default="self-review-scope")
    return parser


def load_fixture() -> dict[str, Any]:
    raw_dir = os.environ.get(FIXTURE_ENV)
    if not raw_dir:
        return {}
    root = Path(raw_dir).expanduser()
    for filename in FIXTURE_FILENAMES:
        payload = load_json(root / filename, {})
        if isinstance(payload, dict) and payload:
            return payload
    return {}


def normalize_source_paths(values: list[str] | tuple[str, ...] | None) -> list[str]:
    return normalize_path_list([str(item) for item in (values or []) if str(item).strip()])


def dedupe_preserve_order(values: list[str]) -> list[str]:
    seen: set[str] = set()
    ordered: list[str] = []
    for value in values:
        normalized = normalize_rel_path(value)
        if not normalized or normalized in seen:
            continue
        seen.add(normalized)
        ordered.append(normalized)
    return ordered


def git_snapshot_live() -> dict[str, Any]:
    status_entries = git_status_entries()
    status_paths = [normalize_rel_path(str(item.get("path") or "")) for item in status_entries if str(item.get("path") or "").strip()]
    staged_from_status = [path for item, path in zip(status_entries, status_paths) if (str(item.get("status") or "  ")[:1] != " " and str(item.get("status") or "") != "??")]
    unstaged_from_status = [
        path
        for item, path in zip(status_entries, status_paths)
        if (len(str(item.get("status") or "  ")) > 1 and str(item.get("status") or "  ")[1] != " " and str(item.get("status") or "") != "??")
    ]
    untracked_from_status = [path for item, path in zip(status_entries, status_paths) if str(item.get("status") or "") == "??"]
    staged_from_diff = normalize_source_paths(git_lines("diff", "--cached", "--name-only"))
    unstaged_from_diff = normalize_source_paths(git_lines("diff", "--name-only"))
    branch = git_lines("rev-parse", "--abbrev-ref", "HEAD")
    head = git_lines("rev-parse", "--short", "HEAD")
    staged_files = dedupe_preserve_order(staged_from_status + staged_from_diff)
    unstaged_files = dedupe_preserve_order(unstaged_from_status + unstaged_from_diff)
    untracked_files = dedupe_preserve_order(untracked_from_status)
    changed_files = dedupe_preserve_order(staged_files + unstaged_files + untracked_files)
    return {
        "branch": branch[0] if branch else "unknown",
        "head": head[0] if head else "unknown",
        "status_entries": status_entries,
        "staged_files": staged_files,
        "unstaged_files": unstaged_files,
        "untracked_files": untracked_files,
        "changed_files": changed_files,
    }


def git_snapshot_from_fixture(fixture: dict[str, Any]) -> dict[str, Any]:
    staged_files = normalize_source_paths(fixture.get("staged_files") if isinstance(fixture.get("staged_files"), list) else [])
    unstaged_files = normalize_source_paths(fixture.get("unstaged_files") if isinstance(fixture.get("unstaged_files"), list) else [])
    untracked_files = normalize_source_paths(fixture.get("untracked_files") if isinstance(fixture.get("untracked_files"), list) else [])
    changed_files = dedupe_preserve_order(staged_files + unstaged_files + untracked_files)
    status_entries = fixture.get("status_entries") if isinstance(fixture.get("status_entries"), list) else []
    if not status_entries:
        status_entries = [{"status": "M ", "path": path} for path in staged_files]
        status_entries.extend({"status": " M", "path": path} for path in unstaged_files)
        status_entries.extend({"status": "??", "path": path} for path in untracked_files)
    files = fixture.get("files")
    if not isinstance(files, dict):
        files = fixture.get("file_contents") if isinstance(fixture.get("file_contents"), dict) else {}
    return {
        "branch": str(fixture.get("branch") or "scope-fixture"),
        "head": str(fixture.get("head") or "fixture"),
        "status_entries": status_entries,
        "staged_files": staged_files,
        "unstaged_files": unstaged_files,
        "untracked_files": untracked_files,
        "changed_files": changed_files,
        "files": {normalize_rel_path(str(key)): str(value) for key, value in files.items()},
    }


def task_type_scope_seeds(task_types: list[str]) -> tuple[list[str], list[str], list[str]]:
    recognized = {str(item).strip() for item in task_types if str(item).strip()}
    unknown = sorted(item for item in recognized if item not in TASK_TYPE_SCOPE_SEEDS)
    seeds: list[str] = list(UNIVERSAL_SCOPE_SEEDS)
    for task_type in sorted(recognized):
        seeds.extend(TASK_TYPE_SCOPE_SEEDS.get(task_type, ()))
    if any(task_type in recognized for task_type in {"docs", "release_audit"}):
        seeds.extend(("script/self-review/", "config/self-review/", "docs/self-review/"))
    directory_seed_raw = [normalize_rel_path(seed) for seed in seeds if seed.endswith("/")]
    return dedupe_preserve_order(seeds), unknown, dedupe_preserve_order(directory_seed_raw)


def file_text_for_path(path: str, fixture_files: dict[str, str]) -> str | None:
    normalized = normalize_rel_path(path)
    if normalized in fixture_files:
        return fixture_files[normalized]
    absolute = project_root() / normalized
    try:
        return absolute.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return None


def content_hits_launch_trust(text: str | None) -> list[str]:
    if not text:
        return []
    lowered = text.lower()
    return [phrase for phrase in LAUNCH_CONTENT_PATTERNS if phrase in lowered]


def content_hits_auth_secret(text: str | None) -> list[str]:
    if not text:
        return []
    hits: list[str] = []
    for regex in SECRET_CONTENT_PATTERNS:
        if regex.search(text):
            hits.append(regex.pattern)
    return hits


def is_docs_asset(path: str) -> bool:
    lowered = normalize_rel_path(path).lower()
    return lowered.startswith("docs/assets/") or lowered.startswith("docs/images/") or lowered.startswith("docs/static/")


def is_app_asset(path: str) -> bool:
    lowered = normalize_rel_path(path).lower()
    return ".xcassets/" in lowered or "appassets/" in lowered or lowered.startswith("mac/66tasklight/resources/")


def is_cache_artifact(path: str) -> bool:
    lowered = normalize_rel_path(path).lower()
    return any(hint.lower() in lowered for hint in CACHE_ARTIFACT_HINTS)


def artifact_exclusion_root(path: str) -> str:
    normalized = normalize_rel_path(path)
    lowered = normalized.lower()
    for hint in ARTIFACT_ROOT_HINTS:
        token = hint.lower()
        if token in lowered:
            prefix = normalized[: lowered.index(token)]
            return f"{normalize_rel_path(prefix + hint)}/"
    if normalized.endswith(".DS_Store"):
        return normalized
    if "/" in normalized:
        return f"{normalized.rsplit('/', 1)[0]}/"
    return normalized


def compact_paths(paths: list[str], collapse_parents: list[str] | tuple[str, ...] | set[str] | None = None) -> list[str]:
    selected: set[str] = set(normalize_source_paths(paths))
    collapse_set = {normalize_rel_path(path) for path in (collapse_parents or [])}
    if not selected:
        return []
    changed = True
    while changed:
        changed = False
        directories: dict[str, set[str]] = {}
        for path in sorted(selected):
            if path.endswith("/"):
                continue
            parent = path.rsplit("/", 1)[0] if "/" in path else ""
            if parent:
                directories.setdefault(f"{parent}/", set()).add(path)
        for parent, children in sorted(directories.items(), key=lambda item: (item[0].count("/"), item[0])):
            if len(children) >= 2 and normalize_rel_path(parent) in collapse_set and parent not in selected:
                selected.difference_update(children)
                selected.add(parent)
                changed = True
    ordered = sorted(selected, key=lambda item: (item.count("/"), item))
    compacted: list[str] = []
    for path in ordered:
        if any(path_has_prefix(path, existing) for existing in compacted):
            continue
        compacted.append(path)
    return compacted


def display_scope_paths(paths: list[str], directory_paths: list[str]) -> list[str]:
    directory_set = {normalize_rel_path(path) for path in directory_paths}
    formatted: list[str] = []
    for path in normalize_source_paths(paths):
        if path in directory_set:
            formatted.append(f"{path}/")
        else:
            formatted.append(path)
    return formatted


def collect_candidate_data(task_id: str, task_types: list[str]) -> dict[str, Any]:
    fixture = load_fixture()
    if fixture:
        git = git_snapshot_from_fixture(fixture)
    else:
        git = git_snapshot_live()
    fixture_files = git.get("files") if isinstance(git.get("files"), dict) else {}
    task_seeds, unknown_task_types, task_directory_seeds = task_type_scope_seeds(task_types)
    changed_files = normalize_source_paths(git.get("changed_files") if isinstance(git.get("changed_files"), list) else [])
    staged_files = normalize_source_paths(git.get("staged_files") if isinstance(git.get("staged_files"), list) else [])
    unstaged_files = normalize_source_paths(git.get("unstaged_files") if isinstance(git.get("unstaged_files"), list) else [])
    untracked_files = normalize_source_paths(git.get("untracked_files") if isinstance(git.get("untracked_files"), list) else [])

    in_scope_candidates: list[str] = []
    out_of_scope_candidates: list[str] = []
    risky_launch_trust: list[str] = []
    risky_auth_secret: list[str] = []
    build_artifacts: list[str] = []
    cache_artifacts: list[str] = []
    docs_assets: list[str] = []
    app_assets: list[str] = []
    unknown: list[str] = []
    notes: list[dict[str, Any]] = []
    file_reasons: dict[str, list[str]] = {}

    build_hits = build_artifacts_in_paths(changed_files)
    for path in changed_files:
        text = file_text_for_path(path, fixture_files)
        reasons: list[str] = []
        if path in build_hits:
            build_artifacts.append(path)
            reasons.append("build artifact path")
        if is_cache_artifact(path):
            cache_artifacts.append(path)
            reasons.append("cache artifact path")
        if is_docs_asset(path):
            docs_assets.append(path)
            reasons.append("docs asset path")
        if is_app_asset(path):
            app_assets.append(path)
            reasons.append("app asset path")
        launch_hits = []
        if path_has_launch_trust_risk(path):
            launch_hits.append("path")
        launch_hits.extend(content_hits_launch_trust(text))
        if launch_hits:
            risky_launch_trust.append(path)
            reasons.append(f"launch/trust match: {', '.join(sorted(set(launch_hits)))}")
        auth_hits = []
        if path_has_auth_secret_risk(path):
            auth_hits.append("path")
        auth_hits.extend(content_hits_auth_secret(text))
        if auth_hits:
            risky_auth_secret.append(path)
            reasons.append(f"auth/secret match: {', '.join(sorted(set(auth_hits)))}")
        if any(path_has_prefix(path, seed) for seed in task_seeds):
            in_scope_candidates.append(path)
        else:
            out_of_scope_candidates.append(path)
            if not reasons:
                unknown.append(path)
                reasons.append("no known scope classifier matched")
        if reasons:
            file_reasons[path] = reasons

    include_seed_paths = display_scope_paths(compact_paths(task_seeds + in_scope_candidates, task_directory_seeds), task_directory_seeds)
    artifact_roots = [artifact_exclusion_root(path) for path in build_artifacts + cache_artifacts]
    exclude_roots = display_scope_paths(compact_paths(artifact_roots, [path for path in artifact_roots if path.endswith("/")]), [path for path in artifact_roots if path.endswith("/")])
    has_launch_trust = bool(risky_launch_trust)
    has_auth_secret = bool(risky_auth_secret)
    non_artifact_out_of_scope = [
        path
        for path in out_of_scope_candidates
        if path not in build_artifacts and path not in cache_artifacts
    ]
    if has_auth_secret:
        recommended_decision = "REJECT"
    elif has_launch_trust:
        recommended_decision = "NEEDS_HUMAN_REVIEW"
    elif non_artifact_out_of_scope:
        recommended_decision = "CONDITIONAL_PASS"
    elif build_artifacts or cache_artifacts:
        recommended_decision = "PASS"
    else:
        recommended_decision = "PASS"

    notes.append(
        {
            "type": "scope_sources",
            "value": "default staged + unstaged diff",
            "staged_files": staged_files,
            "unstaged_files": unstaged_files,
            "untracked_files": untracked_files,
        }
    )
    if unknown_task_types:
        notes.append({"type": "unknown_task_types", "value": unknown_task_types})
    for path in sorted(set(risky_launch_trust)):
        notes.append(
            {
                "type": "risky_launch_trust",
                "path": path,
                "reason": "; ".join(file_reasons.get(path, [])) or "launch/trust classifier matched",
            }
        )
    for path in sorted(set(risky_auth_secret)):
        notes.append(
            {
                "type": "risky_auth_secret",
                "path": path,
                "reason": "; ".join(file_reasons.get(path, [])) or "auth/secret classifier matched",
            }
        )
    if build_artifacts:
        notes.append({"type": "build_artifacts", "value": sorted(set(build_artifacts))})
    if cache_artifacts:
        notes.append({"type": "cache_artifacts", "value": sorted(set(cache_artifacts))})

    classification = {
        "in_scope_candidates": sorted(set(in_scope_candidates)),
        "out_of_scope_candidates": sorted(set(out_of_scope_candidates)),
        "risky_launch_trust": sorted(set(risky_launch_trust)),
        "risky_auth_secret": sorted(set(risky_auth_secret)),
        "build_artifacts": sorted(set(build_artifacts)),
        "cache_artifacts": sorted(set(cache_artifacts)),
        "docs_assets": sorted(set(docs_assets)),
        "app_assets": sorted(set(app_assets)),
        "unknown": sorted(set(unknown)),
    }
    recommendation = {
        "include": include_seed_paths,
        "exclude": exclude_roots,
        "reason": "Generated from current git diff and task types.",
    }
    risk_summary = {
        "has_launch_trust": has_launch_trust,
        "has_auth_secret": has_auth_secret,
        "has_build_artifacts": bool(build_artifacts),
        "requires_human_review": has_launch_trust or has_auth_secret,
        "recommended_decision": recommended_decision,
    }
    return {
        "task_id": task_id,
        "task_types": normalize_source_paths(task_types),
        "git": {
            "branch": git.get("branch"),
            "head": git.get("head"),
            "staged_files": staged_files,
            "unstaged_files": unstaged_files,
            "untracked_files": untracked_files,
        },
        "classification": classification,
        "recommendation": recommendation,
        "risk_summary": risk_summary,
        "notes": notes,
        "file_reasons": file_reasons,
    }


def render_markdown(payload: dict[str, Any], scope_file_path: Path | None) -> str:
    classification = payload.get("classification") if isinstance(payload.get("classification"), dict) else {}
    recommendation = payload.get("recommendation") if isinstance(payload.get("recommendation"), dict) else {}
    risk_summary = payload.get("risk_summary") if isinstance(payload.get("risk_summary"), dict) else {}
    notes = payload.get("notes") if isinstance(payload.get("notes"), list) else []
    file_reasons = payload.get("file_reasons") if isinstance(payload.get("file_reasons"), dict) else {}
    lines = [
        f"# Scope Candidate {payload.get('task_id')}",
        "",
        f"- Task ID: `{payload.get('task_id')}`",
        f"- Task Types: `{', '.join(payload.get('task_types') or [])}`",
        f"- Generated At: `{payload.get('generated_at')}`",
        f"- Recommended Decision: `{risk_summary.get('recommended_decision')}`",
        "",
        "## Recommended Include Paths",
    ]
    include = recommendation.get("include") or []
    if include:
        for path in include:
            lines.append(f"- `{path}`")
    else:
        lines.append("- none")
    lines.extend(["", "## Recommended Exclude Paths"])
    exclude = recommendation.get("exclude") or []
    if exclude:
        for path in exclude:
            lines.append(f"- `{path}`")
    else:
        lines.append("- none")
    lines.extend(["", "## In-Scope Candidate Files"])
    in_scope = classification.get("in_scope_candidates") or []
    if in_scope:
        for path in in_scope:
            lines.append(f"- `{path}`")
    else:
        lines.append("- none")
    lines.extend(["", "## Out-of-Scope Dirty Files"])
    out_of_scope = classification.get("out_of_scope_candidates") or []
    if out_of_scope:
        for path in out_of_scope:
            lines.append(f"- `{path}`")
    else:
        lines.append("- none")
    lines.extend(["", "## Risk Classification"])
    for label in ("risky_launch_trust", "risky_auth_secret", "build_artifacts", "cache_artifacts", "docs_assets", "app_assets", "unknown"):
        values = classification.get(label) or []
        lines.append(f"- `{label}`: `{len(values)}`")
    lines.extend(["", "## Why Risky Files Were Classified"])
    risky_paths = sorted(set((classification.get("risky_launch_trust") or []) + (classification.get("risky_auth_secret") or [])))
    if risky_paths:
        for path in risky_paths:
            reasons = file_reasons.get(path) or []
            lines.append(f"- `{path}`: {', '.join(reasons) if reasons else 'classifier matched'}")
    else:
        lines.append("- none")
    lines.extend(["", "## Suggested Command"])
    if scope_file_path is not None:
        task_type_args = " ".join(f"--task-type {task_type}" for task_type in (payload.get("task_types") or []))
        lines.append("```bash")
        command = [
            "python3 script/self-review/run_self_review.py",
            f"--task-id {payload.get('task_id')}",
            task_type_args,
            f"--scope-file {scope_file_path}",
            "--evidence-profile full",
            "--mode final",
        ]
        lines.append(" ".join(item for item in command if item))
        lines.append("```")
    else:
        lines.append("- Rerun with `--write-scope-file` to materialize a scope file, then feed it to `run_self_review.py`.")
    if risk_summary.get("has_launch_trust") or risk_summary.get("has_auth_secret"):
        lines.extend(["", "## Human Review Warning", "- Launch/trust or auth/secret risk exists. Do not auto-apply this scope without review."])
    return "\n".join(lines) + "\n"


def write_outputs(payload: dict[str, Any], output_dir: Path, format_name: str, write_scope_file: bool, scope_name: str) -> dict[str, str]:
    output_dir.mkdir(parents=True, exist_ok=True)
    candidate_json_path = output_dir / "scope-candidate.json"
    candidate_md_path = output_dir / "scope-candidate.md"
    scope_file_path = output_dir / f"{scope_name}.json" if write_scope_file else None
    if format_name in {"json", "both"}:
        atomic_write_json(candidate_json_path, payload)
    if format_name in {"md", "both"}:
        atomic_write(candidate_md_path, render_markdown(payload, scope_file_path))
    if write_scope_file and scope_file_path is not None:
        scope_payload = {
            "task_id": payload.get("task_id"),
            "include": payload.get("recommendation", {}).get("include") or [],
            "exclude": payload.get("recommendation", {}).get("exclude") or [],
            "reason": "Auto-generated scope candidate. Review manually before use.",
        }
        atomic_write_json(scope_file_path, scope_payload)
    return {
        "candidate_json_path": str(candidate_json_path),
        "candidate_md_path": str(candidate_md_path),
        "scope_file_path": str(scope_file_path) if scope_file_path is not None else "",
    }


def main() -> None:
    args = build_parser().parse_args()
    output_dir = Path(args.output_dir).expanduser() if args.output_dir else report_directory(args.task_id)
    payload = collect_candidate_data(args.task_id, args.task_types)
    payload["schema_version"] = "0.1"
    payload["generated_at"] = now_iso()
    payload["source"] = "generate_scope.py"
    payload["include_current_staged"] = bool(args.include_current_staged)
    payload["include_unstaged"] = bool(args.include_unstaged)
    scope_file_path = output_dir / f"{args.scope_name}.json" if args.write_scope_file else None
    payload["outputs"] = {
        "candidate_json_path": str(output_dir / "scope-candidate.json"),
        "candidate_md_path": str(output_dir / "scope-candidate.md"),
        "scope_file_path": str(scope_file_path) if scope_file_path is not None else "",
    }
    write_outputs(payload, output_dir, args.format, args.write_scope_file, args.scope_name)
    summary = {
        "task_id": args.task_id,
        "task_types": normalize_source_paths(args.task_types),
        "output_dir": str(output_dir),
        "scope_candidate_json": payload["outputs"]["candidate_json_path"],
        "scope_candidate_md": payload["outputs"]["candidate_md_path"],
        "scope_file": payload["outputs"]["scope_file_path"],
        "recommended_decision": payload["risk_summary"]["recommended_decision"],
    }
    print(json.dumps(summary, ensure_ascii=True, sort_keys=True, indent=2))


if __name__ == "__main__":
    main()
