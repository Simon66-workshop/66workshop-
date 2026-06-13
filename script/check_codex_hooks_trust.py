#!/usr/bin/env python3
"""Read-only Codex hooks configuration and trust readiness check."""

from __future__ import annotations

import argparse
import json
import os
import select
import shlex
import subprocess
import sys
import time
from pathlib import Path
from typing import Any


DEFAULT_PROJECT_ROOT = Path("/Users/macmini-simon66/Documents/Codex状态桌面栏提醒")
HOOK_HANDLER_REL = Path("script/codex_hook_event.py")
HOOK_CONFIG_REL = Path(".codex/hooks.json")
PROJECT_CONFIG_REL = Path(".codex/config.toml")
CODEX_BIN = Path("/Applications/Codex.app/Contents/Resources/codex")


def load_hooks_json(path: Path) -> tuple[str, Any | None, str | None]:
    if not path.exists():
        return "missing", None, "hooks.json is missing"
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        return "invalid_json", None, f"hooks.json invalid JSON: {exc.msg}"
    if not isinstance(payload, dict):
        return "invalid_json", None, "hooks.json root must be an object"
    return "ok", payload, None


def contains_hook_handler_reference(payload: Any) -> bool:
    needle = "script/codex_hook_event.py"
    if isinstance(payload, str):
        return needle in payload
    if isinstance(payload, dict):
        return any(contains_hook_handler_reference(value) for value in payload.values())
    if isinstance(payload, list):
        return any(contains_hook_handler_reference(value) for value in payload)
    return False


def command_strings(payload: Any) -> list[str]:
    if isinstance(payload, str):
        return [payload]
    if isinstance(payload, dict):
        values: list[str] = []
        for key, value in payload.items():
            if key == "command" and isinstance(value, str):
                values.append(value)
            else:
                values.extend(command_strings(value))
        return values
    if isinstance(payload, list):
        values: list[str] = []
        for item in payload:
            values.extend(command_strings(item))
        return values
    return []


def resolve_hook_handler_path(hook_payload: Any, project_root: Path) -> Path:
    for command in command_strings(hook_payload):
        if "codex_hook_event.py" not in command:
            continue
        try:
            parts = shlex.split(command)
        except ValueError:
            parts = command.split()
        for part in parts:
            if not part.endswith("codex_hook_event.py"):
                continue
            candidate = Path(part)
            if candidate.is_absolute():
                return candidate
            resolved = project_root / candidate
            if resolved.exists():
                return resolved
            return resolved
    return project_root / HOOK_HANDLER_REL


def run_command(args: list[str], cwd: Path, timeout: float = 5.0) -> tuple[int, str, str]:
    try:
        proc = subprocess.run(
            args,
            cwd=str(cwd),
            text=True,
            capture_output=True,
            timeout=timeout,
            check=False,
        )
        return proc.returncode, proc.stdout.strip(), proc.stderr.strip()
    except subprocess.TimeoutExpired as exc:
        return 124, exc.stdout or "", f"timeout after {timeout}s"


def check_handler(project_root: Path, handler_path: Path) -> tuple[str, str, list[str]]:
    notes: list[str] = []
    if not handler_path.exists():
        return "missing", "not_run", ["hook handler is missing"]
    if not os.access(handler_path, os.X_OK):
        return "not_executable", "not_run", ["hook handler is not executable"]
    rc, _, stderr = run_command(["python3", "-m", "py_compile", str(handler_path)], project_root)
    if rc != 0:
        notes.append(stderr or "python compile failed")
        return "compile_failed", "not_run", notes
    rc, stdout, stderr = run_command(["python3", str(handler_path), "--health"], project_root)
    if rc != 0:
        notes.append(stderr or stdout or "health command failed")
        return "compile_failed", "failed", notes
    try:
        payload = json.loads(stdout)
    except json.JSONDecodeError:
        notes.append("health output is not JSON")
        return "compile_failed", "failed", notes
    if payload.get("ok") is not True:
        notes.append("health ok is not true")
        return "compile_failed", "failed", notes
    if payload.get("writes_task_state") is not False:
        notes.append("health did not confirm read-only task-state behavior")
        return "compile_failed", "failed", notes
    return "ok", "ok", notes


def safe_hook_metadata(hook: dict[str, Any]) -> dict[str, Any]:
    return {
        "eventName": hook.get("eventName"),
        "enabled": hook.get("enabled"),
        "trustStatus": hook.get("trustStatus"),
        "sourcePath": hook.get("sourcePath"),
        "currentHash": hook.get("currentHash"),
    }


