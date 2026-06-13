#!/usr/bin/env python3
"""Shared helpers for the 66TaskLight Self-Review Arbiter."""

from __future__ import annotations

import json
import os
import re
import subprocess
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


PROJECT_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_STATE_DIR = Path.home() / ".66tasklight"
BUILD_ARTIFACT_PATTERNS = (
    ".build/",
    "DerivedData/",
    ".app/",
    ".dSYM/",
    "build/",
)
SUSPICIOUS_BUILD_SUFFIXES = (".app", ".dSYM", ".o", ".swiftmodule", ".swiftdoc")
LAUNCH_TRUST_PATH_HINTS = (
    "launch_agent",
    "launchagents",
    "hooks_trust",
    "hook_trust",
    "check_codex_hooks_trust",
    ".plist",
    "security",
    "trust",
)
AUTH_SECRET_PATH_HINTS = (
    ".codex/auth.json",
    "auth.json",
    ".env",
    "secret",
    "credential",
    "auth_token",
    "api_key",
)


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def project_root() -> Path:
    return PROJECT_ROOT


def state_dir() -> Path:
    return Path(os.environ.get("TASKLIGHT_STATE_DIR", str(DEFAULT_STATE_DIR))).expanduser()


def ui_state_path() -> Path:
    return Path(os.environ.get("TASKLIGHT_UI_STATE_PATH", str(state_dir() / "ui_state.json"))).expanduser()


def signal_bus_path() -> Path:
    return Path(
        os.environ.get("TASKLIGHT_NORMALIZED_SIGNALS_PATH", str(state_dir() / "normalized_signals.jsonl"))
    ).expanduser()


def tasks_dir() -> Path:
    return Path(os.environ.get("TASKLIGHT_TASKS_DIR", str(state_dir() / "tasks"))).expanduser()


def config_dir() -> Path:
    return project_root() / "config" / "self-review"


def report_root() -> Path:
    return Path(
        os.environ.get(
            "TASKLIGHT_SELF_REVIEW_REPORT_ROOT",
            str(project_root() / "docs" / "reports" / "self-review"),
        )
    ).expanduser()


def self_review_docs_dir() -> Path:
    return project_root() / "docs" / "self-review"


def load_json(path: Path, default: Any) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return default


def dump_json(payload: Any) -> str:
    return json.dumps(payload, ensure_ascii=True, sort_keys=True, indent=2) + "\n"


def atomic_write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        handle.write(text)
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(tmp_name, path)


def atomic_write_json(path: Path, payload: Any) -> None:
    atomic_write(path, dump_json(payload))


def slugify(value: str) -> str:
    text = re.sub(r"[^A-Za-z0-9._-]+", "-", value.strip())
    text = re.sub(r"-{2,}", "-", text).strip("-")
    return text or "self-review"


def normalize_rel_path(value: str) -> str:
    text = str(value or "").replace("\\", "/").strip()
    while text.startswith("./"):
        text = text[2:]
    if text.endswith("/") and text != "/":
        text = text.rstrip("/")
    return text


def normalize_path_list(values: list[str] | tuple[str, ...] | None) -> list[str]:
    if not values:
        return []
    normalized = [normalize_rel_path(value) for value in values if normalize_rel_path(value)]
    return sorted(set(normalized))


def run_subprocess(argv: list[str], *, cwd: Path | None = None, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        argv,
        cwd=str(cwd or project_root()),
        text=True,
        capture_output=True,
        check=False,
        env=env,
    )


def fixture_dir() -> Path | None:
    raw = os.environ.get("TASKLIGHT_SELF_REVIEW_FIXTURE_DIR")
    if not raw:
        return None
    return Path(raw).expanduser()


def fixture_command_result(command_id: str) -> dict[str, Any] | None:
    root = fixture_dir()
    if root is None:
        return None
    payload = load_json(root / "command-results.json", {})
    result = payload.get(command_id)
    return result if isinstance(result, dict) else None


def fixture_baseline_overrides() -> dict[str, Any]:
    root = fixture_dir()
    if root is None:
        return {}
    payload = load_json(root / "baseline-overrides.json", {})
    return payload if isinstance(payload, dict) else {}


def parse_scope_file(path: str | None) -> dict[str, Any]:
    if not path:
        return {}
    payload = load_json(Path(path).expanduser(), {})
    return payload if isinstance(payload, dict) else {}


