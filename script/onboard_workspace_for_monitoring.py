#!/usr/bin/env python3
"""Install workspace hooks and summarize monitoring readiness."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Any


PROJECT_ROOT = Path(__file__).resolve().parents[1]
INSTALL_SCRIPT = PROJECT_ROOT / "script" / "install_hooks_for_workspace.sh"
COVERAGE_SCRIPT = PROJECT_ROOT / "script" / "check_codex_thread_coverage.py"
TRUST_SCRIPT = PROJECT_ROOT / "script" / "check_codex_hooks_trust.py"


def run_command(args: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        cwd=str(PROJECT_ROOT),
        text=True,
        capture_output=True,
        check=False,
    )


def run_json(args: list[str], *, allow_nonzero: bool = False) -> dict[str, Any]:
    proc = run_command(args)
    if proc.returncode != 0 and not allow_nonzero:
        raise RuntimeError(proc.stderr.strip() or proc.stdout.strip() or f"command failed: {' '.join(args)}")
    try:
        payload = json.loads(proc.stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"invalid json output from {' '.join(args)}: {exc}") from exc
    if not isinstance(payload, dict):
        raise RuntimeError(f"unexpected json shape from {' '.join(args)}")
    return payload


def core_hook_config_ok(payload: dict[str, Any]) -> bool:
    return all(
        payload.get(key) == "ok"
        for key in ("project_root", "codex_dir", "hook_config", "hook_reference", "hook_handler", "hook_health")
    )


def derive_onboarding_state(
    *,
    coverage: dict[str, Any],
    trust: dict[str, Any],
    skip_appserver: bool,
) -> tuple[str, str]:
    if not core_hook_config_ok(trust):
        return "misconfigured", "fix hook configuration in this workspace"

    visibility = str(trust.get("hook_visibility") or "")
    if visibility == "visible_trusted":
        return "ready", "monitoring is active for this workspace; start a new turn to verify live signals"
    if visibility == "visible_untrusted":
        return "needs_trust", "open this workspace in Codex UI and trust project hooks"
    if visibility == "hidden_not_loaded":
        return "needs_reload_then_trust", "open this workspace in Codex UI, then trust hooks if prompted"
    if visibility == "visible_unknown":
        return "needs_ui_check", str(trust.get("next_action") or "check Codex UI hook state")

    hook_status = str(coverage.get("hook_status") or "")
    if skip_appserver and hook_status == "ok":
        return "configured_check_ui", "hooks are installed; open this workspace in Codex UI and trust hooks if prompted"
    if hook_status == "ok":
        return "configured_check_ui", "hooks are installed; reopen this workspace in Codex UI and confirm hooks are visible"
    return "needs_ui_check", str(trust.get("next_action") or "check Codex UI hook state")


def summarize_counts(results: list[dict[str, Any]]) -> dict[str, int]:
    counts: dict[str, int] = {}
    for item in results:
        state = str(item.get("onboarding_status") or "unknown")
        counts[state] = counts.get(state, 0) + 1
    return counts


def onboard_workspace(workspace_arg: str, *, skip_appserver: bool) -> dict[str, Any]:
    workspace = Path(workspace_arg).expanduser().resolve()
    if not workspace.exists() or not workspace.is_dir():
        return {
            "workspace": str(workspace),
            "install_status": "missing_workspace",
            "onboarding_status": "missing_workspace",
            "next_action": "verify the workspace path, then rerun onboarding",
        }

    install_proc = run_command([str(INSTALL_SCRIPT), str(workspace)])
    install_status = "installed" if install_proc.returncode == 0 else "install_failed"
    if install_proc.returncode != 0:
        return {
            "workspace": str(workspace),
            "install_status": install_status,
            "install_stdout": install_proc.stdout.strip(),
            "install_stderr": install_proc.stderr.strip(),
            "onboarding_status": "install_failed",
            "next_action": "inspect install error and rerun onboarding",
        }

    coverage_args = ["python3", str(COVERAGE_SCRIPT), "--json", "--workspace", str(workspace)]
    trust_args = ["python3", str(TRUST_SCRIPT), "--json", "--project-root", str(workspace)]
    if skip_appserver:
        coverage_args.append("--skip-appserver")
        trust_args.append("--skip-appserver")

    coverage_report = run_json(coverage_args)
    # A missing local app-server is an expected pre-Trust state for a newly
    # added workspace. Keep the structured report so onboarding can still tell
    # the user to open Codex UI and approve hooks manually.
    trust_report = run_json(trust_args, allow_nonzero=True)
    coverage = ((coverage_report.get("workspaces") or {}).get(str(workspace)) or {})
    onboarding_status, next_action = derive_onboarding_state(
        coverage=coverage,
        trust=trust_report,
        skip_appserver=skip_appserver,
    )
    return {
        "workspace": str(workspace),
        "install_status": install_status,
        "coverage_hook_status": coverage.get("hook_status"),
        "coverage_hook_detail": coverage.get("hook_detail"),
        "coverage_appserver": coverage.get("codex_appserver"),
        "hook_visibility": trust_report.get("hook_visibility"),
        "hook_visibility_reason": trust_report.get("hook_visibility_reason"),
        "project_trust": trust_report.get("project_trust"),
        "trust_status": trust_report.get("status"),
        "onboarding_status": onboarding_status,
        "next_action": next_action,
    }


def print_human(results: list[dict[str, Any]]) -> None:
    for index, item in enumerate(results):
        if index:
            print("")
        print(f"WORKSPACE: {item['workspace']}")
        print(f"INSTALL_STATUS: {item['install_status']}")
        print(f"ONBOARDING_STATUS: {item['onboarding_status']}")
        if item.get("coverage_hook_status") is not None:
            print(f"COVERAGE_HOOK_STATUS: {item['coverage_hook_status']}")
        if item.get("coverage_hook_detail") is not None:
            print(f"COVERAGE_HOOK_DETAIL: {item['coverage_hook_detail']}")
        if item.get("coverage_appserver") is not None:
            print(f"COVERAGE_APPSERVER: {item['coverage_appserver']}")
        if item.get("hook_visibility") is not None:
            print(f"HOOK_VISIBILITY: {item['hook_visibility']}")
        if item.get("hook_visibility_reason") is not None:
            print(f"HOOK_VISIBILITY_REASON: {item['hook_visibility_reason']}")
        if item.get("project_trust") is not None:
            print(f"PROJECT_TRUST: {item['project_trust']}")
        if item.get("trust_status") is not None:
            print(f"TRUST_STATUS: {item['trust_status']}")
        print(f"NEXT_ACTION: {item['next_action']}")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Install 66TaskLight monitoring hooks into one or more Codex workspaces")
    parser.add_argument("paths", nargs="*")
    parser.add_argument("--workspace", action="append", default=[])
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--skip-appserver", action="store_true")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    targets = list(args.workspace) + list(args.paths)
    if not targets:
        raise SystemExit("usage: onboard_workspace_for_monitoring.py --workspace /path/to/project")

    results = [onboard_workspace(target, skip_appserver=args.skip_appserver) for target in targets]
    summary = {
        "workspace_count": len(results),
        "status_counts": summarize_counts(results),
    }
    payload = {"results": results, "summary": summary}
    if args.json:
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True, indent=2))
    else:
        print_human(results)
    failure_states = {"missing_workspace", "install_failed", "misconfigured"}
    return 1 if any(item.get("onboarding_status") in failure_states for item in results) else 0


if __name__ == "__main__":
    raise SystemExit(main())
