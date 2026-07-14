#!/usr/bin/env python3
"""Summarize bounded render telemetry without exposing event contents."""

from __future__ import annotations

import argparse
import json
import math
from collections import Counter, defaultdict
from pathlib import Path
from statistics import median
from typing import Any


def percentile(values: list[float], value: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    index = min(len(ordered) - 1, max(0, math.ceil((len(ordered) - 1) * value)))
    return round(ordered[index], 3)


def iter_json_objects(text: str):
    """Read both newline-delimited and legacy pretty-printed JSON records."""
    decoder = json.JSONDecoder()
    cursor = 0
    while cursor < len(text):
        while cursor < len(text) and text[cursor].isspace():
            cursor += 1
        if cursor >= len(text):
            break
        try:
            payload, cursor = decoder.raw_decode(text, cursor)
        except json.JSONDecodeError:
            next_start = text.find("{", cursor + 1)
            if next_start < 0:
                break
            cursor = next_start
            continue
        yield payload


def analyze(path: Path) -> dict[str, Any]:
    rows = []
    if path.exists():
        for payload in iter_json_objects(path.read_text(encoding="utf-8")):
            if isinstance(payload, dict) and isinstance(payload.get("load_milliseconds"), (int, float)):
                rows.append(payload)
    values = [float(row["load_milliseconds"]) for row in rows]
    thresholds = {str(limit): sum(value > limit for value in values) for limit in (160, 500, 1000)}
    stage_values: dict[str, list[float]] = defaultdict(list)
    status_counts: Counter[str] = Counter()
    for row in rows:
        status_counts[str(row.get("status") or "unknown")] += 1
        for stage, duration in (row.get("stages") or {}).items():
            if isinstance(duration, (int, float)):
                stage_values[str(stage)].append(float(duration))
    return {
        "schema_version": "m7.1",
        "source": "sanitized_render_telemetry",
        "records": len(values),
        "percentiles_ms": {
            "p50": percentile(values, 0.50),
            "p90": percentile(values, 0.90),
            "p95": percentile(values, 0.95),
            "p99": percentile(values, 0.99),
            "p99_9": percentile(values, 0.999),
            "max": round(max(values), 3) if values else 0.0,
            "mean": round(sum(values) / len(values), 3) if values else 0.0,
            "median": round(median(values), 3) if values else 0.0,
        },
        "thresholds": {
            "over_160ms": thresholds["160"],
            "over_500ms": thresholds["500"],
            "over_1000ms": thresholds["1000"],
            "over_160_ratio": round(thresholds["160"] / len(values), 6) if values else 0.0,
            "over_500_ratio": round(thresholds["500"] / len(values), 6) if values else 0.0,
            "over_1000_ratio": round(thresholds["1000"] / len(values), 6) if values else 0.0,
        },
        "status_counts": dict(sorted(status_counts.items())),
        "stage_percentiles_ms": {
            stage: {
                "records": len(stage_rows),
                "p95": percentile(stage_rows, 0.95),
                "max": round(max(stage_rows), 3),
            }
            for stage, stage_rows in sorted(stage_values.items())
        },
        "safety": {"raw_log_body_read": False, "secret_output": False},
    }


def markdown(payload: dict[str, Any]) -> str:
    p = payload["percentiles_ms"]
    t = payload["thresholds"]
    lines = [
        "# Render Performance Analysis",
        "",
        f"- Records: `{payload['records']}`",
        f"- p50/p90/p95/p99/p99.9/max: `{p['p50']} / {p['p90']} / {p['p95']} / {p['p99']} / {p['p99_9']} / {p['max']} ms`",
        f"- Over 160ms: `{t['over_160ms']}` ({t['over_160_ratio']:.2%})",
        f"- Over 500ms: `{t['over_500ms']}` ({t['over_500_ratio']:.2%})",
        f"- Over 1000ms: `{t['over_1000ms']}` ({t['over_1000_ratio']:.2%})",
        "",
        "## Stage Telemetry",
        "",
        "| Stage | Records | p95 ms | Max ms |",
        "|---|---:|---:|---:|",
    ]
    for stage, item in payload["stage_percentiles_ms"].items():
        lines.append(f"| {stage} | {item['records']} | {item['p95']} | {item['max']} |")
    lines += [
        "",
        "## Interpretation",
        "",
        "The current telemetry is sufficient to separate read-model assembly from auxiliary reads. Window construction, SwiftUI first-frame, menu, and scroll timings remain separate self-test evidence and are not inferred from this JSONL alone.",
    ]
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--output-json", required=True)
    parser.add_argument("--output-md", required=True)
    args = parser.parse_args()
    payload = analyze(Path(args.input).expanduser())
    Path(args.output_json).write_text(json.dumps(payload, ensure_ascii=True, indent=2) + "\n", encoding="utf-8")
    Path(args.output_md).write_text(markdown(payload), encoding="utf-8")
    print(f"render_analysis_status=ok records={payload['records']} max_ms={payload['percentiles_ms']['max']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