def build_review_scope(task_id: str, *, scope_file: str | None, review_paths: list[str] | None, exclude_paths: list[str] | None) -> dict[str, Any]:
    scope_payload = parse_scope_file(scope_file)
    scope_task_id = str(scope_payload.get("task_id") or "").strip()
    if scope_task_id and scope_task_id != task_id:
        raise SystemExit(f"scope file task_id mismatch: expected {task_id}, got {scope_task_id}")

    include = normalize_path_list((scope_payload.get("include") if isinstance(scope_payload.get("include"), list) else []) + list(review_paths or []))
    exclude = normalize_path_list((scope_payload.get("exclude") if isinstance(scope_payload.get("exclude"), list) else []) + list(exclude_paths or []))
    enabled = bool(scope_file or include or exclude)
    return {
        "schema_version": "0.1",
        "enabled": enabled,
        "mode": "scoped" if enabled else "whole_worktree",
        "scope_file": str(Path(scope_file).expanduser()) if scope_file else None,
        "task_id": task_id,
        "source_task_id": scope_task_id or None,
        "reason": str(scope_payload.get("reason") or "").strip(),
        "include": include,
        "exclude": exclude,
    }


def parse_key_values(text: str) -> dict[str, Any]:
    pairs: dict[str, Any] = {}
    for raw in text.splitlines():
        line = raw.strip()
        if not line or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if not key:
            continue
        if value.startswith("{") or value.startswith("["):
            try:
                pairs[key] = json.loads(value)
                continue
            except json.JSONDecodeError:
                pass
        pairs[key] = value
    return pairs


def sanitize_status_line(text: str) -> str | None:
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    if not lines:
        return None
    candidate = lines[-1][:240]
    lowered = candidate.lower()
    if any(token in lowered for token in ("prompt", "response", "auth", "raw log")):
        return None
    return candidate


def run_command(command_id: str, argv: list[str], *, env: dict[str, str] | None = None) -> dict[str, Any]:
    fixture = fixture_command_result(command_id)
    if fixture is not None:
        result = {
            "command_id": command_id,
            "argv": argv,
            "mode": "fixture",
            "exit_code": int(fixture.get("exit_code", 0)),
            "duration_sec": float(fixture.get("duration_sec", 0.0)),
            "passed": int(fixture.get("exit_code", 0)) == 0,
            "key_values": fixture.get("key_values") if isinstance(fixture.get("key_values"), dict) else {},
            "status_line": fixture.get("status_line"),
            "line_count": int(fixture.get("line_count", 0)),
        }
        return result

    started = time.time()
    completed = run_subprocess(argv, cwd=project_root(), env=env)
    output = "\n".join(part for part in [completed.stdout, completed.stderr] if part).strip()
    return {
        "command_id": command_id,
        "argv": argv,
        "mode": "live",
        "exit_code": completed.returncode,
        "duration_sec": round(time.time() - started, 3),
        "passed": completed.returncode == 0,
        "key_values": parse_key_values(output),
        "status_line": sanitize_status_line(output),
        "line_count": len(output.splitlines()) if output else 0,
    }


def git_lines(*args: str) -> list[str]:
    completed = run_subprocess(["git", *args], cwd=project_root())
    if completed.returncode != 0:
        return []
    return [line.rstrip("\n") for line in completed.stdout.splitlines()]


def git_status_entries() -> list[dict[str, str]]:
    entries: list[dict[str, str]] = []
    for line in git_lines("status", "--short"):
        if not line.strip():
            continue
        status = line[:2]
        path = line[3:] if len(line) > 3 else ""
        entries.append({"status": status, "path": path})
    return entries


def path_has_prefix(path: str, prefix: str) -> bool:
    normalized_path = normalize_rel_path(path)
    normalized_prefix = normalize_rel_path(prefix)
    return normalized_path == normalized_prefix or normalized_path.startswith(normalized_prefix + "/")


def path_in_review_scope(path: str, scope: dict[str, Any]) -> bool:
    normalized = normalize_rel_path(path)
    includes = normalize_path_list(scope.get("include"))
    excludes = normalize_path_list(scope.get("exclude"))
    if excludes and any(path_has_prefix(normalized, item) for item in excludes):
        return False
    if not bool(scope.get("enabled", False)):
        return True
    if not includes:
        return True
    return any(path_has_prefix(normalized, item) for item in includes)


def is_staged_status(status: str) -> bool:
    return bool(status) and status[0] not in {" ", "?"}


def build_status_entries_from_paths(changed_files: list[str], staged_files: list[str]) -> list[dict[str, str]]:
    staged_set = {normalize_rel_path(path) for path in staged_files}
    entries: list[dict[str, str]] = []
    for path in normalize_path_list(changed_files):
        status = "M " if path in staged_set else " M"
        entries.append({"status": status, "path": path})
    return entries