def query_appserver_hooks(project_root: Path, timeout: float = 4.0) -> tuple[str, list[dict[str, Any]], str | None]:
    if not CODEX_BIN.exists():
        return "unavailable", [], "codex binary not found"
    try:
        proc = subprocess.Popen(
            [str(CODEX_BIN), "app-server", "--listen", "stdio://"],
            cwd=str(project_root),
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
    except OSError as exc:
        return "unavailable", [], str(exc)

    assert proc.stdin is not None
    assert proc.stdout is not None
    requests = [
        {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "clientInfo": {"name": "66tasklight-hooks-check", "version": "0.1"},
                "capabilities": {"experimentalApi": True},
            },
        },
        {
            "jsonrpc": "2.0",
            "id": 2,
            "method": "hooks/list",
            "params": {"cwds": [str(project_root)]},
        },
    ]
    for request in requests:
        proc.stdin.write(json.dumps(request, separators=(",", ":")) + "\n")
        proc.stdin.flush()

    response: dict[str, Any] | None = None
    deadline = time.time() + timeout
    while time.time() < deadline:
        ready, _, _ = select.select([proc.stdout], [], [], 0.2)
        if not ready:
            continue
        line = proc.stdout.readline()
        if not line:
            break
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            continue
        if message.get("id") == 2:
            response = message
            break

    proc.terminate()
    try:
        proc.wait(timeout=1)
    except subprocess.TimeoutExpired:
        proc.kill()

    if not response:
        return "unavailable", [], "hooks/list did not respond"
    if response.get("error"):
        return "unavailable", [], str(response["error"].get("message") or response["error"])
    entries = (response.get("result") or {}).get("data") or []
    if not isinstance(entries, list):
        return "unavailable", [], "hooks/list response shape is unexpected"

    hooks: list[dict[str, Any]] = []
    for entry in entries:
        if not isinstance(entry, dict):
            continue
        if Path(str(entry.get("cwd", ""))) != project_root:
            continue
        for hook in entry.get("hooks") or []:
            if isinstance(hook, dict):
                hooks.append(safe_hook_metadata(hook))
    if not hooks:
        return "not_loaded", [], "no hooks returned for project root"
    trust_states = {str(hook.get("trustStatus")) for hook in hooks}
    if trust_states <= {"trusted", "managed"}:
        return "trusted", hooks, None
    if "untrusted" in trust_states:
        return "untrusted", hooks, None
    return "loaded_unknown", hooks, None


def summarize(payload: dict[str, Any]) -> tuple[str, str, str]:
    fatal = []
    if payload["project_root"] != "ok":
        fatal.append("project_root")
    if payload["codex_dir"] != "ok":
        fatal.append("codex_dir")
    if payload["hook_config"] != "ok":
        fatal.append("hook_config")
    if payload["hook_reference"] != "ok":
        fatal.append("hook_reference")
    if payload["hook_handler"] != "ok":
        fatal.append("hook_handler")
    if payload["hook_health"] != "ok":
        fatal.append("hook_health")
    if fatal:
        return "likely_not_loaded", "misconfigured", "fix hook configuration"

    appserver = payload.get("codex_appserver", "skipped")
    if appserver == "trusted":
        return "trusted_possible", "trusted_possible", "hooks appear trusted; trigger a new Codex turn to verify spool events"
    if appserver == "untrusted":
        return "unknown_manual_required", "untrusted_or_not_loaded", "open Codex UI and trust project hooks"
    if appserver == "not_loaded":
        return "likely_not_loaded", "untrusted_or_not_loaded", "reload Codex project thread, then trust project hooks if prompted"
    return "unknown_manual_required", "trusted_possible", "open Codex UI and trust project hooks if prompted"


def classify_visibility(payload: dict[str, Any]) -> tuple[str, str]:
    if payload["project_root"] != "ok" or payload["codex_dir"] != "ok" or payload["hook_config"] != "ok" or payload["hook_reference"] != "ok" or payload["hook_handler"] != "ok" or payload["hook_health"] != "ok":
        return "hidden_misconfigured", "hooks 配置不完整，所以 Codex UI 不会稳定显示"

    appserver = payload.get("codex_appserver", "skipped")
    if appserver == "trusted":
        return "visible_trusted", "Codex UI 已加载这个 workspace 的 hooks，而且它们已可信"
    if appserver == "untrusted":
        return "visible_untrusted", "Codex UI 已加载这个 workspace 的 hooks，但还没有 Trust"
    if appserver == "not_loaded":
        return "hidden_not_loaded", "hooks 文件已存在，但 Codex UI 还没把这个 workspace 加载进来"
    if appserver == "loaded_unknown":
        return "visible_unknown", "Codex UI 已加载这个 workspace，但 hooks 信任状态不明确"
    return "unknown", "当前只能确认 hooks 文件存在，无法确认 Codex UI 是否已加载"


