#!/usr/bin/env python3
"""Local Codex app-server bridge probe and event normalizer."""

from __future__ import annotations

import argparse
import json
import os
import select
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any


DEFAULT_CODEX = "/Applications/Codex.app/Contents/Resources/codex"


def codex_bin() -> str:
    return os.environ.get("CODEX_BIN") or (DEFAULT_CODEX if Path(DEFAULT_CODEX).exists() else shutil.which("codex") or "codex")


def event_name(event: dict[str, Any]) -> str:
    return str(event.get("method") or event.get("event") or event.get("type") or event.get("name") or "")


def event_params(event: dict[str, Any]) -> dict[str, Any]:
    params = event.get("params")
    if isinstance(params, dict):
        return params
    return event


def first_present(*values: Any) -> Any:
    for value in values:
        if value is not None and value != "":
            return value
    return None


def status_type(value: Any) -> str:
    if isinstance(value, dict):
        return str(value.get("type") or value.get("status") or "")
    return str(value or "")


def sanitize_event_time(value: Any) -> int:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return int(time.time())
    if number > 10_000_000_000:
        number = number / 1000
    return int(number)


def event_to_signal(event: dict[str, Any]) -> dict[str, Any]:
    name = event_name(event)
    params = event_params(event)
    thread = params.get("thread") if isinstance(params.get("thread"), dict) else {}
    turn = params.get("turn") if isinstance(params.get("turn"), dict) else {}
    item = params.get("item") if isinstance(params.get("item"), dict) else {}
    thread_id = first_present(
        params.get("thread_id"),
        params.get("threadId"),
        params.get("threadID"),
        params.get("sessionId"),
        params.get("session_id"),
        thread.get("id"),
        thread.get("sessionId"),
        event.get("thread_id"),
    )
    turn_id = first_present(
        params.get("turn_id"),
        params.get("turnId"),
        turn.get("id"),
        turn.get("turnId"),
        item.get("turnId"),
        event.get("turn_id"),
    )
    item_id = first_present(params.get("item_id"), params.get("itemId"), item.get("id"), event.get("item_id"))
    event_type = "unknown"
    confidence = 0.90
    reason = None
    message = None

    if name in {"turn/started", "thread/started"}:
        event_type = "turn_started"
    elif name == "thread/status/changed":
        state = status_type(params.get("status") or thread.get("status"))
        if state == "active":
            event_type = "turn_started"
        elif state in {"systemError", "errored", "failed"}:
            event_type = "tool_failed"
            reason = "codex_exit_failed"
            message = "Codex app-server thread status changed to an error state"
        elif state in {"idle", "complete", "completed"}:
            event_type = "appserver_quiet"
            confidence = 0.65
        else:
            confidence = 0.0
    elif name == "item/started":
        event_type = "item_started"
    elif name == "item/completed":
        event_type = "item_completed"
    elif name in {"item/commandExecution/requestApproval", "item/fileChange/requestApproval", "item/permissions/requestApproval", "item/tool/requestUserInput"}:
        event_type = "approval_pending"
        reason = "needs_human_review"
        message = "Codex is waiting for approval or user input"
    elif name == "error":
        event_type = "tool_failed"
        reason = "codex_exit_failed"
        message = "Codex app-server emitted an error event"
    elif name == "turn/completed":
        event_type = "turn_completed"

    return {
        "source": "codex_appserver",
        "event_type": event_type,
        "thread_id": thread_id,
        "turn_id": turn_id,
        "item_id": item_id,
        "event_time": sanitize_event_time(first_present(params.get("event_time"), params.get("eventTime"), params.get("startedAtMs"), params.get("completedAt"), event.get("event_time"))),
        "confidence": confidence if event_type != "unknown" else 0.0,
        "thread_scoped": bool(thread_id),
        "turn_scoped": bool(turn_id),
        "source_quality": "codex_appserver_jsonrpc_event" if event_type != "unknown" else "codex_appserver_unknown",
        "reason": reason,
        "message": message,
        "evidence": [f"codex_appserver:{name}"] if name else [],
        "conflicts": [] if event_type != "unknown" else ["unknown_appserver_event"],
        "raw_event_ref": name,
    }


def load_events(path: str) -> list[dict[str, Any]]:
    raw = Path(path).read_text(encoding="utf-8")
    try:
        parsed = json.loads(raw)
        if isinstance(parsed, list):
            return [item for item in parsed if isinstance(item, dict)]
        if isinstance(parsed, dict):
            return [parsed]
    except json.JSONDecodeError:
        pass
    return [json.loads(line) for line in raw.splitlines() if line.strip()]


