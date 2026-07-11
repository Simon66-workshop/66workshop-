#!/usr/bin/env python3
"""Report WidgetKit desktop acceptance readiness without signing or installing anything."""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
PACKAGE = ROOT / "mac" / "66TaskLight"
APP_ENTITLEMENTS = PACKAGE / "WidgetKitScaffold" / "66TaskLightApp.entitlements"
WIDGET_ENTITLEMENTS = PACKAGE / "WidgetKitScaffold" / "66TaskLightWidgetExtension.entitlements"
WIDGET_SOURCE = PACKAGE / "WidgetKitScaffold" / "66TaskLightWidget.swift"


def codesign_identity_count() -> int:
    security = shutil.which("security")
    if not security:
        return 0
    completed = subprocess.run(
        [security, "find-identity", "-v", "-p", "codesigning"],
        capture_output=True,
        text=True,
        check=False,
    )
    return sum(1 for line in completed.stdout.splitlines() if '"' in line and "valid identities found" not in line)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--require-ready", action="store_true")
    args = parser.parse_args()

    checks = {
        "xcodegen_available": shutil.which("xcodegen") is not None,
        "xcodebuild_available": shutil.which("xcodebuild") is not None,
        "app_entitlements_present": APP_ENTITLEMENTS.is_file(),
        "widget_entitlements_present": WIDGET_ENTITLEMENTS.is_file(),
        "widget_source_present": WIDGET_SOURCE.is_file(),
        "app_group_declared": False,
        "widget_is_sanitized": False,
    }
    app = APP_ENTITLEMENTS.read_text(encoding="utf-8") if APP_ENTITLEMENTS.is_file() else ""
    widget = WIDGET_ENTITLEMENTS.read_text(encoding="utf-8") if WIDGET_ENTITLEMENTS.is_file() else ""
    source = WIDGET_SOURCE.read_text(encoding="utf-8") if WIDGET_SOURCE.is_file() else ""
    checks["app_group_declared"] = "group.com.66tasklight.widget" in app and "group.com.66tasklight.widget" in widget
    forbidden = ("auth.json", "URLSession", "credential", "prompt", "response", "raw log")
    checks["widget_is_sanitized"] = not any(token.lower() in source.lower() for token in forbidden)
    identities = codesign_identity_count()
    ready = all(checks.values()) and identities > 0
    payload = {
        "status": "ready_for_human_desktop_acceptance" if ready else "blocked_missing_codesign_identity",
        "production_ready": False,
        "codesigning_identity_count": identities,
        "checks": checks,
        "next_action": (
            "Generate the Xcode project, sign the app and extension with one Team/App Group, install it, and add the widget from macOS Desktop widgets."
            if ready
            else "Configure a real Apple Team signing identity and App Group provisioning profile; no signing or desktop-widget claim was made."
        ),
    }
    print(json.dumps(payload, ensure_ascii=True, sort_keys=True))
    return 0 if ready or not args.require_ready else 2


if __name__ == "__main__":
    raise SystemExit(main())
