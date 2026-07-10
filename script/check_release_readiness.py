#!/usr/bin/env python3
"""Report WidgetKit and production signing readiness without overclaiming."""

from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def has_codesign_identity() -> bool:
    completed = subprocess.run(
        ["/usr/bin/security", "find-identity", "-p", "codesigning", "-v"],
        text=True,
        capture_output=True,
        check=False,
    )
    return completed.returncode == 0 and "0 valid identities found" not in completed.stdout


def report() -> dict[str, object]:
    project = (ROOT / "mac/66TaskLight/project.yml").read_text(encoding="utf-8")
    widget_source = ROOT / "mac/66TaskLight/WidgetKitScaffold/66TaskLightWidget.swift"
    app_entitlements = ROOT / "mac/66TaskLight/WidgetKitScaffold/66TaskLightApp.entitlements"
    widget_entitlements = ROOT / "mac/66TaskLight/WidgetKitScaffold/66TaskLightWidgetExtension.entitlements"
    widget_target = all((
        "66TaskLightWidgetExtension" in project,
        "type: app-extension" in project,
        widget_source.exists(),
        app_entitlements.exists(),
        widget_entitlements.exists(),
    ))
    signing_identity = has_codesign_identity()
    return {
        "schema_version": "0.1",
        "widget_target_status": "ready_for_team_signing" if widget_target else "incomplete",
        "widget_target_configured": widget_target,
        "app_group_configured": "group.com.66tasklight.widget" in app_entitlements.read_text(encoding="utf-8") if app_entitlements.exists() else False,
        "signed_update_workflow": (ROOT / "script/sign_update_manifest.py").exists() and (ROOT / "script/verify_update_manifest.py").exists(),
        "developer_id_identity_available": signing_identity,
        "production_signing_status": "ready" if signing_identity else "blocked_missing_codesign_identity",
        "notarization_status": "not_run",
        "production_ready": bool(widget_target and signing_identity),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Check TaskLight release readiness")
    parser.add_argument("--require-production", action="store_true")
    args = parser.parse_args()
    payload = report()
    print(json.dumps(payload, ensure_ascii=True, sort_keys=True, indent=2))
    return 0 if payload["production_ready"] or not args.require_production else 2


if __name__ == "__main__":
    raise SystemExit(main())