def method_names_from_schema(schema_path: Path, file_name: str) -> list[str]:
    target = schema_path / file_name
    if not target.exists():
        return []
    data = json.loads(target.read_text(encoding="utf-8"))
    names: list[str] = []

    def walk(value: Any) -> None:
        if isinstance(value, dict):
            enum = value.get("enum")
            if isinstance(enum, list):
                for item in enum:
                    if isinstance(item, str) and "/" in item:
                        names.append(item)
            for child in value.values():
                walk(child)
        elif isinstance(value, list):
            for child in value:
                walk(child)

    walk(data)
    return sorted(set(names))


def probe() -> dict[str, Any]:
    binary = codex_bin()
    result: dict[str, Any] = {
        "source": "codex_appserver",
        "codex_bin": binary,
        "binary_exists": Path(binary).exists() or shutil.which(binary) is not None,
        "supports_stdio": False,
        "supports_unix": False,
        "supports_ws": False,
        "schema_generation": False,
        "client_request_methods": [],
        "server_notification_methods": [],
        "socket_candidates": [],
    }
    completed = subprocess.run([binary, "app-server", "--help"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=5)
    help_text = completed.stdout
    result["supports_stdio"] = "stdio://" in help_text
    result["supports_unix"] = "unix://" in help_text
    result["supports_ws"] = "ws://" in help_text
    result["has_proxy_command"] = "proxy" in help_text
    result["returncode"] = completed.returncode

    with tempfile.TemporaryDirectory(prefix="codex-appserver-schema-") as tmp:
        schema = subprocess.run(
            [binary, "app-server", "generate-json-schema", "--out", tmp],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=10,
        )
        result["schema_generation"] = schema.returncode == 0
        if schema.returncode == 0:
            schema_path = Path(tmp)
            result["client_request_methods"] = method_names_from_schema(schema_path, "ClientRequest.json")[:120]
            result["server_notification_methods"] = method_names_from_schema(schema_path, "ServerNotification.json")[:120]

    search_roots = [Path.home() / ".codex", Path.home() / "Library/Application Support/Codex"]
    sockets: list[str] = []
    for root in search_roots:
        if not root.exists():
            continue
        for item in root.rglob("*"):
            if len(sockets) >= 20:
                break
            if item.is_socket() or item.suffix in {".sock", ".ipc"} or item.name == "SingletonSocket":
                sockets.append(str(item))
    result["socket_candidates"] = sockets
    return result


def write_signal(signal: dict[str, Any], spool_dir: str | None) -> None:
    if not spool_dir:
        return
    target = Path(spool_dir).expanduser()
    target.mkdir(parents=True, exist_ok=True)
    path = target / "codex_appserver.jsonl"
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(signal, ensure_ascii=True, sort_keys=True, separators=(",", ":")) + "\n")


def thread_list_signals(response: dict[str, Any], requested_thread_id: str | None) -> list[dict[str, Any]]:
    result = response.get("result") if isinstance(response.get("result"), dict) else {}
    records = result.get("data") if isinstance(result.get("data"), list) else []
    signals: list[dict[str, Any]] = []
    for record in records:
        if not isinstance(record, dict):
            continue
        thread_id = first_present(record.get("id"), record.get("sessionId"), record.get("thread_id"))
        if requested_thread_id and thread_id != requested_thread_id:
            continue
        state = status_type(record.get("status"))
        event_type = "unknown"
        confidence = 0.0
        reason = None
        message = None
        if state == "active":
            event_type = "turn_started"
            confidence = 0.82
        elif state in {"idle", "completed", "complete"}:
            event_type = "appserver_quiet"
            confidence = 0.60
        elif state in {"systemError", "errored", "failed"}:
            event_type = "tool_failed"
            confidence = 0.80
            reason = "codex_exit_failed"
            message = "Codex app-server thread list reported an error state"
        else:
            event_type = "unknown"
            confidence = 0.0
        signals.append(
            {
                "source": "codex_appserver",
                "event_type": event_type,
                "thread_id": thread_id,
                "turn_id": None,
                "item_id": None,
                "event_time": sanitize_event_time(record.get("updatedAt")),
                "confidence": confidence,
                "thread_scoped": bool(thread_id),
                "turn_scoped": False,
                "source_quality": "codex_appserver_thread_list_status",
                "reason": reason,
                "message": message,
                "evidence": [f"thread/list:status={state or 'unknown'}"],
                "conflicts": [] if event_type != "unknown" else ["thread_list_not_loaded_or_unknown"],
                "raw_event_ref": "thread/list",
            }
        )
    return signals


def send_jsonrpc(proc: subprocess.Popen[str], request_id: int, method: str, params: dict[str, Any]) -> None:
    if proc.stdin is None:
        raise RuntimeError("app-server stdin is closed")
    payload = {"jsonrpc": "2.0", "id": request_id, "method": method, "params": params}
    proc.stdin.write(json.dumps(payload, separators=(",", ":")) + "\n")
    proc.stdin.flush()


