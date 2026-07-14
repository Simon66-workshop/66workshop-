#!/usr/bin/env python3
"""Batch coverage report for Codex workspaces."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_STATE_DIR = Path.home() / ".66tasklight"

sys.path.insert(0, str(PROJECT_ROOT / "script"))
from check_codex_thread_coverage import build_parser as coverage_parser_builder  # noqa: E402
from check_codex_thread_coverage import build_report as build_thread_coverage  # noqa: E402
from check_codex_thread_coverage import check_hook_workspace  # noqa: E402
from discover_codex_workspaces import build_report as build_discovery_report  # noqa: E402


def now_string() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def state_dir() -> Path:
    return Path(os.environ.get("TASKLIGHT_STATE_DIR", str(DEFAULT_STATE_DIR))).expanduser()


def coverage_dir() -> Path:
    return Path(os.environ.get("TASKLIGHT_WORKSPACE_COVERAGE_DIR", str(state_dir() / "workspace_coverage"))).expanduser()


def atomic_write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    tmp.replace(path)


def write_run_status(status: str, message: str, latest_json: Path | None = None, latest_md: Path | None = None) -> None:
    payload = {
        "schema_version": "0.1",
        "status": status,
        "message": message,
        "updated_at": now_string(),
        "latest_json_path": str(latest_json) if latest_json else None,
        "report_path": str(latest_md) if latest_md else None,
    }
    atomic_write_json(coverage_dir() / "run_status.json", payload)


def discovery_args(args: argparse.Namespace) -> argparse.Namespace:
    return argparse.Namespace(
        root=args.root,
        config=args.config,
        max_depth=args.max_depth,
        max_workspaces=args.max_workspaces,
        output=str(coverage_dir() / "workspaces.json"),
        json=False,
    )


def classify_workspace(hook_report: dict[str, Any], thread_items: list[dict[str, Any]]) -> tuple[str, str, str]:
    hook_status = hook_report.get("hook_status")
    hook_detail = hook_report.get("hook_detail")
    hook_visibility = hook_report.get("hook_visibility")
    if hook_status == "missing":
        return "missing_hooks", "这个 workspace 还没安装 hooks", "run install_hooks_for_workspaces"
    if hook_status == "invalid":
        return "invalid_hooks", "这个 workspace 的 hooks 配置不可用", "reinstall hooks for this workspace"
    if hook_status == "unknown_manual_required":
        return "installed_needs_trust", "hooks 已安装，但需要在 Codex UI 点 Trust", "open this Codex workspace and trust hooks"
    if hook_status == "probe_unavailable" or hook_report.get("codex_appserver") == "unavailable":
        return "probe_unavailable", "本地 app-server 探针不可用，不能据此否定已有 Trust", "retry the local app-server probe later"
    if any(item.get("decision") == "covered_running" for item in thread_items):
        return "trusted", "已有 fresh hook/appserver evidence，可以驱动状态灯", "no action"
    if any(item.get("decision") == "diagnostic_only" for item in thread_items):
        return "diagnostic_only", "只有弱观察信号，不会点亮 RUNNING", "wait for hook/appserver active evidence"
    if hook_visibility == "hidden_not_loaded" or hook_report.get("codex_appserver") == "not_loaded" or hook_detail == "needs_trust_or_reload":
        return "not_loaded", "Codex 还没加载这个 workspace 的 hooks", "reload the workspace in Codex"
    if hook_visibility == "visible_untrusted":
        return "installed_needs_trust", "hooks 已安装，但需要在 Codex UI 点 Trust", "open this Codex workspace and trust hooks"
    if hook_status == "ok":
        return "trusted", "状态入口正常", "no action"
    return "unknown", "暂时无法判断这个 workspace 的状态入口", "run single-workspace coverage check"


def build_thread_report(args: argparse.Namespace, workspaces: list[str]) -> dict[str, Any]:
    parser = coverage_parser_builder()
    coverage_args = parser.parse_args([])
    coverage_args.workspace = workspaces
    coverage_args.state_dir = args.state_dir
    coverage_args.signal_limit = args.signal_limit
    coverage_args.ttl_seconds = args.ttl_seconds
    coverage_args.appserver_timeout = args.appserver_timeout
    coverage_args.skip_appserver = args.skip_appserver
    coverage_args.signals_path = os.environ.get(
        "TASKLIGHT_NORMALIZED_SIGNALS_PATH",
        str(Path(args.state_dir).expanduser() / "normalized_signals.jsonl"),
    )
    coverage_args.default_workspace = "unknown"
    return build_thread_coverage(coverage_args)


def render_markdown(report: dict[str, Any]) -> str:
    summary = report["summary"]
    lines = [
        "# 66TaskLight Workspace Coverage",
        "",
        f"- Generated: `{report['generated_at']}`",
        f"- Status: `{report['status']}`",
        f"- Workspaces: `{summary['workspace_count']}`",
        f"- Preferred workspaces: `{summary['preferred_workspace_count']}`",
        f"- Preferred need Trust: `{summary['preferred_installed_needs_trust']}`",
        f"- Preferred missing hooks: `{summary['preferred_missing_hooks']}`",
        f"- Trusted: `{summary['trusted']}`",
        f"- Need Trust: `{summary['installed_needs_trust']}`",
        f"- Missing hooks: `{summary['missing_hooks']}`",
        f"- Invalid hooks: `{summary['invalid_hooks']}`",
        f"- Diagnostic only: `{summary['diagnostic_only']}`",
        "",
        "## Preferred Workspaces",
        "",
    ]
    preferred = [item for item in report["workspaces"] if item.get("workspace_group") == "preferred"]
    non_preferred = [item for item in report["workspaces"] if item.get("workspace_group") != "preferred"]
    for item in preferred:
        lines.extend(
            [
                f"### {item['name']}",
                f"- Path: `{item['workspace']}`",
                f"- Coverage: `{item['coverage_status']}`",
                f"- Hook: `{item['hook_status']}` / `{item['hook_detail']}`",
                f"- UI visibility: `{item.get('hook_visibility')}` / `{item.get('hook_visibility_reason')}`",
                f"- Reason: {item['reason']}",
                f"- Recommended action: `{item['recommended_action']}`",
                "",
            ]
        )
    lines.extend(["## Discovered Non-Preferred Workspaces", ""])
    for item in non_preferred:
        lines.extend(
            [
                f"### {item['name']}",
                f"- Path: `{item['workspace']}`",
                f"- Coverage: `{item['coverage_status']}`",
                f"- Hook: `{item['hook_status']}` / `{item['hook_detail']}`",
                f"- UI visibility: `{item.get('hook_visibility')}` / `{item.get('hook_visibility_reason')}`",
                f"- Reason: {item['reason']}",
                f"- Recommended action: `{item['recommended_action']}`",
                "",
            ]
        )
    return "\n".join(lines).rstrip() + "\n"


def open_report(path: Path) -> None:
    try:
        subprocess.Popen(["/usr/bin/open", str(path)])
    except OSError:
        pass


def build_report(args: argparse.Namespace) -> dict[str, Any]:
    discovery = build_discovery_report(discovery_args(args))
    workspaces = [item["workspace"] for item in discovery["workspaces"]]
    groups_by_workspace = {item["workspace"]: item.get("workspace_group", "discovered_non_preferred") for item in discovery["workspaces"]}
    thread_report = build_thread_report(args, workspaces)
    threads_by_workspace: dict[str, list[dict[str, Any]]] = {}
    for thread in thread_report.get("threads", []):
        threads_by_workspace.setdefault(str(thread.get("workspace") or "unknown"), []).append(thread)

    records: list[dict[str, Any]] = []
    counts = {
        "trusted": 0,
        "installed_needs_trust": 0,
        "missing_hooks": 0,
        "invalid_hooks": 0,
        "not_loaded": 0,
        "diagnostic_only": 0,
        "probe_unavailable": 0,
        "unknown": 0,
    }
    for workspace in workspaces:
        hook_report = check_hook_workspace(workspace, skip_appserver=args.skip_appserver, appserver_timeout=args.appserver_timeout)
        thread_items = threads_by_workspace.get(workspace, [])
        coverage_status, reason, action = classify_workspace(hook_report, thread_items)
        counts[coverage_status] = counts.get(coverage_status, 0) + 1
        records.append(
            {
                "workspace": workspace,
                "name": Path(workspace).name,
                "workspace_group": groups_by_workspace.get(workspace, "discovered_non_preferred"),
                "preferred": groups_by_workspace.get(workspace) == "preferred",
                "coverage_status": coverage_status,
                "reason": reason,
                "recommended_action": action,
                "hook_status": hook_report.get("hook_status"),
                "hook_detail": hook_report.get("hook_detail"),
                "hook_visibility": hook_report.get("hook_visibility"),
                "hook_visibility_reason": hook_report.get("hook_visibility_reason"),
                "codex_appserver": hook_report.get("codex_appserver"),
                "thread_count": len(thread_items),
                "covered_running": sum(1 for item in thread_items if item.get("decision") == "covered_running"),
                "diagnostic_only": sum(1 for item in thread_items if item.get("decision") == "diagnostic_only"),
            }
        )

    status = "ok"
    if counts["missing_hooks"] or counts["invalid_hooks"]:
        status = "needs_hooks"
    elif counts["installed_needs_trust"] or counts["not_loaded"]:
        status = "needs_trust"
    elif counts["probe_unavailable"]:
        status = "probe_unavailable"
    elif counts["unknown"]:
        status = "unknown"

    preferred_records = [item for item in records if item.get("preferred")]
    preferred_counts = {
        "preferred_workspace_count": len(preferred_records),
        "preferred_trusted": sum(1 for item in preferred_records if item["coverage_status"] == "trusted"),
        "preferred_installed_needs_trust": sum(1 for item in preferred_records if item["coverage_status"] == "installed_needs_trust"),
        "preferred_missing_hooks": sum(1 for item in preferred_records if item["coverage_status"] == "missing_hooks"),
        "preferred_invalid_hooks": sum(1 for item in preferred_records if item["coverage_status"] == "invalid_hooks"),
    }
    active_recent_records = [item for item in records if int(item.get("covered_running") or 0) > 0]
    group_counts = {}
    for group in ("preferred", "active_recent", "optional", "archived", "temporary", "unknown"):
        group_counts[f"{group}_total"] = sum(1 for item in records if item.get("workspace_group") == group)
    group_counts["active_recent_total"] = len(active_recent_records)
    group_counts["active_recent_trusted"] = sum(1 for item in active_recent_records if item["coverage_status"] == "trusted")
    group_counts["active_recent_missing"] = sum(1 for item in active_recent_records if item["coverage_status"] == "missing_hooks")
    group_counts["overall_total"] = len(records)
    group_counts["overall_missing"] = counts["missing_hooks"]
    group_counts["probe_status"] = "unavailable" if counts["probe_unavailable"] else "available"

    return {
        "schema_version": "0.1",
        "generated_at": now_string(),
        "status": status,
        "summary": {"workspace_count": len(records), **counts, **preferred_counts, **group_counts},
        "workspaces": sorted(records, key=lambda item: (not item.get("preferred", False), item["coverage_status"], item["workspace"])),
        "thread_summary": thread_report.get("summary", {}),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Batch-check Codex workspace coverage for 66TaskLight")
    parser.add_argument("--root", action="append")
    parser.add_argument("--config", default=os.environ.get("TASKLIGHT_WORKSPACE_COVERAGE_CONFIG", str(PROJECT_ROOT / "config" / "workspace_coverage.json")))
    parser.add_argument("--state-dir", default=str(state_dir()))
    parser.add_argument("--max-depth", type=int, default=int(os.environ.get("TASKLIGHT_WORKSPACE_SCAN_MAX_DEPTH", "5")))
    parser.add_argument("--max-workspaces", type=int, default=int(os.environ.get("TASKLIGHT_WORKSPACE_SCAN_MAX_COUNT", "300")))
    parser.add_argument("--signal-limit", type=int, default=2000)
    parser.add_argument("--ttl-seconds", type=float, default=float(os.environ.get("TASKLIGHT_COVERAGE_ACTIVE_TTL_SECONDS", "30")))
    parser.add_argument("--appserver-timeout", type=float, default=1.5)
    parser.add_argument("--skip-appserver", action="store_true")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--open-report", action="store_true")
    args = parser.parse_args()

    latest_json = coverage_dir() / "latest.json"
    latest_md = coverage_dir() / "latest.md"
    write_run_status("running", "正在检查 Codex 项目...", latest_json, latest_md)
    try:
        report = build_report(args)
        atomic_write_json(latest_json, report)
        latest_md.write_text(render_markdown(report), encoding="utf-8")
        message = "状态入口正常"
        summary = report["summary"]
        if summary.get("preferred_installed_needs_trust", 0) > 0:
            message = f"常用项目 {summary['preferred_installed_needs_trust']} 个需要 Trust"
        elif summary.get("preferred_missing_hooks", 0) > 0:
            message = f"常用项目 {summary['preferred_missing_hooks']} 个缺 hooks"
        elif summary.get("preferred_invalid_hooks", 0) > 0:
            message = f"常用项目 {summary['preferred_invalid_hooks']} 个 hooks 异常"
        elif summary.get("installed_needs_trust", 0) > 0:
            message = f"发现 {summary['installed_needs_trust']} 个项目需要 Trust"
        elif summary.get("missing_hooks", 0) > 0:
            message = f"有 {summary['missing_hooks']} 个项目缺 hooks"
        elif summary.get("invalid_hooks", 0) > 0:
            message = f"有 {summary['invalid_hooks']} 个 hooks 配置异常"
        write_run_status("ok", message, latest_json, latest_md)
    except Exception as exc:
        write_run_status("error", f"巡检失败: {exc}", latest_json, latest_md)
        raise

    if args.open_report:
        open_report(latest_md)
    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True))
    else:
        print(f"STATUS={report['status']}")
        for key, value in report["summary"].items():
            print(f"{key}={value}")
        print(f"report={latest_md}")
        for item in report["workspaces"][:50]:
            print(f"workspace={item['workspace']} coverage_status={item['coverage_status']} hook_status={item['hook_status']} reason={item['reason']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