def apply_scope_to_git_payload(raw: dict[str, Any], scope: dict[str, Any]) -> dict[str, Any]:
    branch = str(raw.get("branch") or "unknown")
    head = str(raw.get("head") or "unknown")
    status_entries = raw.get("status_entries") if isinstance(raw.get("status_entries"), list) else []
    normalized_entries = []
    for item in status_entries:
        if not isinstance(item, dict):
            continue
        path = normalize_rel_path(str(item.get("path") or ""))
        if not path:
            continue
        normalized_entries.append({"status": str(item.get("status") or "??")[:2], "path": path})
    if not normalized_entries:
        changed_files = [str(item) for item in (raw.get("changed_files") or raw.get("all_changed_files") or [])]
        staged_files = [str(item) for item in (raw.get("staged_files") or raw.get("all_staged_files") or [])]
        normalized_entries = build_status_entries_from_paths(changed_files, staged_files)

    all_changed_files = sorted({entry["path"] for entry in normalized_entries})
    all_staged_files = sorted({entry["path"] for entry in normalized_entries if is_staged_status(entry.get("status", ""))})
    in_scope_entries = [entry for entry in normalized_entries if path_in_review_scope(entry["path"], scope)]
    out_of_scope_entries = [entry for entry in normalized_entries if not path_in_review_scope(entry["path"], scope)]
    changed_files = sorted({entry["path"] for entry in in_scope_entries})
    staged_files = sorted({entry["path"] for entry in in_scope_entries if is_staged_status(entry.get("status", ""))})
    out_of_scope_dirty_files = sorted({entry["path"] for entry in out_of_scope_entries})
    out_of_scope_staged_files = sorted({entry["path"] for entry in out_of_scope_entries if is_staged_status(entry.get("status", ""))})
    return {
        "branch": branch,
        "head": head,
        "status_entries": in_scope_entries,
        "changed_files": changed_files,
        "staged_files": staged_files,
        "all_status_entries": normalized_entries,
        "all_changed_files": all_changed_files,
        "all_staged_files": all_staged_files,
        "out_of_scope_status_entries": out_of_scope_entries,
        "out_of_scope_dirty_files": out_of_scope_dirty_files,
        "out_of_scope_staged_files": out_of_scope_staged_files,
        "scope": scope,
    }


def changed_file_paths() -> list[str]:
    paths = {entry["path"] for entry in git_status_entries() if entry.get("path")}
    return sorted(paths)


def staged_file_paths() -> list[str]:
    return sorted(set(git_lines("diff", "--cached", "--name-only")))


def build_artifacts_in_paths(paths: list[str]) -> list[str]:
    hits: list[str] = []
    for path in paths:
        if any(pattern in path for pattern in BUILD_ARTIFACT_PATTERNS):
            hits.append(path)
            continue
        if path.endswith(SUSPICIOUS_BUILD_SUFFIXES):
            hits.append(path)
    return sorted(set(hits))


def path_has_any_hint(path: str, hints: tuple[str, ...]) -> bool:
    lowered = normalize_rel_path(path).lower()
    return any(hint in lowered for hint in hints)


def path_has_launch_trust_risk(path: str) -> bool:
    return path_has_any_hint(path, LAUNCH_TRUST_PATH_HINTS)


def path_has_auth_secret_risk(path: str) -> bool:
    return path_has_any_hint(path, AUTH_SECRET_PATH_HINTS)


def classify_dirty_paths(paths: list[str]) -> dict[str, list[str]]:
    ordinary: list[str] = []
    launch_trust: list[str] = []
    auth_secret: list[str] = []
    for path in normalize_path_list(paths):
        if path_has_auth_secret_risk(path):
            auth_secret.append(path)
        elif path_has_launch_trust_risk(path):
            launch_trust.append(path)
        else:
            ordinary.append(path)
    return {
        "ordinary": ordinary,
        "launch_trust": launch_trust,
        "auth_secret": auth_secret,
    }


def classify_dirty_paths_with_unknown(paths: list[str]) -> dict[str, list[str]]:
    classified = classify_dirty_paths(paths)
    unknown: list[str] = []
    for path in normalize_path_list(paths):
        if not path:
            unknown.append(path)
        elif any(ch in path for ch in ("\x00", "\n", "\r")):
            unknown.append(path)
    classified["unknown"] = sorted(set(unknown))
    return classified


def scope_reason_text(scope: dict[str, Any], out_of_scope_risk_classes: dict[str, list[str]]) -> str:
    reason = str(scope.get("reason") or "").strip()
    if reason:
        return reason
    if not bool(scope.get("enabled", False)):
        return "Whole working tree review."
    if out_of_scope_risk_classes.get("auth_secret"):
        return "Out-of-scope auth/secret files require rejection."
    if out_of_scope_risk_classes.get("launch_trust"):
        return "Out-of-scope launch/trust files require human review."
    if out_of_scope_risk_classes.get("ordinary") or out_of_scope_risk_classes.get("unknown"):
        return "Out-of-scope dirty files remain outside the scoped task."
    return "Scoped review stayed inside the included paths."