def build_report(args: argparse.Namespace) -> dict[str, Any]:
    project_root = Path(args.project_root).expanduser().resolve()
    expected_root = (
        Path(args.expected_root).expanduser().resolve()
        if args.expected_root
        else project_root
    )
    codex_dir = project_root / ".codex"
    hooks_path = project_root / HOOK_CONFIG_REL
    config_path = project_root / PROJECT_CONFIG_REL
    handler_path = project_root / HOOK_HANDLER_REL

    notes: list[str] = []
    project_root_status = "ok" if project_root == expected_root else "wrong_root"
    if project_root_status != "ok":
        notes.append(f"project root is {project_root}, expected {expected_root}")
    codex_dir_status = "ok" if codex_dir.is_dir() else "missing"
    if codex_dir_status != "ok":
        notes.append(".codex directory is missing")

    hook_config, hook_payload, hook_config_error = load_hooks_json(hooks_path)
    if hook_config_error:
        notes.append(hook_config_error)
    hook_reference = "ok" if hook_payload is not None and contains_hook_handler_reference(hook_payload) else "missing"
    if hook_config == "ok" and hook_reference != "ok":
        notes.append("hooks.json does not reference script/codex_hook_event.py")

    handler_path = resolve_hook_handler_path(hook_payload, project_root) if hook_payload is not None else handler_path
    hook_handler, hook_health, handler_notes = check_handler(project_root, handler_path)
    notes.extend(handler_notes)

    config_toml = "present" if config_path.exists() else "missing_optional"
    appserver_status = "skipped"
    appserver_hooks: list[dict[str, Any]] = []
    appserver_error = None
    if not args.skip_appserver:
        appserver_status, appserver_hooks, appserver_error = query_appserver_hooks(project_root, timeout=args.appserver_timeout)
        if appserver_error:
            notes.append(f"codex app-server check: {appserver_error}")

    payload: dict[str, Any] = {
        "project_root_path": str(project_root),
        "expected_project_root": str(expected_root),
        "project_root": project_root_status,
        "codex_dir": codex_dir_status,
        "hook_config": hook_config,
        "hook_reference": hook_reference,
        "hook_handler": hook_handler,
        "hook_handler_path": str(handler_path),
        "hook_health": hook_health,
        "config_toml": config_toml,
        "codex_appserver": appserver_status,
        "codex_appserver_hooks": appserver_hooks,
        "notes": notes,
    }
    project_trust, status, next_action = summarize(payload)
    payload["project_trust"] = project_trust
    payload["status"] = status
    payload["next_action"] = next_action
    visibility, visibility_reason = classify_visibility(payload)
    payload["hook_visibility"] = visibility
    payload["hook_visibility_reason"] = visibility_reason
    return payload


def print_human(payload: dict[str, Any]) -> None:
    print(f"PROJECT_ROOT: {payload['project_root']}")
    print(f"CODEX_DIR: {payload['codex_dir']}")
    print(f"HOOK_CONFIG: {payload['hook_config']}")
    print(f"HOOK_REFERENCE: {payload['hook_reference']}")
    print(f"HOOK_HANDLER: {payload['hook_handler']}")
    print(f"HOOK_HEALTH: {payload['hook_health']}")
    print(f"CONFIG_TOML: {payload['config_toml']}")
    print(f"CODEX_APPSERVER: {payload['codex_appserver']}")
    if payload["codex_appserver_hooks"]:
        trust_counts: dict[str, int] = {}
        for hook in payload["codex_appserver_hooks"]:
            trust = str(hook.get("trustStatus"))
            trust_counts[trust] = trust_counts.get(trust, 0) + 1
        summary = ", ".join(f"{key}={value}" for key, value in sorted(trust_counts.items()))
        print(f"CODEX_APPSERVER_HOOKS: {summary}")
    print(f"PROJECT_TRUST: {payload['project_trust']}")
    print(f"HOOK_VISIBILITY: {payload['hook_visibility']}")
    print(f"HOOK_VISIBILITY_REASON: {payload['hook_visibility_reason']}")
    print(f"STATUS: {payload['status']}")
    print(f"NEXT_ACTION: {payload['next_action']}")
    for note in payload["notes"]:
        print(f"NOTE: {note}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Check local Codex hooks readiness for 66TaskLight")
    parser.add_argument("--project-root", default=str(DEFAULT_PROJECT_ROOT))
    parser.add_argument("--expected-root")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--skip-appserver", action="store_true")
    parser.add_argument("--appserver-timeout", type=float, default=4.0)
    args = parser.parse_args()

    payload = build_report(args)
    if args.json:
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True, indent=2))
    else:
        print_human(payload)
    return 0 if payload["status"] in {"trusted_possible", "untrusted_or_not_loaded"} else 1


if __name__ == "__main__":
    raise SystemExit(main())