def listen(timeout: float, thread_id: str | None, spool_dir: str | None, jsonl: bool, no_thread_list: bool) -> int:
    binary = codex_bin()
    proc: subprocess.Popen[str] | None = None
    signals: list[dict[str, Any]] = []
    diagnostics: list[str] = []
    try:
        proc = subprocess.Popen(
            [binary, "app-server", "--listen", "stdio://"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
        )
        send_jsonrpc(
            proc,
            1,
            "initialize",
            {
                "clientInfo": {"name": "66tasklight-appserver-bridge", "version": "0.1"},
                "capabilities": {"experimentalApi": True},
            },
        )
        if not no_thread_list:
            send_jsonrpc(proc, 2, "thread/list", {"limit": 25, "sortKey": "updated_at", "sortDirection": "desc"})

        deadline = time.time() + max(0.5, timeout)
        while time.time() < deadline:
            if proc.stdout is None or proc.stderr is None:
                break
            ready, _, _ = select.select([proc.stdout, proc.stderr], [], [], min(0.25, max(0, deadline - time.time())))
            for stream in ready:
                line = stream.readline()
                if not line:
                    continue
                if stream is proc.stderr:
                    diagnostics.append("appserver_stderr")
                    continue
                try:
                    message = json.loads(line)
                except json.JSONDecodeError:
                    diagnostics.append("appserver_non_json_line")
                    continue
                if not isinstance(message, dict):
                    continue
                if message.get("id") == 2:
                    for signal in thread_list_signals(message, thread_id):
                        signals.append(signal)
                        write_signal(signal, spool_dir)
                    continue
                if message.get("method"):
                    signal = event_to_signal(message)
                    if thread_id and signal.get("thread_id") not in {None, thread_id}:
                        continue
                    if signal.get("event_type") != "unknown":
                        signals.append(signal)
                        write_signal(signal, spool_dir)

        if not signals:
            signal = {
                "source": "codex_appserver",
                "event_type": "unknown",
                "thread_id": thread_id,
                "turn_id": None,
                "item_id": None,
                "event_time": int(time.time()),
                "confidence": 0.0,
                "thread_scoped": bool(thread_id),
                "turn_scoped": False,
                "source_quality": "codex_appserver_listen_no_signal",
                "reason": None,
                "message": "No active Codex app-server status event was observed during the listen window",
                "evidence": ["appserver:listen_window_empty"],
                "conflicts": diagnostics[:6],
                "raw_event_ref": "listen",
            }
            signals.append(signal)
            write_signal(signal, spool_dir)
    except Exception as exc:
        signal = {
            "source": "codex_appserver",
            "event_type": "unknown",
            "thread_id": thread_id,
            "turn_id": None,
            "item_id": None,
            "event_time": int(time.time()),
            "confidence": 0.0,
            "thread_scoped": bool(thread_id),
            "turn_scoped": False,
            "source_quality": "codex_appserver_listen_error",
            "reason": None,
            "message": "Codex app-server listen failed closed",
            "evidence": ["appserver:listen_error"],
            "conflicts": [f"{type(exc).__name__}:{exc}"],
            "raw_event_ref": "listen",
        }
        signals = [signal]
    finally:
        if proc is not None:
            proc.terminate()
            try:
                proc.wait(timeout=1)
            except subprocess.TimeoutExpired:
                proc.kill()

    if jsonl:
        for signal in signals:
            print(json.dumps(signal, ensure_ascii=True, sort_keys=True, separators=(",", ":")))
    else:
        print(json.dumps(signals, ensure_ascii=True, sort_keys=True, indent=2))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Codex app-server bridge")
    parser.add_argument("--probe", action="store_true")
    parser.add_argument("--listen", action="store_true")
    parser.add_argument("--fixture")
    parser.add_argument("--timeout", type=float, default=3.0, help="listen window in seconds")
    parser.add_argument("--thread-id", help="optional thread id filter")
    parser.add_argument("--spool-dir", help="optional directory for JSONL signal spool")
    parser.add_argument("--jsonl", action="store_true", help="emit one signal JSON per line")
    parser.add_argument("--no-thread-list", action="store_true", help="skip initial thread/list probe")
    args = parser.parse_args()

    if args.probe:
        print(json.dumps(probe(), ensure_ascii=True, sort_keys=True, indent=2))
        return 0
    if args.fixture:
        signals = [event_to_signal(event) for event in load_events(args.fixture)]
        print(json.dumps(signals, ensure_ascii=True, sort_keys=True, indent=2))
        return 0
    if args.listen:
        return listen(args.timeout, args.thread_id, args.spool_dir, args.jsonl, args.no_thread_list)
    parser.error("one of --probe, --listen, or --fixture is required")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
