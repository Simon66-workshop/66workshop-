#!/usr/bin/env python3
"""Audit state accuracy and projector safety."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from _shared import config_dir, load_json, now_iso  # noqa: E402


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Audit state projector behavior")
    parser.add_argument("--baseline-json", required=True)
    parser.add_argument("--evidence-json", required=True)
    parser.add_argument("--task-type", nargs="*", default=[])
    return parser


def command_passed(commands: dict[str, Any], command_id: str) -> bool:
    item = commands.get(command_id) if isinstance(commands, dict) else None
    return bool(isinstance(item, dict) and item.get("passed"))


def matrix_item(judgment: str, *evidence: str) -> dict[str, Any]:
    return {"judgment": judgment, "evidence": [item for item in evidence if item]}


def main() -> None:
    args = build_parser().parse_args()
    baseline = load_json(Path(args.baseline_json), {})
    evidence = load_json(Path(args.evidence_json), {})
    requirements = load_json(config_dir() / "evidence-requirements.json", {})
    required = evidence.get("required_commands") if isinstance(evidence.get("required_commands"), dict) else {}
    optional = evidence.get("optional_commands") if isinstance(evidence.get("optional_commands"), dict) else {}
    ui = baseline.get("ui_state_summary") if isinstance(baseline.get("ui_state_summary"), dict) else {}
    signals = baseline.get("signal_bus_summary") if isinstance(baseline.get("signal_bus_summary"), dict) else {}
    tasks = baseline.get("task_summary") if isinstance(baseline.get("task_summary"), dict) else {}
    findings: list[dict[str, Any]] = []

    matrix: dict[str, Any] = {}
    for item in requirements.get("state_accuracy_matrix") or []:
        if not isinstance(item, dict):
            continue
        matrix_id = str(item.get("matrix_id"))
        source_ids = [str(value) for value in (item.get("source_command_ids") or [])]
        passed = all(command_passed(required, value) or command_passed(optional, value) for value in source_ids if value in optional or value in required)
        known = any((value in optional or value in required) for value in source_ids)
        matrix[matrix_id] = matrix_item("pass" if passed and known else ("unknown" if not known else "fail"), *source_ids)

    recent_source_set = set(signals.get("recent_source_set") or [])
    private_quality = signals.get("latest_private_probe_quality")
    private_scope = signals.get("latest_private_probe_scope")
    global_status = str(ui.get("global_status") or "idle")
    pending_verify = int(((ui.get("counts") or {}).get("pending_verify_count")) or 0)
    done_unverified_count = int((((tasks.get("status_counts") or {}).get("done_unverified")) or 0))
    has_recent_stop = bool(signals.get("has_recent_stop_signal"))
    has_recent_verified = bool(signals.get("has_recent_verified_signal"))
    writer_status = str(ui.get("writer_status") or "unknown")

    if global_status == "running" and recent_source_set == {"process_observer"}:
        findings.append(
            {
                "failure_type": "false_blue_running",
                "message": "RUNNING is backed by process_observer only",
                "evidence": ["ui_state_summary.global_status=running", "signal_bus_summary.recent_source_set=process_observer"],
                "root_cause": "weak process evidence was promoted into global RUNNING",
                "next_bounded_action": "inspect current runtime scoring before changing any UI layer",
                "do_not_touch_next": "Do not change LuckyCat presentation to mask a projector mistake.",
                "decision": "REJECT",
            }
        )
        matrix["process_only_not_running"] = matrix_item("fail", "live_ui_state", "signal_bus_summary")

    if global_status == "running" and recent_source_set == {"codex_private_probe"} and private_scope == "global":
        findings.append(
            {
                "failure_type": "weak_signal_promoted",
                "message": "RUNNING is backed by global private probe only",
                "evidence": ["ui_state_summary.global_status=running", f"signal_bus_summary.latest_private_probe_quality={private_quality}"],
                "root_cause": "global private probe escaped diagnostic-only scope",
                "next_bounded_action": "tighten projector guards around global private metadata",
                "do_not_touch_next": "Do not move this rule into Swift fallback or LuckyCat skin logic.",
                "decision": "REJECT",
            }
        )
        matrix["private_global_only_not_running"] = matrix_item("fail", "live_ui_state", "signal_bus_summary")

    if global_status == "done_verified" and (pending_verify > 0 or done_unverified_count > 0 or (has_recent_stop and not has_recent_verified)):
        findings.append(
            {
                "failure_type": "false_green_done",
                "message": "DONE is visible while pending stop-only evidence still exists",
                "evidence": [
                    "ui_state_summary.global_status=done_verified",
                    f"ui_state_summary.counts.pending_verify_count={pending_verify}",
                    f"task_summary.done_unverified={done_unverified_count}",
                ],
                "root_cause": "verify-only green path was bypassed or stale pending state survived",
                "next_bounded_action": "re-check stop and verify precedence with sanitized local fixtures",
                "do_not_touch_next": "Do not rewrite Stop -> done_unverified semantics.",
                "decision": "REJECT",
            }
        )

    if global_status == "blocked" and int(((ui.get("counts") or {}).get("blocked")) or 0) <= 0:
        findings.append(
            {
                "failure_type": "false_red_blocked",
                "message": "BLOCKED appears without a counted open blocker",
                "evidence": ["ui_state_summary.global_status=blocked", "ui_state_summary.counts.blocked<=0"],
                "root_cause": "stale blocker display escaped current blocker scope",
                "next_bounded_action": "inspect blocker scope resolution before changing observer or UI layers",
                "decision": "REJECT",
            }
        )

    if writer_status in {"old_writer", "multiple_writers"}:
        findings.append(
            {
                "failure_type": "stale_writer",
                "message": f"writer status is {writer_status}",
                "evidence": [f"ui_state_summary.writer_status={writer_status}"],
                "root_cause": "projector writer identity guard is not clean",
                "next_bounded_action": "stop stale projector processes and verify single current writer",
                "decision": "REJECT",
            }
        )
        if writer_status == "old_writer":
            matrix["old_projector_writer_detected"] = matrix_item("pass", "live_ui_state")
        if writer_status == "multiple_writers":
            matrix["multiple_projector_detected"] = matrix_item("pass", "live_ui_state")

    summary = {
        "verify_only_done_green": not any(item.get("failure_type") == "false_green_done" for item in findings),
        "stop_never_done_verified": not any(item.get("failure_type") == "false_green_done" for item in findings),
        "stop_preserves_done_unverified": global_status != "done_verified" or (pending_verify == 0 and done_unverified_count == 0 and has_recent_verified),
        "process_observer_only_not_running": not any(item.get("failure_type") == "false_blue_running" for item in findings),
        "global_private_probe_not_running": not any(item.get("failure_type") == "weak_signal_promoted" for item in findings),
        "no_weak_signal_promotion": not any(item.get("failure_type") in {"false_blue_running", "weak_signal_promoted"} for item in findings),
    }

    payload = {
        "auditor_id": "state_projector_auditor",
        "checked_at": now_iso(),
        "matrix": matrix,
        "summary": summary,
        "findings": findings,
    }
    print(json.dumps(payload, ensure_ascii=True, sort_keys=True, indent=2))


if __name__ == "__main__":
    main()
