#!/usr/bin/env python3
"""Discover local Codex workspaces for 66TaskLight hook coverage checks."""

from __future__ import annotations

import argparse
import fnmatch
import json
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_STATE_DIR = Path.home() / ".66tasklight"
DEFAULT_CONFIG_PATH = PROJECT_ROOT / "config" / "workspace_coverage.json"
DEFAULT_ROOTS = [
    Path.home() / "Documents",
    Path("/Volumes/2T扩展盘"),
]
SKIP_DIR_NAMES = {
    ".Trash",
    ".build",
    ".cache",
    ".git",
    ".swiftpm",
    "__pycache__",
    "Library",
    "DerivedData",
    "dist",
    "node_modules",
    "target",
}
PROJECT_MARKERS = {
    "AGENTS.md",
    "Package.swift",
    "go.mod",
    "package.json",
    "pyproject.toml",
}


def now_string() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def state_dir() -> Path:
    return Path(os.environ.get("TASKLIGHT_STATE_DIR", str(DEFAULT_STATE_DIR))).expanduser()


def coverage_dir() -> Path:
    return Path(os.environ.get("TASKLIGHT_WORKSPACE_COVERAGE_DIR", str(state_dir() / "workspace_coverage"))).expanduser()


def default_output_path() -> Path:
    return coverage_dir() / "workspaces.json"


def load_config(path: str | None = None) -> dict[str, Any]:
    raw_path = path or os.environ.get("TASKLIGHT_WORKSPACE_COVERAGE_CONFIG") or str(DEFAULT_CONFIG_PATH)
    config_path = Path(raw_path).expanduser()
    try:
        payload = json.loads(config_path.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return {}
    return payload if isinstance(payload, dict) else {}


def configured_roots(config: dict[str, Any]) -> list[Path]:
    raw = os.environ.get("TASKLIGHT_WORKSPACE_SCAN_ROOTS")
    if raw:
        return [Path(item).expanduser() for item in raw.split(":") if item.strip()]
    configured = config.get("include_roots")
    if isinstance(configured, list) and configured:
        return [Path(str(item)).expanduser() for item in configured if str(item).strip()]
    return DEFAULT_ROOTS


def normalized_path(path: Path) -> str:
    return str(path.expanduser().resolve())


def path_matches_pattern(path: Path, pattern: str) -> bool:
    text = str(path)
    return fnmatch.fnmatch(text, pattern) or fnmatch.fnmatch(path.name, pattern)


def should_skip(path: Path, exclude_patterns: list[str]) -> bool:
    if path.name in SKIP_DIR_NAMES:
        return True
    if path.name.startswith(".") and path.name not in {".codex"}:
        return True
    if any(path_matches_pattern(path, pattern) for pattern in exclude_patterns):
        return True
    return False


def has_project_marker(path: Path) -> bool:
    if (path / ".codex").is_dir():
        return True
    if (path / ".git").is_dir():
        return True
    return any((path / marker).exists() for marker in PROJECT_MARKERS)


def workspace_record(path: Path, root: Path, preferred: set[str]) -> dict[str, Any]:
    codex_dir = path / ".codex"
    hooks_path = codex_dir / "hooks.json"
    config_path = codex_dir / "config.toml"
    markers = sorted(marker for marker in PROJECT_MARKERS if (path / marker).exists())
    if (path / ".codex").is_dir():
        markers.append(".codex")
    if (path / ".git").is_dir():
        markers.append(".git")
    return {
        "workspace": str(path),
        "root": str(root),
        "has_codex_dir": codex_dir.is_dir(),
        "hooks_json_exists": hooks_path.exists(),
        "config_toml_exists": config_path.exists(),
        "markers": markers,
        "workspace_group": "preferred" if str(path) in preferred else "discovered_non_preferred",
        "preferred": str(path) in preferred,
    }


def discover(root_paths: list[Path], max_depth: int, max_workspaces: int, exclude_patterns: list[str], preferred: set[str]) -> list[dict[str, Any]]:
    found: dict[str, dict[str, Any]] = {}
    for raw_root in root_paths:
        root = raw_root.expanduser()
        if not root.exists() or not root.is_dir():
            continue
        root = root.resolve()
        base_depth = len(root.parts)
        for current, dirnames, _ in os.walk(root):
            current_path = Path(current)
            depth = len(current_path.parts) - base_depth
            dirnames[:] = [name for name in dirnames if not should_skip(current_path / name, exclude_patterns)]
            if depth > max_depth:
                dirnames[:] = []
                continue
            if has_project_marker(current_path):
                resolved = current_path.resolve()
                if any(path_matches_pattern(resolved, pattern) for pattern in exclude_patterns):
                    continue
                found[str(resolved)] = workspace_record(resolved, root, preferred)
                if len(found) >= max_workspaces:
                    return sorted(found.values(), key=lambda item: item["workspace"])
                if (current_path / ".codex").is_dir() or (current_path / ".git").is_dir():
                    dirnames[:] = []
    return sorted(found.values(), key=lambda item: item["workspace"])


def build_report(args: argparse.Namespace) -> dict[str, Any]:
    config = load_config(args.config)
    roots = [Path(item).expanduser() for item in args.root] if args.root else configured_roots(config)
    exclude_patterns = [str(item) for item in config.get("exclude_patterns", []) if str(item).strip()]
    preferred = {normalized_path(Path(str(item))) for item in config.get("preferred_workspaces", []) if str(item).strip()}
    workspaces = discover(roots, args.max_depth, args.max_workspaces, exclude_patterns, preferred)
    discovered_paths = {item["workspace"] for item in workspaces}
    for raw in sorted(preferred - discovered_paths):
        path = Path(raw)
        if path.exists() and path.is_dir() and not any(path_matches_pattern(path, pattern) for pattern in exclude_patterns):
            workspaces.append(workspace_record(path.resolve(), path.resolve().parent, preferred))
    workspaces = sorted(workspaces, key=lambda item: (not item.get("preferred", False), item["workspace"]))
    return {
        "schema_version": "0.1",
        "generated_at": now_string(),
        "roots": [str(path) for path in roots],
        "config_path": str(Path(args.config).expanduser()) if args.config else str(Path(os.environ.get("TASKLIGHT_WORKSPACE_COVERAGE_CONFIG", str(DEFAULT_CONFIG_PATH))).expanduser()),
        "exclude_patterns": exclude_patterns,
        "preferred_workspace_count": sum(1 for item in workspaces if item.get("preferred")),
        "workspace_count": len(workspaces),
        "workspaces": workspaces,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Discover Codex workspaces for 66TaskLight")
    parser.add_argument("--root", action="append", help="scan root; may be repeated")
    parser.add_argument("--config", default=os.environ.get("TASKLIGHT_WORKSPACE_COVERAGE_CONFIG", str(DEFAULT_CONFIG_PATH)))
    parser.add_argument("--max-depth", type=int, default=int(os.environ.get("TASKLIGHT_WORKSPACE_SCAN_MAX_DEPTH", "5")))
    parser.add_argument("--max-workspaces", type=int, default=int(os.environ.get("TASKLIGHT_WORKSPACE_SCAN_MAX_COUNT", "300")))
    parser.add_argument("--output", default=str(default_output_path()))
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    report = build_report(args)
    output = Path(args.output).expanduser()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True))
    else:
        print(f"workspace_count={report['workspace_count']}")
        print(f"output={output}")
        for item in report["workspaces"][:50]:
            print(f"workspace={item['workspace']} hooks_json_exists={str(item['hooks_json_exists']).lower()} has_codex_dir={str(item['has_codex_dir']).lower()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