def build_scope_summary(task_id: str, baseline: dict[str, Any], safety: dict[str, Any]) -> dict[str, Any]:
    scope = baseline.get("review_scope") if isinstance(baseline.get("review_scope"), dict) else {}
    git = baseline.get("git") if isinstance(baseline.get("git"), dict) else {}
    out_of_scope_risk_classes = classify_dirty_paths_with_unknown(
        [str(item) for item in (git.get("out_of_scope_dirty_files") or [])]
    )
    summary_scope_decision = str((safety.get("summary") or {}).get("scope_decision") or "PASS")
    payload = {
        "schema_version": "0.1",
        "task_id": task_id,
        "review_scope": str(scope.get("mode") or "whole_worktree"),
        "included_paths": normalize_path_list(scope.get("include") if isinstance(scope.get("include"), list) else []),
        "excluded_paths": normalize_path_list(scope.get("exclude") if isinstance(scope.get("exclude"), list) else []),
        "in_scope_changed_files": normalize_path_list([str(item) for item in (git.get("changed_files") or [])]),
        "out_of_scope_dirty_files": normalize_path_list([str(item) for item in (git.get("out_of_scope_dirty_files") or [])]),
        "out_of_scope_risk_classes": out_of_scope_risk_classes,
        "scope_decision": summary_scope_decision,
        "scope_reason": scope_reason_text(scope, out_of_scope_risk_classes),
        "generated_at": now_iso(),
    }
    return payload


def load_signal_records(limit: int = 80) -> list[dict[str, Any]]:
    path = signal_bus_path()
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError:
        return []
    records: list[dict[str, Any]] = []
    for raw in lines[-limit:]:
        raw = raw.strip()
        if not raw:
            continue
        try:
            payload = json.loads(raw)
        except json.JSONDecodeError:
            continue
        if isinstance(payload, dict):
            records.append(payload)
    return records


def summarize_signal_bus(records: list[dict[str, Any]]) -> dict[str, Any]:
    source_counts: dict[str, int] = {}
    recent_sources: list[str] = []
    recent_event_types: list[str] = []
    latest_private_quality = None
    latest_private_scope = None
    latest_verified = False
    latest_stop = False
    for item in records:
        source = str(item.get("source") or "unknown")
        source_counts[source] = source_counts.get(source, 0) + 1
        recent_sources.append(source)
        recent_event_types.append(str(item.get("event_type") or "unknown"))
        if source == "codex_private_probe":
            latest_private_quality = item.get("source_quality")
            latest_private_scope = "thread" if item.get("thread_scoped") else "global"
        if str(item.get("event_type") or "") in {"verified", "verify"}:
            latest_verified = True
        if str(item.get("event_type") or "").lower() == "stop":
            latest_stop = True
    recent_source_set = sorted(set(recent_sources[-8:]))
    recent_event_set = sorted(set(recent_event_types[-8:]))
    return {
        "record_count": len(records),
        "source_counts": source_counts,
        "recent_source_set": recent_source_set,
        "recent_event_set": recent_event_set,
        "latest_private_probe_quality": latest_private_quality,
        "latest_private_probe_scope": latest_private_scope,
        "has_recent_verified_signal": latest_verified,
        "has_recent_stop_signal": latest_stop,
    }


def summarize_tasks() -> dict[str, Any]:
    counts: dict[str, int] = {}
    root = tasks_dir()
    if not root.exists():
        return {"status_counts": counts, "task_count": 0}
    task_count = 0
    for path in sorted(root.glob("*.json")):
        payload = load_json(path, {})
        if not isinstance(payload, dict):
            continue
        task_count += 1
        status = str(payload.get("status") or "unknown")
        counts[status] = counts.get(status, 0) + 1
    return {"status_counts": counts, "task_count": task_count}


def summarize_ui_state() -> dict[str, Any]:
    payload = load_json(ui_state_path(), {})
    diagnostics = payload.get("diagnostics") if isinstance(payload.get("diagnostics"), dict) else {}
    counts = payload.get("counts") if isinstance(payload.get("counts"), dict) else {}
    return {
        "path": str(ui_state_path()),
        "exists": ui_state_path().exists(),
        "source": payload.get("source"),
        "projector_version": payload.get("projector_version"),
        "global_status": payload.get("global_status"),
        "global_display_title": payload.get("global_display_title"),
        "lamp_status": payload.get("lamp_status"),
        "writer_status": diagnostics.get("writer_status"),
        "fallback_reason": diagnostics.get("fallback_reason"),
        "projector_reason": diagnostics.get("projector_reason"),
        "counts": counts,
    }


def report_directory(task_id: str) -> Path:
    return report_root() / slugify(task_id)
