#!/usr/bin/env python3
"""Capture sanitized status-mismatch cases and turn them into regression fixtures."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_STATE_DIR = Path.home() / ".66tasklight"
EXPECTED_STATUSES = {"idle", "running", "blocked", "pending", "done"}


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def compact_time() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def safe_hash(value: Any) -> str | None:
    if value in (None, ""):
        return None
    return hashlib.sha256(str(value).encode("utf-8")).hexdigest()[:16]


def load_json(path: Path, default: Any) -> Any:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return default
    return payload


def atomic_write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=True, sort_keys=True, indent=2)
        handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(tmp_name, path)


def state_dir() -> Path:
    return Path(os.environ.get("TASKLIGHT_STATE_DIR", str(DEFAULT_STATE_DIR))).expanduser()


def ui_state_path(root: Path) -> Path:
    return Path(os.environ.get("TASKLIGHT_UI_STATE_PATH", str(root / "ui_state.json"))).expanduser()


def signals_path(root: Path) -> Path:
    return Path(os.environ.get("TASKLIGHT_NORMALIZED_SIGNALS_PATH", str(root / "normalized_signals.jsonl"))).expanduser()


def reflection_root() -> Path:
    return Path(os.environ.get("TASKLIGHT_STATUS_REFLECTION_DIR", str(PROJECT_ROOT / "docs" / "status-reflections"))).expanduser()


def normalized_status(value: Any) -> str:
    text = str(value or "idle")
    if text == "done_verified":
        return "done"
    if text == "done_unverified":
        return "pending"
    return text if text in EXPECTED_STATUSES else "idle"


def summarize_counts(counts: Any) -> dict[str, int]:
    if not isinstance(counts, dict):
        return {}
    keys = [
        "blocked",
        "stale",
        "running",
        "queued",
        "pending_verify_count",
        "done_verified_visible",
        "observed_active",
        "managed_active",
        "appserver_active",
        "process_observed",
    ]
    return {key: int(counts.get(key) or 0) for key in keys}


def sanitize_runtime_candidate(candidate: dict[str, Any]) -> dict[str, Any]:
    return {
        "candidate_id_hash": safe_hash(candidate.get("candidate_id")),
        "source_set": candidate.get("source_set") or [],
        "display_scope": candidate.get("display_scope"),
        "runtime_score": candidate.get("runtime_score"),
        "state_cause": candidate.get("state_cause"),
        "age_sec": candidate.get("age_sec"),
        "why_active": candidate.get("why_active"),
        "why_ignored": candidate.get("why_ignored"),
    }


def summarize_ui_state(payload: dict[str, Any]) -> dict[str, Any]:
    diagnostics = payload.get("diagnostics") if isinstance(payload.get("diagnostics"), dict) else {}
    candidates = payload.get("runtime_candidates")
    if not isinstance(candidates, list):
        candidates = diagnostics.get("top_runtime_candidates") if isinstance(diagnostics.get("top_runtime_candidates"), list) else []
    return {
        "source": payload.get("source"),
        "projector_version": payload.get("projector_version"),
        "global_status": payload.get("global_status"),
        "global_display_title": payload.get("global_display_title"),
        "lamp_status": payload.get("lamp_status"),
        "projector_generated_at": payload.get("projector_generated_at"),
        "counts": summarize_counts(payload.get("counts")),
        "diagnostics": {
            "hook_bridge_status": diagnostics.get("hook_bridge_status"),
            "writer_status": diagnostics.get("writer_status"),
            "fallback_reason": diagnostics.get("fallback_reason"),
            "projector_reason": diagnostics.get("projector_reason") or [],
            "runtime_candidate_count": diagnostics.get("runtime_candidate_count"),
            "appserver_active_count": diagnostics.get("appserver_active_count"),
            "process_observed_count": diagnostics.get("process_observed_count"),
        },
        "top_runtime_candidates": [sanitize_runtime_candidate(item) for item in candidates[:5] if isinstance(item, dict)],
    }


def sanitize_thread(item: dict[str, Any]) -> dict[str, Any]:
    return {
        "thread_id_hash": safe_hash(item.get("thread_id")),
        "turn_id_hash": safe_hash(item.get("turn_id")),
        "workspace_hash": safe_hash(item.get("workspace")),
        "hook_status": item.get("hook_status"),
        "latest_hook_signal_age_sec": item.get("latest_hook_signal_age_sec"),
        "latest_signal_age_sec": item.get("latest_signal_age_sec"),
        "appserver_status": item.get("appserver_status"),
        "projector_scope": item.get("projector_scope"),
        "ui_effect": item.get("ui_effect"),
        "decision": item.get("decision"),
        "reason": item.get("reason"),
        "explanation": item.get("explanation"),
        "source_set": item.get("source_set") or [],
        "recommended_fixture": item.get("recommended_fixture"),
    }


def summarize_coverage(report: dict[str, Any]) -> dict[str, Any]:
    return {
        "status": report.get("status"),
        "recommended_action": report.get("recommended_action"),
        "summary": report.get("summary") or {},
        "recommended_fixture": report.get("recommended_fixture"),
        "recommended_fixtures": report.get("recommended_fixtures") or [],
        "threads": [sanitize_thread(item) for item in (report.get("threads") or [])[:20] if isinstance(item, dict)],
    }


def run_coverage(root: Path, args: argparse.Namespace) -> dict[str, Any]:
    command = [
        sys.executable,
        str(PROJECT_ROOT / "script" / "check_codex_thread_coverage.py"),
        "--json",
        "--state-dir",
        str(root),
        "--signals-path",
        str(signals_path(root)),
        "--appserver-timeout",
        str(args.appserver_timeout),
    ]
    for workspace in args.workspace or []:
        command.extend(["--workspace", workspace])
    if args.skip_appserver:
        command.append("--skip-appserver")
    completed = subprocess.run(command, cwd=str(PROJECT_ROOT), text=True, capture_output=True, timeout=max(5.0, args.appserver_timeout + 5.0))
    if completed.returncode != 0:
        return {
            "status": "error",
            "recommended_action": "coverage command failed",
            "summary": {},
            "threads": [],
            "error": completed.stderr.strip()[:500],
        }
    try:
        return json.loads(completed.stdout)
    except json.JSONDecodeError:
        return {
            "status": "error",
            "recommended_action": "coverage output was not json",
            "summary": {},
            "threads": [],
        }


def choose_recommended_fixture(coverage: dict[str, Any], expected: str, actual: str) -> dict[str, Any]:
    fixtures = coverage.get("recommended_fixtures") or []
    if fixtures:
        preferred = sorted(
            [fixture for fixture in fixtures if isinstance(fixture, dict)],
            key=lambda item: (
                item.get("decision") != "uncovered_active_suspect",
                item.get("decision") != "diagnostic_only",
                item.get("decision") != "covered_running",
            ),
        )
        if preferred:
            fixture = dict(preferred[0])
            fixture["expected_status"] = expected
            fixture["actual_status"] = actual
            return fixture
    return {
        "schema_version": "0.1",
        "source": "none",
        "event_type": "none",
        "thread_id_hash": None,
        "turn_id_hash": None,
        "workspace_hash": None,
        "status_hint": None,
        "decision": "no_thread_signal",
        "reason": "no_coverage_fixture_available",
        "expected_projector_result": expected,
        "expected_status": expected,
        "actual_status": actual,
    }


def case_id(expected: str, actual: str) -> str:
    return f"{compact_time()}-{expected}-{actual}"


def capture_case(args: argparse.Namespace) -> Path:
    root = Path(args.state_dir).expanduser()
    ui_payload = load_json(ui_state_path(root), {})
    actual = normalized_status(ui_payload.get("global_status"))
    expected = args.expected
    coverage = run_coverage(root, args)
    selected_fixture = choose_recommended_fixture(coverage, expected, actual)
    cid = args.case_id or case_id(expected, actual)
    output = Path(args.output) if args.output else reflection_root() / "cases" / f"{cid}.json"
    payload = {
        "schema_version": "0.1",
        "case_id": cid,
        "created_at": now_iso(),
        "expected_status": expected,
        "actual_status": actual,
        "match": expected == actual,
        "note": args.note or "",
        "ui_state_summary": summarize_ui_state(ui_payload),
        "coverage_summary": summarize_coverage(coverage),
        "recommended_fixture": selected_fixture,
        "safe_evidence": {
            "state_dir_hash": safe_hash(root),
            "ui_state_path_hash": safe_hash(ui_state_path(root)),
            "signals_path_hash": safe_hash(signals_path(root)),
            "signal_count": (coverage.get("metadata") or {}).get("signal_count"),
            "coverage_status": coverage.get("status"),
            "coverage_recommended_action": coverage.get("recommended_action"),
        },
    }
    atomic_write_json(output, payload)
    return output


def fixture_assertions(case_payload: dict[str, Any]) -> dict[str, Any]:
    expected = case_payload.get("expected_status")
    actual = case_payload.get("actual_status")
    recommended = case_payload.get("recommended_fixture") if isinstance(case_payload.get("recommended_fixture"), dict) else {}
    decision = recommended.get("decision")
    source = recommended.get("source")
    status_hint = str(recommended.get("status_hint") or "").lower()
    assertions: dict[str, Any] = {
        "expected_status": expected,
        "actual_status": actual,
        "must_not_read_sensitive_logs": True,
        "verify_remains_only_done_green_path": True,
    }
    if decision == "uncovered_active_suspect":
        assertions["requires_workspace_hook_or_appserver_active_evidence"] = True
    if source == "process_observer":
        assertions["process_observer_only_never_global_running"] = True
    if source == "codex_private_probe":
        assertions["global_private_probe_never_global_running"] = True
    if status_hint in {"notloaded", "not_loaded", "unknown", "idle"}:
        assertions["weak_appserver_evidence_never_global_running"] = True
    if expected == "running" and actual != "running":
        assertions["mismatch_class"] = "missed_running"
    elif actual == "running" and expected != "running":
        assertions["mismatch_class"] = "false_running"
    elif actual == "blocked" and expected != "blocked":
        assertions["mismatch_class"] = "false_blocked"
    elif actual == "done" and expected != "done":
        assertions["mismatch_class"] = "false_done"
    else:
        assertions["mismatch_class"] = "matched_or_other"
    return assertions


def fixture_case(args: argparse.Namespace) -> Path:
    case_path = Path(args.case).expanduser()
    case_payload = load_json(case_path, {})
    if not isinstance(case_payload, dict) or not case_payload.get("case_id"):
        raise SystemExit(f"Invalid case file: {case_path}")
    fixture_id = str(case_payload["case_id"])
    output = Path(args.output) if args.output else reflection_root() / "fixtures" / f"{fixture_id}.json"
    payload = {
        "schema_version": "0.1",
        "fixture_id": fixture_id,
        "created_at": now_iso(),
        "source_case": str(case_path),
        "expected_status": case_payload.get("expected_status"),
        "actual_status": case_payload.get("actual_status"),
        "recommended_fixture": case_payload.get("recommended_fixture"),
        "assertions": fixture_assertions(case_payload),
    }
    atomic_write_json(output, payload)
    return output


def verify_fixture(args: argparse.Namespace) -> None:
    payload = load_json(Path(args.fixture).expanduser(), {})
    if not isinstance(payload, dict):
        raise SystemExit("fixture is not json object")
    assertions = payload.get("assertions") if isinstance(payload.get("assertions"), dict) else {}
    recommended = payload.get("recommended_fixture") if isinstance(payload.get("recommended_fixture"), dict) else {}
    source = recommended.get("source")
    status_hint = str(recommended.get("status_hint") or "").lower()
    if source == "process_observer" and not assertions.get("process_observer_only_never_global_running"):
        raise SystemExit("process_observer fixture missing no-running assertion")
    if source == "codex_private_probe" and not assertions.get("global_private_probe_never_global_running"):
        raise SystemExit("private probe fixture missing no-running assertion")
    if status_hint in {"notloaded", "not_loaded", "unknown", "idle"} and not assertions.get("weak_appserver_evidence_never_global_running"):
        raise SystemExit("weak appserver fixture missing no-running assertion")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Capture sanitized 66TaskLight status reflection cases")
    subparsers = parser.add_subparsers(dest="command", required=True)

    capture = subparsers.add_parser("capture")
    capture.add_argument("--expected", required=True, choices=sorted(EXPECTED_STATUSES))
    capture.add_argument("--note", default="")
    capture.add_argument("--state-dir", default=str(DEFAULT_STATE_DIR))
    capture.add_argument("--workspace", action="append")
    capture.add_argument("--output")
    capture.add_argument("--case-id")
    capture.add_argument("--skip-appserver", action="store_true")
    capture.add_argument("--appserver-timeout", type=float, default=2.0)

    fixture = subparsers.add_parser("fixture")
    fixture.add_argument("--case", required=True)
    fixture.add_argument("--output")

    verify = subparsers.add_parser("verify-fixture")
    verify.add_argument("--fixture", required=True)

    return parser


def main() -> int:
    args = build_parser().parse_args()
    if args.command == "capture":
        path = capture_case(args)
        print(f"case_path={path}")
    elif args.command == "fixture":
        path = fixture_case(args)
        print(f"fixture_path={path}")
    elif args.command == "verify-fixture":
        verify_fixture(args)
        print("fixture_status=ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
