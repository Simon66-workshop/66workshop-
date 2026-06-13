#!/usr/bin/env python3
"""Read-only coverage report for Codex threads and 66TaskLight status inputs."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shlex
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from check_codex_hooks_trust import query_appserver_hooks


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_STATE_DIR = Path.home() / ".66tasklight"
HOOK_HANDLER_NAME = "codex_hook_event.py"
ACTIVE_EVENTS = {"turn_started", "item_started", "item_completed", "heartbeat", "task_started", "bridge_running"}
PENDING_EVENTS = {"stop", "turn_completed", "bridge_done_unverified"}
DIAGNOSTIC_SOURCES = {"process_observer", "codex_private_probe"}


def safe_hash(value: Any) -> str | None:
    if value in (None, ""):
        return None
    digest = hashlib.sha256(str(value).encode("utf-8")).hexdigest()
    return digest[:16]


def parse_ts(value: Any) -> float | None:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    text = str(value)
    try:
        return float(text)
    except ValueError:
        pass
    try:
        return datetime.fromisoformat(text.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def age_sec(value: Any, now_ts: float) -> float | None:
    parsed = parse_ts(value)
    if parsed is None:
        return None
    return max(0.0, now_ts - parsed)


def load_json(path: Path, default: Any) -> Any:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return default
    return payload


def read_jsonl(path: Path, limit: int) -> list[dict[str, Any]]:
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError:
        return []
    records: list[dict[str, Any]] = []
    for line in lines[-limit:]:
        if not line.strip():
            continue
        try:
            payload = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(payload, dict):
            records.append(payload)
    return records


def string_list(value: Any) -> list[str]:
    if isinstance(value, list):
        return [str(item) for item in value if item not in (None, "")]
    if value in (None, ""):
        return []
    return [str(value)]


def signal_time(signal: dict[str, Any]) -> Any:
    return signal.get("occurred_at") or signal.get("event_time") or signal.get("recorded_at") or signal.get("checked_at")


def latest_signal(signals: list[dict[str, Any]]) -> dict[str, Any] | None:
    if not signals:
        return None
    return max(signals, key=lambda item: parse_ts(signal_time(item)) or 0.0)


def signal_identity(signal: dict[str, Any]) -> tuple[str, str]:
    identity = signal.get("identity") if isinstance(signal.get("identity"), dict) else {}
    turn_id = signal.get("turn_id") or identity.get("turn_id")
    thread_id = signal.get("thread_id") or identity.get("thread_id")
    if turn_id:
        return "turn", str(turn_id)
    if thread_id:
        return "thread", str(thread_id)
    observation_id = signal.get("observation_id") or identity.get("observation_id")
    if observation_id:
        return "observation", str(observation_id)
    return "unknown", str(signal.get("signal_id") or "unknown")


def appserver_active_like(signal: dict[str, Any], now_ts: float, ttl: float) -> tuple[bool, str]:
    if str(signal.get("source") or "") != "codex_appserver":
        return False, "not_appserver"
    age = age_sec(signal_time(signal), now_ts)
    if age is None:
        return False, "missing_event_time"
    if age > ttl:
        return False, "stale_appserver_signal"
    event_type = str(signal.get("event_type") or "").lower()
    status_hint = str(signal.get("status_hint") or "").lower()
    source_quality = str(signal.get("source_quality") or "").lower()
    evidence = " ".join(string_list(signal.get("evidence")) + string_list(signal.get("appserver_activity_evidence"))).lower()
    if event_type in {"unknown", "appserver_quiet"}:
        return False, f"event_type={event_type}"
    if status_hint in {"unknown", "notloaded", "not_loaded", "idle", "quiet", "complete", "completed"}:
        return False, f"status_hint={status_hint}"
    if any(marker in source_quality for marker in ("unknown", "ignored", "quiet")):
        return False, f"source_quality={source_quality}"
    if event_type in {"turn_started", "item_started"}:
        return True, f"event_type={event_type}"
    if "status=active" in evidence or "updatedat advanced" in evidence or status_hint in {"active", "running"}:
        return True, "appserver_activity_evidence"
    return False, "missing_active_like_evidence"


def command_strings(payload: Any) -> list[str]:
    commands: list[str] = []
    if isinstance(payload, dict):
        for key, value in payload.items():
            if key == "command" and isinstance(value, str):
                commands.append(value)
            else:
                commands.extend(command_strings(value))
    elif isinstance(payload, list):
        for item in payload:
            commands.extend(command_strings(item))
    return commands


def resolve_hook_handler(command: str, workspace: Path) -> Path | None:
    try:
        parts = shlex.split(command)
    except ValueError:
        return None
    for part in parts:
        if part.endswith(HOOK_HANDLER_NAME):
            candidate = Path(part)
            if candidate.is_absolute():
                return candidate
            for root in (workspace, PROJECT_ROOT):
                resolved = root / candidate
                if resolved.exists():
                    return resolved
            return workspace / candidate
    return None


def check_hook_workspace(workspace: str, *, skip_appserver: bool, appserver_timeout: float) -> dict[str, Any]:
    if workspace == "unknown":
        return {
            "workspace": "unknown",
            "hook_status": "unknown_manual_required",
            "hook_detail": "workspace_unknown",
        }
    root = Path(workspace).expanduser().resolve()
    hooks_path = root / ".codex" / "hooks.json"
    config_path = root / ".codex" / "config.toml"
    if not root.exists():
        return {"workspace": str(root), "hook_status": "missing", "hook_detail": "workspace_missing"}
    try:
        payload = json.loads(hooks_path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return {"workspace": str(root), "hook_status": "missing", "hook_detail": "hooks_json_missing"}
    except json.JSONDecodeError:
        return {"workspace": str(root), "hook_status": "invalid", "hook_detail": "hooks_json_invalid"}
    commands = [command for command in command_strings(payload) if HOOK_HANDLER_NAME in command]
    if not commands:
        return {"workspace": str(root), "hook_status": "invalid", "hook_detail": "handler_reference_missing"}
    handler = resolve_hook_handler(commands[0], root)
    if handler is None or not handler.exists():
        return {"workspace": str(root), "hook_status": "invalid", "hook_detail": "handler_missing"}
    if not os.access(handler, os.X_OK):
        return {"workspace": str(root), "hook_status": "invalid", "hook_detail": "handler_not_executable", "handler": str(handler)}
    health = subprocess.run(["python3", str(handler), "--health"], cwd=str(root), text=True, capture_output=True, timeout=5)
    if health.returncode != 0:
        return {"workspace": str(root), "hook_status": "invalid", "hook_detail": "handler_health_failed", "handler": str(handler)}
    config_text = config_path.read_text(encoding="utf-8") if config_path.exists() else ""
    config_enabled = "codex_hooks" in config_text and "true" in config_text
    appserver_status = "skipped"
    if not skip_appserver:
        appserver_status, _, _ = query_appserver_hooks(root, timeout=appserver_timeout)
    hook_status = "ok" if config_enabled and appserver_status in {"trusted", "skipped"} else "unknown_manual_required"
    return {
        "workspace": str(root),
        "hook_status": hook_status,
        "hook_detail": "ok" if hook_status == "ok" else "needs_trust_or_reload",
        "handler": str(handler),
        "config_enabled": config_enabled,
        "codex_appserver": appserver_status,
    }


def state_dir() -> Path:
    return Path(os.environ.get("TASKLIGHT_STATE_DIR", str(DEFAULT_STATE_DIR))).expanduser()


def load_bindings(root: Path) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    turn_bindings: list[dict[str, Any]] = []
    thread_bindings: list[dict[str, Any]] = []
    for folder, target in ((root / "turn_bindings", turn_bindings), (root / "thread_bindings", thread_bindings)):
        if not folder.exists():
            continue
        for path in folder.glob("*.json"):
            payload = load_json(path, {})
            if isinstance(payload, dict):
                payload["_path"] = str(path)
                target.append(payload)
    return turn_bindings, thread_bindings


def collect_threads(args: argparse.Namespace) -> tuple[dict[str, dict[str, Any]], list[dict[str, Any]], dict[str, Any]]:
    root = Path(args.state_dir).expanduser()
    now_ts = time.time()
    signals = read_jsonl(Path(args.signals_path).expanduser(), args.signal_limit)
    turn_bindings, thread_bindings = load_bindings(root)
    appserver_state = load_json(root / "appserver_thread_watcher_state.json", {})
    appserver_health = load_json(root / "appserver_thread_watcher_health.json", {})
    ui_state = load_json(root / "ui_state.json", {})
    threads: dict[str, dict[str, Any]] = {}

    def ensure(key: str, kind: str, value: str) -> dict[str, Any]:
        item = threads.setdefault(
            key,
            {
                "key": key,
                "thread_id": None,
                "turn_id": None,
                "workspace": args.default_workspace,
                "workspace_source": "default",
                "signals": [],
                "latest_signal_age_sec": None,
                "appserver_status": "unknown",
                "appserver_activity_evidence": [],
                "projector_scope": "none",
                "source_set": [],
                "reason": "no_signal",
            },
        )
        if kind == "thread":
            item["thread_id"] = value
        elif kind == "turn":
            item["turn_id"] = value
        return item

    for signal in signals:
        kind, value = signal_identity(signal)
        key = f"{kind}:{value}"
        item = ensure(key, kind, value)
        item["signals"].append(signal)
        if signal.get("thread_id"):
            item["thread_id"] = str(signal.get("thread_id"))
        if signal.get("turn_id"):
            item["turn_id"] = str(signal.get("turn_id"))
        if signal.get("cwd"):
            item["workspace"] = str(signal.get("cwd"))
            item["workspace_source"] = "signal_cwd"

    for binding in turn_bindings:
        turn_id = binding.get("turn_id")
        if not turn_id:
            continue
        item = ensure(f"turn:{turn_id}", "turn", str(turn_id))
        if binding.get("thread_id"):
            item["thread_id"] = str(binding.get("thread_id"))
        if binding.get("cwd"):
            item["workspace"] = str(binding.get("cwd"))
            item["workspace_source"] = "turn_binding_cwd"
        item["turn_binding_status"] = binding.get("status")

    for binding in thread_bindings:
        thread_id = binding.get("thread_id")
        if not thread_id:
            continue
        item = ensure(f"thread:{thread_id}", "thread", str(thread_id))
        if binding.get("cwd"):
            item["workspace"] = str(binding.get("cwd"))
            item["workspace_source"] = "thread_binding_cwd"
        item["thread_binding_status"] = binding.get("status")

    app_threads = appserver_state.get("threads") if isinstance(appserver_state.get("threads"), dict) else {}
    for thread_id, state in app_threads.items():
        if not isinstance(state, dict):
            continue
        item = ensure(f"thread:{thread_id}", "thread", str(thread_id))
        item["appserver_status"] = state.get("status_hint") or state.get("event_type") or "unknown"
        item["appserver_state_age_sec"] = age_sec(state.get("occurred_at"), now_ts)

    diagnostics = ui_state.get("diagnostics") if isinstance(ui_state.get("diagnostics"), dict) else {}
    for candidate in ui_state.get("runtime_candidates") or diagnostics.get("top_runtime_candidates") or []:
        if not isinstance(candidate, dict):
            continue
        kind = "turn" if candidate.get("turn_id") else "thread" if candidate.get("thread_id") else "unknown"
        value = candidate.get("turn_id") or candidate.get("thread_id") or candidate.get("candidate_id")
        if not value:
            continue
        item = ensure(f"{kind}:{value}", kind, str(value))
        item["projector_scope"] = candidate.get("display_scope") or "none"
        item["appserver_activity_evidence"] = string_list(candidate.get("appserver_activity_evidence"))

    metadata = {
        "appserver_health": appserver_health,
        "ui_state_status": ui_state.get("global_status"),
        "signal_count": len(signals),
    }
    return threads, signals, metadata


def classify_thread(item: dict[str, Any], workspace_hook: dict[str, Any], *, now_ts: float, ttl: float) -> dict[str, Any]:
    signals = item.get("signals") or []
    latest_age: float | None = None
    latest_hook_age: float | None = None
    source_set: set[str] = set()
    covered_running = False
    covered_pending = False
    diagnostic_only = False
    weak_appserver = False
    appserver_active = False
    reason = "no_authoritative_runtime_signal"
    ui_effect = "none"
    appserver_status = item.get("appserver_status") or "unknown"
    evidence: list[str] = []
    latest = latest_signal(signals)

    for signal in signals:
        source = str(signal.get("source") or "unknown")
        source_set.add(source)
        current_age = age_sec(signal_time(signal), now_ts)
        if current_age is not None:
            latest_age = current_age if latest_age is None else min(latest_age, current_age)
        event_type = str(signal.get("event_type") or "")
        if source == "codex_hook":
            if current_age is not None and current_age <= ttl:
                latest_hook_age = current_age if latest_hook_age is None else min(latest_hook_age, current_age)
                if event_type in ACTIVE_EVENTS and signal.get("turn_id"):
                    covered_running = True
                    reason = "fresh_hook_turn_signal"
                elif event_type in PENDING_EVENTS and signal.get("turn_id"):
                    covered_pending = True
                    reason = "fresh_hook_stop_signal"
        if source == "codex_appserver":
            is_active, active_reason = appserver_active_like(signal, now_ts, ttl)
            if is_active:
                appserver_active = True
                covered_running = True
                reason = active_reason
                appserver_status = "active"
                evidence.extend(string_list(signal.get("appserver_activity_evidence")))
            elif event_type in {"unknown", "appserver_quiet"}:
                weak_appserver = True
                diagnostic_only = True
        if source in DIAGNOSTIC_SOURCES:
            diagnostic_only = True

    if covered_running:
        if (
            reason == "fresh_hook_turn_signal"
            and workspace_hook.get("hook_status") != "ok"
            and item.get("workspace_source") == "default"
        ):
            decision = "uncovered_active_suspect"
            ui_effect = "none"
            reason = "workspace_hooks_not_ready"
            covered_running = False
        else:
            decision = "covered_running"
            ui_effect = "running"
    elif covered_pending:
        decision = "covered_pending"
        ui_effect = "pending"
    elif latest_age is not None and latest_age > ttl:
        decision = "stale"
        ui_effect = "none"
        reason = "stale_signal"
    elif weak_appserver and workspace_hook.get("hook_status") in {"missing", "invalid", "unknown_manual_required"}:
        decision = "uncovered_active_suspect"
        reason = "appserver_weak_signal_without_workspace_hooks"
    elif diagnostic_only:
        decision = "diagnostic_only"
        ui_effect = "diagnostic_only"
        reason = "diagnostic_source_only"
    elif item.get("appserver_state_age_sec") is not None and item["appserver_state_age_sec"] <= ttl:
        decision = "uncovered_active_suspect"
        reason = "appserver_thread_without_active_evidence"
    elif workspace_hook.get("hook_status") in {"missing", "invalid", "unknown_manual_required"}:
        decision = "uncovered_active_suspect"
        reason = "workspace_hooks_not_ready"
    else:
        decision = "stale" if latest_age is not None else "diagnostic_only"
        reason = "no_recent_authoritative_signal" if latest_age is not None else "no_thread_signal"

    source_set_list = sorted(source_set)
    explanation = explain_decision(
        decision=decision,
        reason=reason,
        source_set=source_set_list,
        hook_status=workspace_hook.get("hook_status", "unknown_manual_required"),
        appserver_status=appserver_status,
    )
    fixture = recommended_fixture_for_thread(
        item=item,
        latest=latest,
        decision=decision,
        reason=reason,
        ui_effect=ui_effect,
        workspace_hook=workspace_hook,
        source_set=source_set_list,
        appserver_status=appserver_status,
    )

    return {
        "thread_id": item.get("thread_id"),
        "turn_id": item.get("turn_id"),
        "workspace": item.get("workspace") or "unknown",
        "workspace_source": item.get("workspace_source") or "unknown",
        "hook_status": workspace_hook.get("hook_status", "unknown_manual_required"),
        "latest_hook_signal_age_sec": None if latest_hook_age is None else round(latest_hook_age, 2),
        "latest_signal_age_sec": None if latest_age is None else round(latest_age, 2),
        "appserver_status": appserver_status,
        "appserver_activity_evidence": sorted(set(evidence or item.get("appserver_activity_evidence") or [])),
        "projector_scope": item.get("projector_scope") or "none",
        "ui_effect": ui_effect,
        "decision": decision,
        "reason": reason,
        "explanation": explanation,
        "source_set": source_set_list,
        "recommended_fixture": fixture,
    }


def explain_decision(*, decision: str, reason: str, source_set: list[str], hook_status: str, appserver_status: str) -> str:
    if decision == "covered_running":
        return "running because fresh hook or appserver active evidence is present"
    if decision == "covered_pending":
        return "pending because a fresh stop or done-unverified signal is present"
    if decision == "stale":
        return "not running because the latest signal is stale"
    if reason in {"workspace_hooks_not_ready", "appserver_weak_signal_without_workspace_hooks"} or hook_status in {"missing", "invalid", "unknown_manual_required"} and decision == "uncovered_active_suspect":
        return "not running because workspace hooks missing or not trusted"
    if "codex_appserver" in source_set and ("notLoaded" in appserver_status or "notloaded" in reason.lower() or "unknown" in appserver_status):
        return f"not running because appserver evidence is {appserver_status}"
    if source_set == ["process_observer"]:
        return "not running because only process_observer is present"
    if source_set == ["codex_private_probe"]:
        return "not running because only weak private probe evidence is present"
    if decision == "diagnostic_only":
        return "not running because available evidence is diagnostic only"
    return f"not running because {reason}"


def expected_projector_result(decision: str, ui_effect: str, reason: str) -> str:
    if ui_effect == "running":
        return "running"
    if ui_effect == "pending":
        return "pending"
    if reason in {"workspace_hooks_not_ready", "appserver_weak_signal_without_workspace_hooks"}:
        return "idle_until_workspace_hooks_trusted"
    return "not_running"


def recommended_fixture_for_thread(
    *,
    item: dict[str, Any],
    latest: dict[str, Any] | None,
    decision: str,
    reason: str,
    ui_effect: str,
    workspace_hook: dict[str, Any],
    source_set: list[str],
    appserver_status: str,
) -> dict[str, Any]:
    source = str((latest or {}).get("source") or source_set[0] if source_set else "unknown")
    event_type = str((latest or {}).get("event_type") or "unknown")
    status_hint = (latest or {}).get("status_hint") or appserver_status
    return {
        "schema_version": "0.1",
        "source": source,
        "event_type": event_type,
        "thread_id_hash": safe_hash(item.get("thread_id")),
        "turn_id_hash": safe_hash(item.get("turn_id")),
        "workspace_hash": safe_hash(item.get("workspace")),
        "status_hint": status_hint,
        "decision": decision,
        "reason": reason,
        "hook_status": workspace_hook.get("hook_status", "unknown_manual_required"),
        "source_set": source_set,
        "expected_projector_result": expected_projector_result(decision, ui_effect, reason),
    }


def build_report(args: argparse.Namespace) -> dict[str, Any]:
    now_ts = time.time()
    threads, _, metadata = collect_threads(args)
    explicit_workspaces = [str(Path(path).expanduser().resolve()) for path in (args.workspace or [])]
    workspaces = {item.get("workspace") or "unknown" for item in threads.values()}
    workspaces.update(explicit_workspaces)
    hook_cache = {
        workspace: check_hook_workspace(workspace, skip_appserver=args.skip_appserver, appserver_timeout=args.appserver_timeout)
        for workspace in sorted(workspaces)
    }
    classified: list[dict[str, Any]] = []
    for item in threads.values():
        workspace = item.get("workspace") or "unknown"
        classified.append(classify_thread(item, hook_cache.get(workspace, {}), now_ts=now_ts, ttl=args.ttl_seconds))
    classified.sort(key=lambda item: (item["decision"] != "covered_running", item["decision"] != "uncovered_active_suspect", item.get("thread_id") or "", item.get("turn_id") or ""))
    summary = {
        "codex_threads_seen": len(classified),
        "covered_running": sum(1 for item in classified if item["decision"] == "covered_running"),
        "covered_pending": sum(1 for item in classified if item["decision"] == "covered_pending"),
        "diagnostic_only": sum(1 for item in classified if item["decision"] == "diagnostic_only"),
        "uncovered_active_suspects": sum(1 for item in classified if item["decision"] == "uncovered_active_suspect"),
        "stale": sum(1 for item in classified if item["decision"] == "stale"),
    }
    if summary["uncovered_active_suspects"]:
        status = "needs_workspace_hooks"
        recommended = "install or trust hooks for uncovered workspaces"
    elif summary["covered_running"] or summary["covered_pending"]:
        status = "ok"
        recommended = "state inputs are covered"
    elif classified:
        status = "no_authoritative_signal"
        recommended = "wait for hook/appserver activity or install workspace hooks"
    else:
        status = "ok"
        recommended = "no Codex threads observed"
    recommended_fixtures = [
        item.get("recommended_fixture")
        for item in classified
        if item.get("recommended_fixture")
        and item.get("decision") in {"uncovered_active_suspect", "diagnostic_only", "covered_running", "covered_pending", "stale"}
    ][:10]
    return {
        "schema_version": "0.1",
        "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "state_dir": str(Path(args.state_dir).expanduser()),
        "status": status,
        "recommended_action": recommended,
        "recommended_fixture": recommended_fixtures[0] if recommended_fixtures else None,
        "recommended_fixtures": recommended_fixtures,
        "summary": summary,
        "workspaces": hook_cache,
        "threads": classified,
        "metadata": metadata,
    }


def print_human(report: dict[str, Any]) -> None:
    summary = report["summary"]
    print(f"STATUS={report['status']}")
    print(f"codex_threads_seen={summary['codex_threads_seen']}")
    print(f"covered_running={summary['covered_running']}")
    print(f"covered_pending={summary['covered_pending']}")
    print(f"diagnostic_only={summary['diagnostic_only']}")
    print(f"uncovered_active_suspects={summary['uncovered_active_suspects']}")
    print(f"stale={summary['stale']}")
    print(f"recommended_action={report['recommended_action']}")
    if report.get("recommended_fixture"):
        fixture = report["recommended_fixture"]
        print(
            "recommended_fixture="
            f"source={fixture.get('source')} event_type={fixture.get('event_type')} "
            f"decision={fixture.get('decision')} reason={fixture.get('reason')} "
            f"expected_projector_result={fixture.get('expected_projector_result')}"
        )
    for workspace, payload in report["workspaces"].items():
        print(f"workspace={workspace} hook_status={payload.get('hook_status')} hook_detail={payload.get('hook_detail')}")
    for item in report["threads"][:20]:
        print(
            "thread thread_id={thread_id} turn_id={turn_id} decision={decision} ui_effect={ui_effect} "
            "workspace={workspace} hook_status={hook_status} appserver_status={appserver_status} "
            "projector_scope={projector_scope} reason={reason} explanation={explanation}".format(**{key: item.get(key, "none") for key in item})
        )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Check Codex thread coverage for 66TaskLight status inputs")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--workspace", action="append")
    parser.add_argument("--state-dir", default=str(DEFAULT_STATE_DIR))
    parser.add_argument("--signals-path")
    parser.add_argument("--signal-limit", type=int, default=2000)
    parser.add_argument("--ttl-seconds", type=float, default=float(os.environ.get("TASKLIGHT_COVERAGE_ACTIVE_TTL_SECONDS", "30")))
    parser.add_argument("--appserver-timeout", type=float, default=2.0)
    parser.add_argument("--skip-appserver", action="store_true")
    parser.add_argument("--no-default-workspace", action="store_true")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    if not args.signals_path:
        args.signals_path = os.environ.get(
            "TASKLIGHT_NORMALIZED_SIGNALS_PATH",
            str(Path(args.state_dir).expanduser() / "normalized_signals.jsonl"),
        )
    if args.no_default_workspace:
        args.default_workspace = "unknown"
    elif args.workspace:
        args.default_workspace = str(Path(args.workspace[0]).expanduser().resolve())
    else:
        args.default_workspace = str(PROJECT_ROOT)
    report = build_report(args)
    if args.json:
        print(json.dumps(report, ensure_ascii=True, sort_keys=True, indent=2))
    else:
        print_human(report)
    return 1 if report["status"] == "error" else 0


if __name__ == "__main__":
    raise SystemExit(main())
