#!/usr/bin/env python3
"""Incrementally index TaskLight JSONL history and publish anomaly metrics."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sqlite3
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


DEFAULT_STATE_DIR = Path.home() / ".66tasklight"
STREAMS = {
    "signals": "normalized_signals.jsonl",
    "ui_flow": "ui_event_flow.jsonl",
    "events": "events.jsonl",
    "quota": "quota_history.jsonl",
}


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def state_dir() -> Path:
    return Path(os.environ.get("TASKLIGHT_STATE_DIR", str(DEFAULT_STATE_DIR))).expanduser()


def database_path(root: Path) -> Path:
    return Path(os.environ.get("TASKLIGHT_HISTORY_DB_PATH", str(root / "history.sqlite3"))).expanduser()


def summary_path(root: Path) -> Path:
    return Path(os.environ.get("TASKLIGHT_ANOMALY_SUMMARY_PATH", str(root / "anomaly_summary.json"))).expanduser()


def connect(path: Path) -> sqlite3.Connection:
    path.parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(path, timeout=2.0)
    db.execute("pragma journal_mode=WAL")
    db.execute("pragma synchronous=NORMAL")
    db.execute("pragma busy_timeout=2000")
    db.executescript(
        """
        create table if not exists history (
          event_key text primary key,
          stream text not null,
          occurred_at text,
          event_type text,
          status text,
          identity text,
          source text,
          payload_json text not null,
          indexed_at text not null
        );
        create index if not exists history_stream_time on history(stream, occurred_at desc);
        create index if not exists history_identity_time on history(identity, occurred_at desc);
        create table if not exists source_offsets (
          path text primary key,
          inode integer not null,
          byte_offset integer not null,
          updated_at text not null
        );
        create table if not exists ingest_stats (
          stream text primary key,
          input_rows integer not null default 0,
          duplicate_rows integer not null default 0,
          invalid_rows integer not null default 0,
          updated_at text not null
        );
        """
    )
    return db


def parse_ts(value: Any) -> float | None:
    if value is None:
        return None
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def event_key(stream: str, payload: dict[str, Any]) -> str:
    explicit = payload.get("signal_id") or payload.get("event_id") or payload.get("sample_id")
    if explicit:
        return f"{stream}:{explicit}"
    stable = json.dumps(payload, ensure_ascii=True, sort_keys=True, separators=(",", ":"))
    return f"{stream}:sha256:{hashlib.sha256(stable.encode()).hexdigest()}"


def event_fields(payload: dict[str, Any]) -> tuple[str | None, str | None, str | None, str | None, str | None]:
    occurred_at = payload.get("occurred_at") or payload.get("recorded_at") or payload.get("captured_at") or payload.get("updated_at")
    event_type = payload.get("event_type") or payload.get("event") or payload.get("action")
    status = payload.get("to_status") or payload.get("status_hint") or payload.get("status")
    identity = payload.get("thread_id") or payload.get("task_id") or payload.get("observation_id") or payload.get("bucket_id")
    source = payload.get("source")
    return tuple(None if value is None else str(value) for value in (occurred_at, event_type, status, identity, source))


def ingest_file(db: sqlite3.Connection, stream: str, path: Path) -> dict[str, int]:
    stats = {"input": 0, "duplicates": 0, "invalid": 0, "inserted": 0}
    if not path.exists():
        return stats
    stat = path.stat()
    row = db.execute("select inode, byte_offset from source_offsets where path=?", (str(path),)).fetchone()
    offset = int(row[1]) if row and int(row[0]) == int(stat.st_ino) and int(row[1]) <= stat.st_size else 0
    with path.open("rb") as handle:
        handle.seek(offset)
        for raw in handle:
            stats["input"] += 1
            try:
                payload = json.loads(raw.decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError):
                stats["invalid"] += 1
                continue
            if not isinstance(payload, dict):
                stats["invalid"] += 1
                continue
            key = event_key(stream, payload)
            occurred_at, event_type, status, identity, source = event_fields(payload)
            before = db.total_changes
            db.execute(
                "insert or ignore into history values(?,?,?,?,?,?,?,?,?)",
                (key, stream, occurred_at, event_type, status, identity, source,
                 json.dumps(payload, ensure_ascii=True, sort_keys=True, separators=(",", ":")), now_iso()),
            )
            if db.total_changes == before:
                stats["duplicates"] += 1
            else:
                stats["inserted"] += 1
        new_offset = handle.tell()
    db.execute(
        "insert into source_offsets values(?,?,?,?) on conflict(path) do update set inode=excluded.inode, byte_offset=excluded.byte_offset, updated_at=excluded.updated_at",
        (str(path), int(stat.st_ino), int(new_offset), now_iso()),
    )
    db.execute(
        """insert into ingest_stats values(?,?,?,?,?)
           on conflict(stream) do update set
             input_rows=input_rows+excluded.input_rows,
             duplicate_rows=duplicate_rows+excluded.duplicate_rows,
             invalid_rows=invalid_rows+excluded.invalid_rows,
             updated_at=excluded.updated_at""",
        (stream, stats["input"], stats["duplicates"], stats["invalid"], now_iso()),
    )
    return stats


def anomaly_summary(db: sqlite3.Connection, root: Path) -> dict[str, Any]:
    now_ts = time.time()
    total = int(db.execute("select count(*) from history").fetchone()[0])
    signal_path = root / STREAMS["signals"]
    signal_ids: list[str] = []
    try:
        for raw in signal_path.read_text(encoding="utf-8").splitlines():
            payload = json.loads(raw)
            if isinstance(payload, dict):
                signal_ids.append(event_key("signals", payload))
    except (FileNotFoundError, OSError, json.JSONDecodeError):
        signal_ids = []
    duplicate_rate = (len(signal_ids) - len(set(signal_ids))) / max(1, len(signal_ids))
    transitions: list[tuple[str | None, str | None]] = db.execute(
        "select occurred_at, payload_json from history where stream='ui_flow' order by occurred_at desc limit 500"
    ).fetchall()
    flaps = 0
    for occurred_at, raw in transitions:
        ts = parse_ts(occurred_at)
        if ts is None or now_ts - ts > 3600:
            continue
        try:
            payload = json.loads(raw)
        except json.JSONDecodeError:
            continue
        if payload.get("from_status") != payload.get("to_status"):
            flaps += 1

    anomalies: list[dict[str, Any]] = []
    if duplicate_rate >= 0.01:
        anomalies.append({"code": "duplicate_signal_rate", "severity": "warning", "value": round(duplicate_rate, 4), "budget": 0.01})
    if flaps > 30:
        anomalies.append({"code": "status_flap_1h", "severity": "warning", "value": flaps, "budget": 30})
    return {
        "schema_version": "0.1",
        "generated_at": now_iso(),
        "status": "warning" if anomalies else "ok",
        "history_database": str(database_path(root)),
        "history_row_count": total,
        "duplicate_signal_rate": round(duplicate_rate, 6),
        "duplicate_signal_budget": 0.01,
        "status_transition_count_1h": flaps,
        "status_transition_budget_1h": 30,
        "anomalies": anomalies,
    }


def atomic_write(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(payload, ensure_ascii=True, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    os.replace(tmp, path)


def refresh_history_index(root: Path | None = None) -> dict[str, Any]:
    root = root or state_dir()
    db = connect(database_path(root))
    try:
        with db:
            for stream, filename in STREAMS.items():
                ingest_file(db, stream, root / filename)
        summary = anomaly_summary(db, root)
    finally:
        db.close()
    atomic_write(summary_path(root), summary)
    return summary


def main() -> int:
    parser = argparse.ArgumentParser(description="Index TaskLight history into SQLite")
    parser.add_argument("--once", action="store_true")
    parser.add_argument("--watch", action="store_true")
    parser.add_argument("--poll-seconds", type=float, default=15)
    args = parser.parse_args()
    if args.once:
        print(json.dumps(refresh_history_index(), ensure_ascii=True, sort_keys=True))
        return 0
    if not args.watch:
        parser.error("choose --once or --watch")
    while True:
        refresh_history_index()
        time.sleep(max(5, args.poll_seconds))


if __name__ == "__main__":
    raise SystemExit(main())
