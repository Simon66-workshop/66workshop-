from __future__ import annotations

import argparse
import dataclasses
import fcntl
import hashlib
import json
import os
import re
import secrets
import sys
import tempfile
import subprocess
import time
from contextlib import contextmanager
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Optional


APP_NAME = "66TaskLight"
SCHEMA_VERSION = 3
DEFAULT_STATE_DIR = Path.home() / ".66tasklight"
DEFAULT_TTL_SECONDS = 300
DEFAULT_REFRESH_SECONDS = 1.0
DEFAULT_VERIFICATION_TTL_SECONDS = 900
DEFAULT_OBSERVATION_MISS_SCANS = 3
TASK_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]*$")
OBSERVATION_PROCESS_RE = re.compile(r"\bcodex\b", re.IGNORECASE)
OBSERVATION_ACTION_RE = re.compile(r"\b(exec|run|chat|shell|resume)\b", re.IGNORECASE)
OBSERVATION_ATTENTION_RE = re.compile(r"\b(waiting|error|failed|blocked|attention)\b", re.IGNORECASE)
OBSERVATION_LINK_RE = re.compile(r"TASKLIGHT_TASK_ID=([A-Za-z0-9_.-]+)")
OBSERVATION_COMMAND_EXCLUDE_SNIPPETS = (
    "tasklight.py observe-local",
    "tasklight.py observations",
    "model_provider=\"openai-memgen\"",
    "chronicle/screen_recording",
    "screen_recording",
    "codex app-server",
    "app-server --listen stdio://",
    "app-server --analytics-default-enabled",
    "node_repl",
    "skycomputeruse",
    "computer use.app",
    "gateway run --replace",
    "hermes gateway",
    "memory server",
    "/applications/codex.app/contents/macos/codex",
    "/applications/codex.app/contents/resources/codex app-server",
    "/applications/codex.app/contents/frameworks/codex framework.framework",
)
OBSERVATION_CWD_EXCLUDE_SNIPPETS = (
    "/applications/codex.app/",
    "/chronicle/",
    "screen_recording",
    "computer use.app",
)
OBSERVATION_PARENT_ALLOW_SNIPPETS = (
    "/applications/codex.app/contents/macos/codex",
    "codex app-server",
    "codex_chronicle",
)
OBSERVATION_ACTIVE_STATUSES = {
    "observed_active",
    "observed_quiet",
    "observed_attention",
}
BLOCKER_REASONS = {
    "dirty_worktree",
    "missing_input",
    "test_failed",
    "acceptance_failed",
    "permission_denied",
    "timeout",
    "stale_state",
    "invalid_json",
    "codex_exit_failed",
    "needs_human_review",
    "hardware_missing",
}
VALID_STATUSES = {
    "queued",
    "running",
    "blocked",
    "done_unverified",
    "done_verified",
    "stale",
    "cancelled",
}
SORT_PRIORITY = {
    "blocked": 0,
    "stale": 1,
    "running": 2,
    "queued": 3,
    "done_verified": 4,
    "done_unverified": 5,
    "cancelled": 6,
    "invalid_json": 7,
}
ACTIVE_STATUSES = {"queued", "running", "done_unverified"}
TERMINAL_STATUSES = {"blocked", "done_verified", "cancelled", "stale"}
SOUND_TYPES = {"blocked", "done_verified"}
STATE_HEALTH_HEALTHY = "healthy"
STATE_HEALTH_CORRUPT = "corrupt_state"
STATE_HEALTH_RECONSTRUCTED = "reconstructed"


class TaskLightError(Exception):
    """Base error for tasklight failures."""


class TaskLightStateError(TaskLightError):
    """Raised when state cannot be read safely."""


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def iso_now() -> str:
    return utc_now().replace(microsecond=0).isoformat().replace("+00:00", "Z")


def parse_iso8601(value: Optional[str]) -> Optional[datetime]:
    if not value:
        return None
    normalized = value.replace("Z", "+00:00")
    try:
        parsed = datetime.fromisoformat(normalized)
    except ValueError as exc:
        raise TaskLightStateError(f"invalid timestamp: {value}") from exc
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def clamp_progress(value: float) -> float:
    if value < 0.0:
        return 0.0
    if value > 1.0:
        return 1.0
    return round(value, 4)


def json_dump(data: Any) -> str:
    return json.dumps(data, ensure_ascii=True, sort_keys=True, indent=2) + "\n"


def json_dump_line(data: Any) -> str:
    return json.dumps(data, ensure_ascii=True, sort_keys=True, separators=(",", ":")) + "\n"


def ensure_directory(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def fsync_directory(directory: Path) -> None:
    try:
        fd = os.open(directory, os.O_DIRECTORY)
    except OSError:
        return
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def slugify(title: str) -> str:
    cleaned = []
    last_hyphen = False
    for char in title.lower().strip():
        if char.isalnum():
            cleaned.append(char)
            last_hyphen = False
        else:
            if not last_hyphen:
                cleaned.append("-")
                last_hyphen = True
    slug = "".join(cleaned).strip("-")
    if not slug:
        slug = "task"
    return slug[:24]


def short_hash(payload: str) -> str:
    return hashlib.sha1(payload.encode("utf-8")).hexdigest()[:8]


def generated_task_id(title: str) -> str:
    stamp = utc_now().strftime("%Y%m%d-%H%M%S")
    slug = slugify(title)
    entropy = secrets.token_hex(8)
    digest = short_hash(f"{stamp}|{title}|{entropy}|{os.getpid()}")
    return f"{stamp}-{slug}-{digest}"


def validate_task_id(task_id: str) -> None:
    if not TASK_ID_RE.match(task_id):
        raise TaskLightError(f"invalid task_id: {task_id}")


@dataclass(slots=True)
class TaskLightConfig:
    state_dir: Path = DEFAULT_STATE_DIR
    state_path: Path = field(init=False)
    tasks_dir: Path = field(init=False)
    current_path: Path = field(init=False)
    thread_bindings_dir: Path = field(init=False)
    observations_dir: Path = field(init=False)
    observations_state_path: Path = field(init=False)
    events_path: Path = field(init=False)
    played_events_path: Path = field(init=False)
    lock_path: Path = field(init=False)
    ttl_seconds: int = DEFAULT_TTL_SECONDS
    refresh_seconds: float = DEFAULT_REFRESH_SECONDS
    verification_ttl_seconds: int = DEFAULT_VERIFICATION_TTL_SECONDS
    blocked_sound_name: str = "Basso"
    done_sound_name: str = "Submarine"
    stale_sound_name: str = "Funk"

    def __post_init__(self) -> None:
        self.state_dir = Path(self.state_dir).expanduser()
        self.state_path = self.state_dir / "state.json"
        self.tasks_dir = self.state_dir / "tasks"
        self.current_path = self.state_dir / "current.json"
        self.thread_bindings_dir = self.state_dir / "thread_bindings"
        self.observations_dir = self.state_dir / "observations"
        self.observations_state_path = self.state_dir / "observations_state.json"
        self.events_path = self.state_dir / "events.jsonl"
        self.played_events_path = self.state_dir / "played_events.json"
        self.lock_path = self.state_dir / ".lock"

    @classmethod
    def from_env(cls) -> "TaskLightConfig":
        state_dir = Path(os.environ.get("TASKLIGHT_STATE_DIR", str(DEFAULT_STATE_DIR)))
        config = cls(
            state_dir=state_dir,
            ttl_seconds=int(os.environ.get("TASKLIGHT_TTL_SECONDS", str(DEFAULT_TTL_SECONDS))),
            refresh_seconds=float(
                os.environ.get("TASKLIGHT_REFRESH_SECONDS", str(DEFAULT_REFRESH_SECONDS))
            ),
            verification_ttl_seconds=int(
                os.environ.get("TASKLIGHT_VERIFICATION_TTL_SECONDS", str(DEFAULT_VERIFICATION_TTL_SECONDS))
            ),
            blocked_sound_name=os.environ.get("TASKLIGHT_BLOCKED_SOUND", "Basso"),
            done_sound_name=os.environ.get("TASKLIGHT_DONE_SOUND", "Submarine"),
            stale_sound_name=os.environ.get("TASKLIGHT_STALE_SOUND", "Funk"),
        )
        explicit_state = os.environ.get("TASKLIGHT_STATE_PATH")
        explicit_tasks = os.environ.get("TASKLIGHT_TASKS_DIR")
        explicit_current = os.environ.get("TASKLIGHT_CURRENT_PATH")
        explicit_thread_bindings = os.environ.get("TASKLIGHT_THREAD_BINDINGS_DIR")
        explicit_observations_dir = os.environ.get("TASKLIGHT_OBSERVATIONS_DIR")
        explicit_observations_state = os.environ.get("TASKLIGHT_OBSERVATIONS_STATE_PATH")
        explicit_events = os.environ.get("TASKLIGHT_EVENTS_PATH")
        explicit_played = os.environ.get("TASKLIGHT_PLAYED_EVENTS_PATH")
        explicit_lock = os.environ.get("TASKLIGHT_LOCK_PATH")
        if explicit_state:
            config.state_path = Path(explicit_state).expanduser()
        if explicit_tasks:
            config.tasks_dir = Path(explicit_tasks).expanduser()
        if explicit_current:
            config.current_path = Path(explicit_current).expanduser()
        if explicit_thread_bindings:
            config.thread_bindings_dir = Path(explicit_thread_bindings).expanduser()
        if explicit_observations_dir:
            config.observations_dir = Path(explicit_observations_dir).expanduser()
        if explicit_observations_state:
            config.observations_state_path = Path(explicit_observations_state).expanduser()
        if explicit_events:
            config.events_path = Path(explicit_events).expanduser()
        if explicit_played:
            config.played_events_path = Path(explicit_played).expanduser()
        if explicit_lock:
            config.lock_path = Path(explicit_lock).expanduser()
        return config


@dataclass(slots=True)
class TaskLightTaskRecord:
    schema_version: int = SCHEMA_VERSION
    task_id: str = ""
    title: str = ""
    slug: str = ""
    status: str = "queued"
    phase: Optional[str] = None
    progress: Optional[float] = None
    reason: Optional[str] = None
    message: Optional[str] = None
    evidence: Optional[str] = None
    summary: Optional[str] = None
    created_at: Optional[str] = None
    started_at: Optional[str] = None
    updated_at: Optional[str] = None
    heartbeat_at: Optional[str] = None
    done_at: Optional[str] = None
    verified_at: Optional[str] = None
    cancelled_at: Optional[str] = None
    ttl_seconds: Optional[int] = None
    source: str = "tasklight"
    last_error: Optional[str] = None
    current_event_id: Optional[str] = None

    def to_dict(self) -> dict[str, Any]:
        return dataclasses.asdict(self)

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "TaskLightTaskRecord":
        allowed = {field.name for field in dataclasses.fields(cls)}
        filtered = {key: data.get(key) for key in allowed if key in data}
        if filtered.get("progress") is not None:
            filtered["progress"] = float(filtered["progress"])
        if filtered.get("ttl_seconds") is not None:
            filtered["ttl_seconds"] = int(filtered["ttl_seconds"])
        if filtered.get("schema_version") is None:
            filtered["schema_version"] = SCHEMA_VERSION
        if filtered.get("source") is None:
            filtered["source"] = "tasklight"
        if filtered.get("slug") in (None, ""):
            task_id = str(filtered.get("task_id") or "")
            if len(task_id.split("-")) >= 4:
                filtered["slug"] = "-".join(task_id.split("-")[2:-1]) or slugify(str(filtered.get("title") or task_id))
            else:
                filtered["slug"] = slugify(str(filtered.get("title") or task_id))
        if filtered.get("title") in (None, ""):
            filtered["title"] = str(filtered.get("task_id") or "")
        return cls(**filtered)

    def effective_status(
        self,
        now: Optional[datetime] = None,
        ttl_seconds: Optional[int] = None,
        verification_ttl_seconds: Optional[int] = None,
    ) -> str:
        if self.status in {"blocked", "stale", "done_verified", "cancelled"}:
            return self.status
        now_dt = now or utc_now()
        if self.status == "done_unverified":
            ttl = verification_ttl_seconds or DEFAULT_VERIFICATION_TTL_SECONDS
            done_time = parse_iso8601(self.done_at or self.updated_at or self.started_at or self.created_at)
            if done_time is None:
                return "stale"
            if now_dt - done_time > timedelta(seconds=ttl):
                return "stale"
            return "done_unverified"
        if self.status != "running":
            return self.status
        ttl = ttl_seconds or self.ttl_seconds or DEFAULT_TTL_SECONDS
        heartbeat = parse_iso8601(self.heartbeat_at or self.updated_at or self.started_at or self.created_at)
        if heartbeat is None:
            return "stale"
        if now_dt - heartbeat > timedelta(seconds=ttl):
            return "stale"
        return "running"

    def alert_fingerprint(self, effective_status: Optional[str] = None) -> str:
        status = effective_status or self.status
        if status == "blocked":
            payload = {
                "status": status,
                "task_id": self.task_id,
                "title": self.title,
                "phase": self.phase,
                "reason": self.reason,
                "message": self.message,
                "evidence": self.evidence,
            }
        elif status == "done_verified":
            payload = {
                "status": status,
                "task_id": self.task_id,
                "title": self.title,
                "summary": self.summary,
            }
        else:
            payload = {
                "status": status,
                "task_id": self.task_id,
                "title": self.title,
            }
        encoded = json.dumps(payload, ensure_ascii=True, sort_keys=True, separators=(",", ":"))
        return hashlib.sha256(encoded.encode("utf-8")).hexdigest()

    @property
    def short_task_id(self) -> str:
        if "-" not in self.task_id:
            return self.task_id[:8]
        return self.task_id.rsplit("-", 1)[-1]

    def is_active(self, effective_status: Optional[str] = None) -> bool:
        status = effective_status or self.status
        return status in ACTIVE_STATUSES

    def with_effective_status(
        self,
        ttl_seconds: int,
        verification_ttl_seconds: int = DEFAULT_VERIFICATION_TTL_SECONDS,
        now: Optional[datetime] = None,
    ) -> "TaskLightTaskRecord":
        effective = self.effective_status(
            now=now,
            ttl_seconds=ttl_seconds,
            verification_ttl_seconds=verification_ttl_seconds,
        )
        if effective == self.status:
            return self
        copy = dataclasses.replace(self, status=effective)
        if effective == "stale":
            copy.last_error = "acceptance gate expired" if self.status == "done_unverified" else "heartbeat expired"
        return copy


@dataclass(slots=True)
class TaskLightTaskSummary:
    schema_version: int = SCHEMA_VERSION
    task_id: str = ""
    short_task_id: str = ""
    title: str = ""
    slug: str = ""
    status: str = "queued"
    raw_status: str = "queued"
    effective_status: str = "queued"
    phase: Optional[str] = None
    progress: Optional[float] = None
    reason: Optional[str] = None
    message: Optional[str] = None
    evidence: Optional[str] = None
    summary: Optional[str] = None
    created_at: Optional[str] = None
    started_at: Optional[str] = None
    updated_at: Optional[str] = None
    heartbeat_at: Optional[str] = None
    done_at: Optional[str] = None
    verified_at: Optional[str] = None
    cancelled_at: Optional[str] = None
    ttl_seconds: Optional[int] = None
    last_error: Optional[str] = None
    file_path: Optional[str] = None
    alert_fingerprint: Optional[str] = None
    sound_type: Optional[str] = None
    is_invalid_json: bool = False
    invalid_json_error: Optional[str] = None

    def to_dict(self) -> dict[str, Any]:
        return dataclasses.asdict(self)

    def live_status(
        self,
        ttl_seconds: int,
        verification_ttl_seconds: int,
        now: Optional[datetime] = None,
    ) -> str:
        if self.is_invalid_json:
            return "invalid_json"
        if self.effective_status == "stale":
            return "stale"
        if self.raw_status == "done_unverified":
            if self.effective_status == "done_unverified":
                done_time = parse_iso8601(self.done_at or self.updated_at or self.started_at or self.created_at)
                if done_time is None:
                    return "stale"
                now_dt = now or utc_now()
                if now_dt - done_time > timedelta(seconds=verification_ttl_seconds):
                    return "stale"
            return self.effective_status
        if self.raw_status != "running":
            return self.effective_status
        heartbeat = parse_iso8601(self.heartbeat_at or self.updated_at or self.started_at or self.created_at)
        if heartbeat is None:
            return "stale"
        now_dt = now or utc_now()
        if now_dt - heartbeat > timedelta(seconds=ttl_seconds):
            return "stale"
        return "running"


@dataclass(slots=True)
class TaskLightCounts:
    blocked: int = 0
    stale: int = 0
    running: int = 0
    queued: int = 0
    done_verified: int = 0
    done_unverified: int = 0
    pending_verify_count: int = 0
    cancelled: int = 0
    invalid_json: int = 0
    active: int = 0
    total: int = 0
    red: int = 0
    blue: int = 0
    green: int = 0
    gray: int = 0


@dataclass(slots=True)
class TaskLightAggregateState:
    schema_version: int = SCHEMA_VERSION
    source: str = "tasklight"
    source_health: str = STATE_HEALTH_HEALTHY
    lamp_status: str = "idle"
    global_status: str = "idle"
    generated_at: str = field(default_factory=iso_now)
    updated_at: str = field(default_factory=iso_now)
    current_task_id: Optional[str] = None
    last_verified_at: Optional[str] = None
    last_event_at: Optional[str] = None
    counts: TaskLightCounts = field(default_factory=TaskLightCounts)
    tasks: list[TaskLightTaskSummary] = field(default_factory=list)
    invalid_tasks: list[TaskLightTaskSummary] = field(default_factory=list)
    compatibility_current: Optional[dict[str, Any]] = None

    def to_dict(self) -> dict[str, Any]:
        data = dataclasses.asdict(self)
        data["counts"] = dataclasses.asdict(self.counts)
        data["tasks"] = [task.to_dict() for task in self.tasks]
        data["invalid_tasks"] = [task.to_dict() for task in self.invalid_tasks]
        return data


@dataclass(slots=True)
class TaskLightObservationRecord:
    schema_version: int = SCHEMA_VERSION
    observation_id: str = ""
    pid: int = 0
    ppid: int = 0
    command: str = ""
    command_short: str = ""
    cwd: Optional[str] = None
    cwd_hash: Optional[str] = None
    title: str = ""
    detected_at: Optional[str] = None
    last_seen_at: Optional[str] = None
    status: str = "observed_quiet"
    confidence: float = 0.0
    managed_task_id: Optional[str] = None
    missed_scans: int = 0
    removed_at: Optional[str] = None
    last_error: Optional[str] = None
    file_path: Optional[str] = None

    def to_dict(self) -> dict[str, Any]:
        return dataclasses.asdict(self)

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "TaskLightObservationRecord":
        allowed = {field.name for field in dataclasses.fields(cls)}
        filtered = {key: data.get(key) for key in allowed if key in data}
        if filtered.get("pid") is not None:
            filtered["pid"] = int(filtered["pid"])
        if filtered.get("ppid") is not None:
            filtered["ppid"] = int(filtered["ppid"])
        if filtered.get("confidence") is not None:
            filtered["confidence"] = float(filtered["confidence"])
        if filtered.get("missed_scans") is not None:
            filtered["missed_scans"] = int(filtered["missed_scans"])
        if filtered.get("schema_version") is None:
            filtered["schema_version"] = SCHEMA_VERSION
        return cls(**filtered)

    @property
    def is_active(self) -> bool:
        return self.status in OBSERVATION_ACTIVE_STATUSES

    @property
    def short_pid(self) -> str:
        return str(self.pid)

    def elapsed_seconds(self, now: Optional[datetime] = None) -> Optional[int]:
        start = parse_iso8601(self.detected_at)
        if start is None:
            return None
        now_dt = now or utc_now()
        return max(0, int((now_dt - start).total_seconds()))


@dataclass(slots=True)
class TaskLightObservationCounts:
    active: int = 0
    quiet: int = 0
    attention: int = 0
    disappeared: int = 0
    linked_managed: int = 0
    total: int = 0


@dataclass(slots=True)
class TaskLightObservationsState:
    schema_version: int = SCHEMA_VERSION
    source: str = "tasklight"
    source_health: str = STATE_HEALTH_HEALTHY
    lamp_status: str = "idle"
    global_status: str = "idle"
    generated_at: str = field(default_factory=iso_now)
    updated_at: str = field(default_factory=iso_now)
    counts: TaskLightObservationCounts = field(default_factory=TaskLightObservationCounts)
    observations: list[TaskLightObservationRecord] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        data = dataclasses.asdict(self)
        data["counts"] = dataclasses.asdict(self.counts)
        data["observations"] = [observation.to_dict() for observation in self.observations]
        return data


@contextmanager
def locked_state(config: TaskLightConfig):
    ensure_directory(config.state_dir)
    with open(config.lock_path, "a+", encoding="utf-8") as handle:
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
        try:
            yield
        finally:
            handle.flush()
            os.fsync(handle.fileno())
            fcntl.flock(handle.fileno(), fcntl.LOCK_UN)


def write_json_atomic(path: Path, data: dict[str, Any]) -> None:
    ensure_directory(path.parent)
    prefix = f".{path.name}."
    with tempfile.NamedTemporaryFile(
        "w",
        delete=False,
        dir=path.parent,
        prefix=prefix,
        suffix=".tmp",
        encoding="utf-8",
    ) as handle:
        handle.write(json_dump(data))
        handle.flush()
        os.fsync(handle.fileno())
        temp_name = Path(handle.name)
    os.replace(temp_name, path)
    fsync_directory(path.parent)


def append_json_line(path: Path, data: dict[str, Any]) -> None:
    ensure_directory(path.parent)
    encoded = json_dump_line(data).encode("utf-8")
    flags = os.O_WRONLY | os.O_APPEND | os.O_CREAT
    fd = os.open(path, flags, 0o600)
    try:
        os.write(fd, encoded)
        os.fsync(fd)
    finally:
        os.close(fd)


def read_json_file(path: Path) -> dict[str, Any]:
    with open(path, "r", encoding="utf-8") as handle:
        data = json.load(handle)
    if not isinstance(data, dict):
        raise TaskLightStateError(f"{path.name} must contain a JSON object")
    return data


def _task_file_path(config: TaskLightConfig, task_id: str) -> Path:
    validate_task_id(task_id)
    return config.tasks_dir / f"{task_id}.json"


def _status_sort_key(summary: TaskLightTaskSummary) -> tuple[int, str, str]:
    return (
        SORT_PRIORITY.get(summary.effective_status, 99),
        summary.updated_at or summary.created_at or "",
        summary.task_id,
    )


def _current_pointer_rank(status: str) -> int:
    if status in {"running", "queued", "done_unverified"}:
        return 0
    if status == "done_verified":
        return 1
    if status in {"blocked", "stale"}:
        return 2
    if status == "cancelled":
        return 3
    return 4


def _pick_current_task_id(summaries: list[TaskLightTaskSummary]) -> Optional[str]:
    if not summaries:
        return None
    ordered = sorted(
        summaries,
        key=lambda summary: (
            _current_pointer_rank(summary.effective_status),
            summary.updated_at or summary.created_at or "",
            summary.task_id,
        ),
    )
    return ordered[0].task_id if ordered else None


def _task_summary_from_record(record: TaskLightTaskRecord, *, config: TaskLightConfig, file_path: Optional[Path] = None, effective_status: Optional[str] = None, invalid_json_error: Optional[str] = None) -> TaskLightTaskSummary:
    effective = effective_status or record.effective_status(
        ttl_seconds=config.ttl_seconds,
        verification_ttl_seconds=config.verification_ttl_seconds,
    )
    last_error = record.last_error
    if effective == "stale":
        last_error = "acceptance gate expired" if record.status == "done_unverified" else "heartbeat expired"
    return TaskLightTaskSummary(
        task_id=record.task_id,
        short_task_id=record.short_task_id,
        title=record.title,
        slug=record.slug,
        status=effective,
        raw_status=record.status,
        effective_status=effective,
        phase=record.phase,
        progress=record.progress,
        reason=record.reason,
        message=record.message,
        evidence=record.evidence,
        summary=record.summary,
        created_at=record.created_at,
        started_at=record.started_at or record.created_at,
        updated_at=record.updated_at,
        heartbeat_at=record.heartbeat_at,
        done_at=record.done_at,
        verified_at=record.verified_at,
        cancelled_at=record.cancelled_at,
        ttl_seconds=record.ttl_seconds,
        last_error=last_error,
        file_path=str(file_path) if file_path else None,
        alert_fingerprint=record.alert_fingerprint(effective_status=effective),
        sound_type="blocked" if effective == "stale" else (effective if effective in SOUND_TYPES else None),
        is_invalid_json=False,
        invalid_json_error=invalid_json_error,
    )


def _invalid_summary(task_id: str, *, file_path: Path, error: str, title: Optional[str] = None) -> TaskLightTaskSummary:
    title = title or task_id
    record = TaskLightTaskRecord(
        task_id=task_id,
        title=title,
        slug=slugify(title),
        status="invalid_json",
        created_at=iso_now(),
        started_at=iso_now(),
        updated_at=iso_now(),
        ttl_seconds=DEFAULT_TTL_SECONDS,
        source="tasklight",
        last_error=error,
    )
    return TaskLightTaskSummary(
        task_id=record.task_id,
        short_task_id=record.short_task_id,
        title=record.title,
        slug=record.slug,
        status="invalid_json",
        raw_status="invalid_json",
        effective_status="invalid_json",
        file_path=str(file_path),
        is_invalid_json=True,
        invalid_json_error=error,
        last_error=error,
    )


def _idle_summary(config: TaskLightConfig) -> TaskLightTaskSummary:
    now = iso_now()
    record = TaskLightTaskRecord(
        task_id="",
        title="Idle",
        slug="idle",
        status="idle",
        created_at=now,
        started_at=now,
        updated_at=now,
        ttl_seconds=config.ttl_seconds,
    )
    return _task_summary_from_record(record, config=config, effective_status="idle")


def _observation_file_path(config: TaskLightConfig, observation_id: str) -> Path:
    return config.observations_dir / f"{observation_id}.json"


def _short_command(command: str, limit: int = 96) -> str:
    compact = " ".join(command.split())
    if len(compact) <= limit:
        return compact
    return compact[: max(0, limit - 1)] + "…"


def _command_basename(command: str) -> str:
    tokens = re.split(r"\s+", command.strip(), maxsplit=1)
    if not tokens or not tokens[0]:
        return ""
    first = tokens[0]
    return Path(first).name if "/" in first else first


def _command_contains_any(command: str, snippets: tuple[str, ...]) -> bool:
    lowered = command.lower()
    return any(snippet in lowered for snippet in snippets)


def _parse_ps_snapshot() -> list[dict[str, Any]]:
    try:
        result = subprocess.run(
            ["/bin/ps", "-axo", "pid=,ppid=,uid=,lstart=,command="],
            check=True,
            capture_output=True,
            text=True,
        )
    except (OSError, subprocess.CalledProcessError):
        return []

    rows: list[dict[str, Any]] = []
    current_uid = os.getuid()
    for raw_line in result.stdout.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        parts = line.split(None, 8)
        if len(parts) < 8:
            continue
        try:
            pid = int(parts[0])
            ppid = int(parts[1])
            uid = int(parts[2])
        except ValueError:
            continue
        if uid != current_uid:
            continue
        lstart = " ".join(parts[3:8])
        command = parts[8] if len(parts) > 8 else ""
        rows.append(
            {
                "pid": pid,
                "ppid": ppid,
                "uid": uid,
                "lstart": lstart,
                "command": command,
            }
        )
    return rows


def _process_cwd(pid: int) -> Optional[str]:
    try:
        result = subprocess.run(
            ["/usr/sbin/lsof", "-p", str(pid), "-a", "-d", "cwd", "-Fn"],
            check=True,
            capture_output=True,
            text=True,
        )
    except (OSError, subprocess.CalledProcessError):
        return None
    for line in result.stdout.splitlines():
        if line.startswith("n"):
            value = line[1:].strip()
            return value or None
    return None


def _observation_parent_chain(sample: dict[str, Any], live_by_pid: dict[int, dict[str, Any]]) -> list[dict[str, Any]]:
    chain: list[dict[str, Any]] = []
    seen: set[int] = set()
    current_pid = int(sample.get("ppid") or 0)
    while current_pid > 0 and current_pid not in seen:
        parent = live_by_pid.get(current_pid)
        if parent is None:
            break
        chain.append(parent)
        seen.add(current_pid)
        current_pid = int(parent.get("ppid") or 0)
    return chain


def _is_observation_parent_allowed(parent_chain: list[dict[str, Any]]) -> bool:
    for parent in parent_chain:
        command = str(parent.get("command") or "")
        if _command_contains_any(command, OBSERVATION_PARENT_ALLOW_SNIPPETS):
            return True
    return False


def _observation_title(command: str, cwd: Optional[str]) -> str:
    if cwd:
        name = Path(cwd).name
        if name:
            return name
    command_short = _short_command(command)
    if command_short:
        return command_short.split()[0]
    return "Observed thread"


def _observation_confidence(
    command: str,
    cwd: Optional[str],
    attention: bool,
    *,
    parent_chain: Optional[list[dict[str, Any]]] = None,
) -> float:
    score = 0.72
    if cwd:
        score += 0.08
    if parent_chain and _is_observation_parent_allowed(parent_chain):
        score += 0.08
    if _command_contains_any(command, OBSERVATION_COMMAND_EXCLUDE_SNIPPETS):
        score -= 0.45
    if cwd and _command_contains_any(cwd, OBSERVATION_CWD_EXCLUDE_SNIPPETS):
        score -= 0.25
    if attention:
        score = min(score, 0.48)
    return max(0.05, min(0.95, round(score, 2)))


def _observation_status(command: str, confidence: float) -> str:
    if OBSERVATION_ATTENTION_RE.search(command):
        return "observed_attention"
    if confidence >= 0.72:
        return "observed_active"
    return "observed_quiet"


def _observation_id(pid: int, lstart: str, cwd: Optional[str]) -> str:
    cwd_hash = short_hash(cwd or "")
    start_hash = short_hash(lstart)
    return f"{pid}-{start_hash}-{cwd_hash}"


def _linked_managed_task_id(command: str) -> Optional[str]:
    match = OBSERVATION_LINK_RE.search(command)
    if match:
        return match.group(1)
    return None


def _matches_observed_process(
    sample: dict[str, Any],
    live_by_pid: dict[int, dict[str, Any]],
    *,
    cwd: Optional[str] = None,
) -> bool:
    command = str(sample.get("command") or "")
    if not command:
        return False
    if _command_contains_any(command, OBSERVATION_COMMAND_EXCLUDE_SNIPPETS):
        return False
    if OBSERVATION_LINK_RE.search(command):
        return True
    if _command_basename(command).lower() != "codex":
        return False
    if not OBSERVATION_ACTION_RE.search(command):
        return False
    cwd = cwd if cwd is not None else _process_cwd(int(sample["pid"]))
    if cwd and _command_contains_any(cwd, OBSERVATION_CWD_EXCLUDE_SNIPPETS):
        return False
    parent_chain = _observation_parent_chain(sample, live_by_pid)
    if not _is_observation_parent_allowed(parent_chain):
        return False
    if OBSERVATION_LINK_RE.search(command):
        return True
    return bool(OBSERVATION_PROCESS_RE.search(command))


class TaskLightStore:
    def __init__(self, config: TaskLightConfig):
        self.config = config

    def ensure_layout(self) -> None:
        ensure_directory(self.config.state_dir)
        ensure_directory(self.config.tasks_dir)
        ensure_directory(self.config.thread_bindings_dir)
        ensure_directory(self.config.observations_dir)
        if not self.config.played_events_path.exists():
            write_json_atomic(
                self.config.played_events_path,
                {
                    "schema_version": SCHEMA_VERSION,
                    "muted": False,
                    "played_event_ids": [],
                    "sound_windows": {
                        "blocked": {"last_played_at": None, "last_event_id": None},
                        "done_verified": {"last_played_at": None, "last_event_id": None},
                    },
                    "updated_at": iso_now(),
                },
            )
        if not self.config.observations_state_path.exists():
            write_json_atomic(
                self.config.observations_state_path,
                self._empty_observations_state(source_health=STATE_HEALTH_RECONSTRUCTED).to_dict(),
            )

    def _load_task_file(self, path: Path) -> tuple[Optional[TaskLightTaskRecord], Optional[str]]:
        try:
            data = read_json_file(path)
            return TaskLightTaskRecord.from_dict(data), None
        except (OSError, json.JSONDecodeError, TaskLightStateError, TypeError, ValueError) as exc:
            return None, str(exc)

    def _load_current_mirror(self) -> Optional[TaskLightTaskRecord]:
        if not self.config.current_path.exists():
            return None
        try:
            data = read_json_file(self.config.current_path)
            record = TaskLightTaskRecord.from_dict(data)
        except (OSError, json.JSONDecodeError, TaskLightStateError, TypeError, ValueError):
            return None
        if record.task_id or record.status != "idle":
            return record
        return None

    def _load_observation_file(self, path: Path) -> tuple[Optional[TaskLightObservationRecord], Optional[str]]:
        try:
            data = read_json_file(path)
            return TaskLightObservationRecord.from_dict(data), None
        except (OSError, json.JSONDecodeError, TaskLightStateError, TypeError, ValueError) as exc:
            return None, str(exc)

    def _empty_observations_state(self, *, source_health: str) -> TaskLightObservationsState:
        return TaskLightObservationsState(
            source_health=source_health,
            lamp_status="idle" if source_health != STATE_HEALTH_CORRUPT else "stale",
            global_status="idle",
            counts=TaskLightObservationCounts(),
            observations=[],
        )

    def _observations_state_from_dict(self, data: dict[str, Any]) -> TaskLightObservationsState:
        counts_data = data.get("counts", {})
        counts = TaskLightObservationCounts(
            active=int(counts_data.get("active", 0)),
            quiet=int(counts_data.get("quiet", 0)),
            attention=int(counts_data.get("attention", 0)),
            disappeared=int(counts_data.get("disappeared", 0)),
            linked_managed=int(counts_data.get("linked_managed", 0)),
            total=int(counts_data.get("total", 0)),
        )
        observations = [
            TaskLightObservationRecord.from_dict(item)
            for item in data.get("observations", [])
            if isinstance(item, dict)
        ]
        state = TaskLightObservationsState(
            schema_version=int(data.get("schema_version", SCHEMA_VERSION)),
            source=str(data.get("source", "tasklight")),
            source_health=str(data.get("source_health", STATE_HEALTH_HEALTHY)),
            lamp_status=str(data.get("lamp_status", data.get("global_status", "idle"))),
            global_status=str(data.get("global_status", "idle")),
            generated_at=str(data.get("generated_at") or iso_now()),
            updated_at=str(data.get("updated_at") or iso_now()),
            counts=counts,
            observations=observations,
        )
        if state.source_health == STATE_HEALTH_CORRUPT:
            state.lamp_status = "stale"
        return state

    def load_observations_state(self) -> TaskLightObservationsState:
        state_data: Optional[dict[str, Any]] = None
        state_parse_health = STATE_HEALTH_RECONSTRUCTED
        try:
            state_data = read_json_file(self.config.observations_state_path)
            state_parse_health = STATE_HEALTH_HEALTHY
        except FileNotFoundError:
            state_parse_health = STATE_HEALTH_RECONSTRUCTED
        except (OSError, json.JSONDecodeError, TaskLightStateError, TypeError, ValueError):
            state_parse_health = STATE_HEALTH_CORRUPT

        observations = self._scan_observation_files()
        if observations:
            state = self._build_observations_state(observations, source_health=state_parse_health)
            if state_parse_health == STATE_HEALTH_CORRUPT:
                state.lamp_status = "stale"
            return state

        if state_data is not None:
            state = self._observations_state_from_dict(state_data)
            state.source_health = state_parse_health
            if state.source_health == STATE_HEALTH_CORRUPT:
                state.lamp_status = "stale"
            return state

        state = self._empty_observations_state(source_health=state_parse_health)
        if state_parse_health == STATE_HEALTH_CORRUPT:
            state.lamp_status = "stale"
        return state

    def _scan_task_files(self) -> tuple[list[TaskLightTaskSummary], list[TaskLightTaskSummary], list[TaskLightTaskRecord]]:
        valid: list[TaskLightTaskSummary] = []
        invalid: list[TaskLightTaskSummary] = []
        raw_records: list[TaskLightTaskRecord] = []
        if not self.config.tasks_dir.exists():
            return valid, invalid, raw_records
        for path in sorted(self.config.tasks_dir.glob("*.json")):
            task_id = path.stem
            record, error = self._load_task_file(path)
            if record is None:
                invalid.append(_invalid_summary(task_id, file_path=path, error=error or "invalid_json"))
                continue
            raw_records.append(record)
            summary = _task_summary_from_record(record, config=self.config, file_path=path)
            valid.append(summary)
        return valid, invalid, raw_records

    def _scan_observation_files(self) -> list[TaskLightObservationRecord]:
        records: list[TaskLightObservationRecord] = []
        if not self.config.observations_dir.exists():
            return records
        for path in sorted(self.config.observations_dir.glob("*.json")):
            record, error = self._load_observation_file(path)
            if record is None:
                record = TaskLightObservationRecord(
                    observation_id=path.stem,
                    pid=0,
                    ppid=0,
                    command="",
                    command_short="",
                    cwd=None,
                    cwd_hash=None,
                    title=path.stem,
                    detected_at=iso_now(),
                    last_seen_at=iso_now(),
                    status="observed_disappeared",
                    confidence=0.0,
                    managed_task_id=None,
                    missed_scans=0,
                    removed_at=iso_now(),
                    last_error=error or "invalid_json",
                    file_path=str(path),
                )
            if not record.file_path:
                record.file_path = str(path)
            records.append(record)
        return records

    def _build_observations_state(self, records: list[TaskLightObservationRecord], *, source_health: str) -> TaskLightObservationsState:
        active_records: list[TaskLightObservationRecord] = []
        counts = TaskLightObservationCounts()
        latest_seen: Optional[str] = None
        lamp = "idle"
        for record in sorted(records, key=lambda item: (item.status, item.last_seen_at or item.detected_at or "", item.observation_id)):
            counts.total += 1
            if record.managed_task_id:
                counts.linked_managed += 1
                continue
            if record.status == "observed_disappeared":
                counts.disappeared += 1
                continue
            counts.active += 1
            if record.status == "observed_attention":
                counts.attention += 1
                active_records.append(record)
                if record.confidence >= 0.75:
                    lamp = "blocked"
            elif record.status == "observed_active":
                active_records.append(record)
                if lamp != "blocked":
                    lamp = "running"
            elif record.status == "observed_quiet":
                counts.quiet += 1
                active_records.append(record)
                if lamp not in {"blocked", "running"}:
                    lamp = "running"
            else:
                counts.quiet += 1
                active_records.append(record)
                if lamp not in {"blocked", "running"}:
                    lamp = "running"
            if record.last_seen_at and (latest_seen is None or record.last_seen_at > latest_seen):
                latest_seen = record.last_seen_at

        global_status = lamp if active_records else "idle"
        if counts.attention > 0:
            lamp_status = "blocked" if any(r.confidence >= 0.75 for r in active_records if r.status == "observed_attention") else global_status
        else:
            lamp_status = global_status
        if source_health == STATE_HEALTH_CORRUPT:
            lamp_status = "stale"

        return TaskLightObservationsState(
            source_health=source_health,
            lamp_status=lamp_status,
            global_status=global_status,
            generated_at=iso_now(),
            updated_at=iso_now(),
            counts=counts,
            observations=sorted(
                active_records,
                key=lambda item: (
                    0 if item.status == "observed_attention" else 1 if item.status == "observed_active" else 2,
                    -(item.confidence * 1000),
                    item.last_seen_at or item.detected_at or "",
                    item.observation_id,
                ),
            ),
        )

    def _save_observation_record(self, record: TaskLightObservationRecord) -> None:
        path = _observation_file_path(self.config, record.observation_id)
        record.file_path = str(path)
        write_json_atomic(path, record.to_dict())

    def _remove_stale_observation_files(self, keep_ids: set[str]) -> None:
        if not self.config.observations_dir.exists():
            return
        for path in self.config.observations_dir.glob("*.json"):
            if path.stem not in keep_ids:
                try:
                    path.unlink()
                except OSError:
                    continue

    def _persist_observations_state(self, state: TaskLightObservationsState) -> TaskLightObservationsState:
        write_json_atomic(self.config.observations_state_path, state.to_dict())
        return state

    def rebuild_observations_state(self, *, scan_processes: bool = True) -> TaskLightObservationsState:
        with locked_state(self.config):
            existing_records = {record.observation_id: record for record in self._scan_observation_files()}
            live_samples = _parse_ps_snapshot() if scan_processes else []
            live_by_pid = {int(sample["pid"]): sample for sample in live_samples}
            live_by_id: dict[str, TaskLightObservationRecord] = {}
            seen_ids: set[str] = set()
            now = iso_now()

            for sample in live_samples:
                command = sample["command"]
                cwd = _process_cwd(sample["pid"])
                if not _matches_observed_process(sample, live_by_pid, cwd=cwd):
                    continue
                managed_task_id = _linked_managed_task_id(command)
                if managed_task_id:
                    continue
                parent_chain = _observation_parent_chain(sample, live_by_pid)
                attention = bool(OBSERVATION_ATTENTION_RE.search(command))
                confidence = _observation_confidence(command, cwd, attention, parent_chain=parent_chain)
                status = _observation_status(command, confidence)
                observation_id = _observation_id(sample["pid"], sample["lstart"], cwd)
                record = TaskLightObservationRecord(
                    observation_id=observation_id,
                    pid=int(sample["pid"]),
                    ppid=int(sample["ppid"]),
                    command=command,
                    command_short=_short_command(command),
                    cwd=cwd,
                    cwd_hash=short_hash(cwd or ""),
                    title=_observation_title(command, cwd),
                    detected_at=existing_records.get(observation_id).detected_at if observation_id in existing_records else now,
                    last_seen_at=now,
                    status=status,
                    confidence=confidence,
                    managed_task_id=None,
                    missed_scans=0,
                    removed_at=None,
                    last_error=None,
                    file_path=str(_observation_file_path(self.config, observation_id)),
                )
                live_by_id[observation_id] = record
                seen_ids.add(observation_id)

            for observation_id, record in existing_records.items():
                if observation_id in seen_ids:
                    continue
                if record.status == "observed_disappeared":
                    live_by_id[observation_id] = record
                    continue
                record.missed_scans = int(record.missed_scans or 0) + 1
                if record.missed_scans >= DEFAULT_OBSERVATION_MISS_SCANS:
                    record.status = "observed_disappeared"
                    record.removed_at = record.removed_at or now
                    record.last_seen_at = record.last_seen_at or now
                live_by_id[observation_id] = record

            for record in live_by_id.values():
                self._save_observation_record(record)

            active_records = [record for record in live_by_id.values() if record.is_active and record.managed_task_id is None]
            state = self._build_observations_state(list(live_by_id.values()), source_health=STATE_HEALTH_HEALTHY)
            self._persist_observations_state(state)
            return state

    def observe_local(self, watch: bool = False) -> TaskLightObservationsState:
        state = self.rebuild_observations_state(scan_processes=True)
        if not watch:
            return state
        try:
            while True:
                time.sleep(self.config.refresh_seconds)
                state = self.rebuild_observations_state(scan_processes=True)
        except KeyboardInterrupt:
            return state

    def list_observations(self) -> TaskLightObservationsState:
        return self.rebuild_observations_state(scan_processes=True)

    def clear_observations(self) -> TaskLightObservationsState:
        with locked_state(self.config):
            if self.config.observations_dir.exists():
                for path in self.config.observations_dir.glob("*.json"):
                    try:
                        path.unlink()
                    except OSError:
                        continue
            try:
                self.config.observations_state_path.unlink()
            except OSError:
                pass
            state = self._empty_observations_state(source_health=STATE_HEALTH_RECONSTRUCTED)
            write_json_atomic(self.config.observations_state_path, state.to_dict())
            return state

    def load_state(self) -> TaskLightAggregateState:
        state_data: Optional[dict[str, Any]] = None
        state_parse_health = STATE_HEALTH_RECONSTRUCTED
        try:
            state_data = read_json_file(self.config.state_path)
            state_parse_health = STATE_HEALTH_HEALTHY
        except FileNotFoundError:
            state_parse_health = STATE_HEALTH_RECONSTRUCTED
        except (OSError, json.JSONDecodeError, TaskLightStateError, TypeError, ValueError):
            state_parse_health = STATE_HEALTH_CORRUPT

        valid, invalid, raw_records = self._scan_task_files()
        if valid or invalid:
            state = self._build_state(valid, invalid, raw_records, source_health=state_parse_health)
            if state_parse_health == STATE_HEALTH_CORRUPT:
                state.lamp_status = "stale"
            return self._refresh_state_view(state)

        if state_data is not None:
            state = self._state_from_dict(state_data)
            state.source_health = state_parse_health
            if state.source_health == STATE_HEALTH_CORRUPT:
                state.lamp_status = "stale"
            return self._refresh_state_view(state)

        mirror = self._load_current_mirror()
        if mirror is None:
            state = self._empty_state(source_health=state_parse_health)
            if state_parse_health == STATE_HEALTH_CORRUPT:
                state.lamp_status = "stale"
            return state
        state = self._state_from_legacy_record(mirror, source_health=state_parse_health)
        if state.source_health == STATE_HEALTH_CORRUPT:
            state.lamp_status = "stale"
        return self._refresh_state_view(state)

    def load_task(self, task_id: str) -> TaskLightTaskSummary:
        validate_task_id(task_id)
        path = _task_file_path(self.config, task_id)
        if not path.exists():
            raise TaskLightStateError(f"task not found: {task_id}")
        record, error = self._load_task_file(path)
        if record is None:
            return _invalid_summary(task_id, file_path=path, error=error or "invalid_json")
        return _task_summary_from_record(record, config=self.config, file_path=path)

    def list_tasks(self) -> TaskLightAggregateState:
        return self.load_state()

    def show_task(self, task_id: str) -> dict[str, Any]:
        summary = self.load_task(task_id)
        return summary.to_dict()

    def _empty_state(self, *, source_health: str) -> TaskLightAggregateState:
        counts = TaskLightCounts(gray=1)
        return TaskLightAggregateState(
            source_health=source_health,
            lamp_status="idle" if source_health != STATE_HEALTH_CORRUPT else "stale",
            global_status="idle",
            counts=counts,
            tasks=[],
            invalid_tasks=[],
            compatibility_current=None,
        )

    def _state_from_legacy_record(self, record: TaskLightTaskRecord, *, source_health: str) -> TaskLightAggregateState:
        if not record.task_id:
            return self._empty_state(source_health=source_health)
        summary = _task_summary_from_record(record, config=self.config)
        return self._build_state([summary], [], [record], source_health=source_health)

    def _state_from_dict(self, data: dict[str, Any]) -> TaskLightAggregateState:
        tasks = [self._summary_from_dict(item) for item in data.get("tasks", []) if isinstance(item, dict)]
        invalid_tasks = [self._summary_from_dict(item, force_invalid=True) for item in data.get("invalid_tasks", []) if isinstance(item, dict)]
        counts_data = data.get("counts", {})
        counts = TaskLightCounts(
            blocked=int(counts_data.get("blocked", 0)),
            stale=int(counts_data.get("stale", 0)),
            running=int(counts_data.get("running", 0)),
            queued=int(counts_data.get("queued", 0)),
            done_verified=int(counts_data.get("done_verified", 0)),
            done_unverified=int(counts_data.get("done_unverified", 0)),
            pending_verify_count=int(counts_data.get("pending_verify_count", 0)),
            cancelled=int(counts_data.get("cancelled", 0)),
            invalid_json=int(counts_data.get("invalid_json", 0)),
            active=int(counts_data.get("active", 0)),
            total=int(counts_data.get("total", 0)),
            red=int(counts_data.get("red", 0)),
            blue=int(counts_data.get("blue", 0)),
            green=int(counts_data.get("green", 0)),
            gray=int(counts_data.get("gray", 0)),
        )
        state = TaskLightAggregateState(
            schema_version=int(data.get("schema_version", SCHEMA_VERSION)),
            source=str(data.get("source", "tasklight")),
            source_health=str(data.get("source_health", STATE_HEALTH_HEALTHY)),
            lamp_status=str(data.get("lamp_status", data.get("global_status", "idle"))),
            global_status=str(data.get("global_status", "idle")),
            generated_at=str(data.get("generated_at") or iso_now()),
            updated_at=str(data.get("updated_at") or iso_now()),
            current_task_id=data.get("current_task_id"),
            last_verified_at=data.get("last_verified_at"),
            last_event_at=data.get("last_event_at"),
            counts=counts,
            tasks=tasks,
            invalid_tasks=invalid_tasks,
            compatibility_current=data.get("compatibility_current"),
        )
        if state.source_health == STATE_HEALTH_CORRUPT:
            state.lamp_status = "stale"
        return state

    def _summary_from_dict(self, data: dict[str, Any], *, force_invalid: bool = False) -> TaskLightTaskSummary:
        return TaskLightTaskSummary(
            schema_version=int(data.get("schema_version", SCHEMA_VERSION)),
            task_id=str(data.get("task_id", "")),
            short_task_id=str(data.get("short_task_id", data.get("task_id", "")).rsplit("-", 1)[-1]),
            title=str(data.get("title", "")),
            slug=str(data.get("slug", "")),
            status=str(data.get("status", data.get("effective_status", "idle"))),
            raw_status=str(data.get("raw_status", data.get("status", "idle"))),
            effective_status=str(data.get("effective_status", data.get("status", "idle"))),
            phase=data.get("phase"),
            progress=float(data["progress"]) if data.get("progress") is not None else None,
            reason=data.get("reason"),
            message=data.get("message"),
            evidence=data.get("evidence"),
            summary=data.get("summary"),
            created_at=data.get("created_at"),
            started_at=data.get("started_at"),
            updated_at=data.get("updated_at"),
            heartbeat_at=data.get("heartbeat_at"),
            done_at=data.get("done_at"),
            verified_at=data.get("verified_at"),
            cancelled_at=data.get("cancelled_at"),
            ttl_seconds=int(data["ttl_seconds"]) if data.get("ttl_seconds") is not None else None,
            last_error=data.get("last_error"),
            file_path=data.get("file_path"),
            alert_fingerprint=data.get("alert_fingerprint"),
            sound_type=data.get("sound_type"),
            is_invalid_json=force_invalid or bool(data.get("is_invalid_json", False)),
            invalid_json_error=data.get("invalid_json_error"),
        )

    def _build_state(
        self,
        valid_summaries: list[TaskLightTaskSummary],
        invalid_summaries: list[TaskLightTaskSummary],
        raw_records: list[TaskLightTaskRecord],
        *,
        source_health: str,
    ) -> TaskLightAggregateState:
        now = utc_now()
        ordered_valid = sorted(valid_summaries, key=_status_sort_key)
        ordered_invalid = sorted(invalid_summaries, key=lambda item: (item.title or item.task_id, item.task_id))
        counts = TaskLightCounts()
        latest_verified: Optional[str] = None
        latest_event: Optional[str] = None
        current_task_id: Optional[str] = _pick_current_task_id(ordered_valid)

        for summary in ordered_valid:
            counts.total += 1
            counts.invalid_json += 0
            status = summary.effective_status
            if status == "blocked":
                counts.blocked += 1
                counts.red += 1
            elif status == "stale":
                counts.stale += 1
                counts.red += 1
            elif status == "running":
                counts.running += 1
                counts.blue += 1
            elif status == "queued":
                counts.queued += 1
                counts.blue += 1
            elif status == "done_verified":
                counts.done_verified += 1
                counts.green += 1
            elif status == "done_unverified":
                counts.done_unverified += 1
                counts.pending_verify_count += 1
                counts.blue += 1
            elif status == "cancelled":
                counts.cancelled += 1

            if status == "done_verified" and summary.verified_at:
                if latest_verified is None or (summary.verified_at > latest_verified):
                    latest_verified = summary.verified_at
            if summary.updated_at and (latest_event is None or summary.updated_at > latest_event):
                latest_event = summary.updated_at

        counts.invalid_json = len(ordered_invalid)
        counts.total += len(ordered_invalid)
        if not ordered_valid and not ordered_invalid:
            counts.gray = 1
        elif counts.red == 0 and counts.blue == 0 and counts.green == 0:
            counts.gray = 1
        else:
            counts.gray = 0
        counts.active = counts.running + counts.queued + counts.done_unverified

        if counts.red > 0:
            global_status = "blocked"
        elif counts.blue > 0:
            global_status = "running"
        elif counts.green > 0 and counts.active == 0 and counts.blocked == 0 and counts.stale == 0:
            global_status = "done_verified"
        else:
            global_status = "idle"

        lamp_status = "stale" if source_health == STATE_HEALTH_CORRUPT else global_status
        compatibility_current = None
        if current_task_id:
            for summary in ordered_valid:
                if summary.task_id == current_task_id:
                    compatibility_current = summary.to_dict()
                    break
        return TaskLightAggregateState(
            source_health=source_health,
            lamp_status=lamp_status,
            global_status=global_status,
            generated_at=iso_now(),
            updated_at=iso_now(),
            current_task_id=current_task_id,
            last_verified_at=latest_verified,
            last_event_at=latest_event,
            counts=counts,
            tasks=ordered_valid,
            invalid_tasks=ordered_invalid,
            compatibility_current=compatibility_current,
        )

    def _refresh_state_view(self, state: TaskLightAggregateState) -> TaskLightAggregateState:
        now = utc_now()
        refreshed_tasks: list[TaskLightTaskSummary] = []
        refreshed_invalid: list[TaskLightTaskSummary] = []
        counts = TaskLightCounts()
        latest_verified: Optional[str] = state.last_verified_at
        latest_event: Optional[str] = state.last_event_at
        current_task_id: Optional[str] = _pick_current_task_id(state.tasks)

        for summary in state.tasks:
            live_status = summary.live_status(
                self.config.ttl_seconds,
                self.config.verification_ttl_seconds,
                now=now,
            )
            if live_status != summary.status:
                summary = dataclasses.replace(
                    summary,
                    status=live_status,
                    effective_status=live_status,
                    sound_type="blocked" if live_status == "stale" else (live_status if live_status in SOUND_TYPES else None),
                    last_error=(
                        "acceptance gate expired"
                        if live_status == "stale" and summary.raw_status == "done_unverified"
                        else ("heartbeat expired" if live_status == "stale" else summary.last_error)
                    ),
                )
            refreshed_tasks.append(summary)
            counts.total += 1
            if live_status == "blocked":
                counts.blocked += 1
                counts.red += 1
            elif live_status == "stale":
                counts.stale += 1
                counts.red += 1
            elif live_status == "running":
                counts.running += 1
                counts.blue += 1
            elif live_status == "queued":
                counts.queued += 1
                counts.blue += 1
            elif live_status == "done_verified":
                counts.done_verified += 1
                counts.green += 1
                if summary.verified_at and (latest_verified is None or summary.verified_at > latest_verified):
                    latest_verified = summary.verified_at
            elif live_status == "done_unverified":
                counts.done_unverified += 1
                counts.pending_verify_count += 1
                counts.blue += 1
            elif live_status == "cancelled":
                counts.cancelled += 1
            if summary.updated_at and (latest_event is None or summary.updated_at > latest_event):
                latest_event = summary.updated_at

        refreshed_invalid.extend(state.invalid_tasks)
        counts.invalid_json = len(refreshed_invalid)
        counts.total += len(refreshed_invalid)
        counts.active = counts.running + counts.queued + counts.done_unverified
        if counts.red == 0 and counts.blue == 0 and counts.green == 0:
            counts.gray = 1

        if counts.red > 0:
            global_status = "blocked"
        elif counts.blue > 0:
            global_status = "running"
        elif counts.green > 0 and counts.active == 0 and counts.blocked == 0 and counts.stale == 0:
            global_status = "done_verified"
        else:
            global_status = "idle"

        lamp_status = "stale" if state.source_health == STATE_HEALTH_CORRUPT else global_status
        compatibility_current = state.compatibility_current
        if current_task_id:
            for summary in refreshed_tasks:
                if summary.task_id == current_task_id:
                    compatibility_current = summary.to_dict()
                    break
        return TaskLightAggregateState(
            schema_version=state.schema_version,
            source=state.source,
            source_health=state.source_health,
            lamp_status=lamp_status,
            global_status=global_status,
            generated_at=state.generated_at,
            updated_at=iso_now(),
            current_task_id=current_task_id,
            last_verified_at=latest_verified,
            last_event_at=latest_event,
            counts=counts,
            tasks=sorted(refreshed_tasks, key=_status_sort_key),
            invalid_tasks=sorted(refreshed_invalid, key=lambda item: (item.title or item.task_id, item.task_id)),
            compatibility_current=compatibility_current,
        )

    def _load_or_placeholder(self, task_id: str) -> tuple[Optional[TaskLightTaskRecord], Optional[TaskLightTaskSummary], bool]:
        path = _task_file_path(self.config, task_id)
        if not path.exists():
            placeholder = TaskLightTaskRecord(
                task_id=task_id,
                title=task_id,
                slug=slugify(task_id),
                status="blocked",
                phase="missing",
                progress=0.0,
                reason="missing_input",
                message="task record not found",
                evidence=f"task_id={task_id}",
                created_at=iso_now(),
                started_at=iso_now(),
                updated_at=iso_now(),
                heartbeat_at=iso_now(),
                ttl_seconds=self.config.ttl_seconds,
                last_error="task file missing",
            )
            return placeholder, _task_summary_from_record(placeholder, config=self.config, file_path=path), True
        record, error = self._load_task_file(path)
        if record is None:
            summary = _invalid_summary(task_id, file_path=path, error=error or "invalid_json")
            return None, summary, False
        return record, _task_summary_from_record(record, config=self.config, file_path=path), False

    def _persist_task_and_state(
        self,
        record: TaskLightTaskRecord,
        *,
        event_name: str,
        previous_status: str,
        sound_type: Optional[str],
        details: dict[str, Any],
        write_current: bool = True,
        extra_invalid: Optional[TaskLightTaskSummary] = None,
    ) -> tuple[TaskLightTaskRecord, TaskLightAggregateState]:
        task_path = _task_file_path(self.config, record.task_id)
        write_json_atomic(task_path, record.to_dict())
        if write_current:
            write_json_atomic(self.config.current_path, record.to_dict())
        append_json_line(
            self.config.events_path,
            {
                "schema_version": SCHEMA_VERSION,
                "event_id": secrets.token_hex(16),
                "task_id": record.task_id,
                "from": previous_status,
                "to": record.status,
                "created_at": record.updated_at or iso_now(),
                "sound_type": sound_type or "none",
                **details,
            },
        )
        state = self.rebuild_state(extra_invalid=extra_invalid)
        write_json_atomic(self.config.state_path, state.to_dict())
        return record, state

    def rebuild_state(self, extra_invalid: Optional[TaskLightTaskSummary] = None) -> TaskLightAggregateState:
        valid, invalid, raw_records = self._scan_task_files()
        if extra_invalid is not None:
            invalid.append(extra_invalid)
        state = self._build_state(valid, invalid, raw_records, source_health=STATE_HEALTH_HEALTHY)
        return state

    def start_task(self, title: str) -> tuple[TaskLightTaskRecord, TaskLightAggregateState]:
        now = iso_now()
        attempt = 0
        while True:
            task_id = generated_task_id(title)
            task_path = _task_file_path(self.config, task_id)
            if not task_path.exists():
                break
            attempt += 1
            if attempt > 8:
                raise TaskLightStateError("unable to generate unique task_id")
        record = TaskLightTaskRecord(
            task_id=task_id,
            title=title,
            slug=slugify(title),
            status="running",
            phase="start",
            progress=0.0,
            created_at=now,
            started_at=now,
            updated_at=now,
            heartbeat_at=now,
            ttl_seconds=self.config.ttl_seconds,
        )
        return self._persist_task_and_state(
            record,
            event_name="start",
            previous_status="idle",
            sound_type=None,
            details={"title": title},
        )

    def heartbeat_task(self, task_id: str, phase: str, progress: float) -> tuple[TaskLightTaskRecord | TaskLightTaskSummary, TaskLightAggregateState]:
        validate_task_id(task_id)
        with locked_state(self.config):
            record, summary, missing = self._load_or_placeholder(task_id)
            if summary is None:
                return self._persist_synthetic_invalid(task_id, "heartbeat", "invalid_json", "task record unreadable")
            if record is None:
                return self._persist_task_and_state(
                    TaskLightTaskRecord(
                        task_id=task_id,
                        title=task_id,
                        slug=slugify(task_id),
                        status="blocked",
                        phase=phase,
                        progress=clamp_progress(progress),
                        reason="missing_input",
                        message="task record not found",
                        evidence=f"task_id={task_id}",
                        created_at=iso_now(),
                        started_at=iso_now(),
                        updated_at=iso_now(),
                        heartbeat_at=iso_now(),
                        ttl_seconds=self.config.ttl_seconds,
                    ),
                    event_name="heartbeat",
                    previous_status="missing",
                    sound_type="blocked",
                    details={"phase": phase, "progress": clamp_progress(progress), "reason": "missing_input"},
                    extra_invalid=None,
                )
            effective = record.effective_status(
                ttl_seconds=self.config.ttl_seconds,
                verification_ttl_seconds=self.config.verification_ttl_seconds,
            )
            if effective not in {"running", "stale", "queued"}:
                blocked = self._blocked_from_record(
                    record,
                    reason="needs_human_review",
                    message="heartbeat received in a terminal state",
                    evidence=f"task status={effective}",
                )
                return self._persist_task_and_state(
                    blocked,
                    event_name="heartbeat",
                    previous_status=effective,
                    sound_type="blocked",
                    details={"phase": phase, "progress": clamp_progress(progress), "reason": "needs_human_review"},
                )
            timestamp = iso_now()
            record.status = "running"
            record.phase = phase
            record.progress = clamp_progress(progress)
            record.updated_at = timestamp
            record.heartbeat_at = timestamp
            record.last_error = None
            record.current_event_id = secrets.token_hex(16)
            return self._persist_task_and_state(
                record,
                event_name="heartbeat",
                previous_status=effective,
                sound_type=None,
                details={"phase": phase, "progress": record.progress},
            )

    def _blocked_from_record(self, record: TaskLightTaskRecord, *, reason: str, message: str, evidence: str) -> TaskLightTaskRecord:
        timestamp = iso_now()
        return TaskLightTaskRecord(
            task_id=record.task_id,
            title=record.title,
            slug=record.slug,
            status="blocked",
            phase=record.phase,
            progress=record.progress,
            reason=reason,
            message=message,
            evidence=evidence,
            summary=record.summary,
            created_at=record.created_at or timestamp,
            started_at=record.started_at or record.created_at or timestamp,
            updated_at=timestamp,
            heartbeat_at=record.heartbeat_at or timestamp,
            done_at=record.done_at,
            verified_at=record.verified_at,
            cancelled_at=record.cancelled_at,
            ttl_seconds=self.config.ttl_seconds,
            source=record.source,
            last_error=record.last_error,
        )

    def _persist_synthetic_invalid(self, task_id: str, event_name: str, reason: str, message: str) -> tuple[TaskLightTaskSummary, TaskLightAggregateState]:
        path = _task_file_path(self.config, task_id)
        summary = _invalid_summary(task_id, file_path=path, error=message)
        state = self.rebuild_state(extra_invalid=summary)
        write_json_atomic(self.config.state_path, state.to_dict())
        append_json_line(
            self.config.events_path,
            {
                "schema_version": SCHEMA_VERSION,
                "event_id": secrets.token_hex(16),
                "task_id": task_id,
                "from": "invalid_json",
                "to": "invalid_json",
                "created_at": iso_now(),
                "sound_type": "none",
                "reason": reason,
                "message": message,
            },
        )
        return summary, state

    def block_task(self, task_id: str, reason: str, message: str, evidence: str) -> tuple[TaskLightTaskRecord | TaskLightTaskSummary, TaskLightAggregateState]:
        validate_task_id(task_id)
        if reason not in BLOCKER_REASONS:
            raise TaskLightError(f"invalid blocker reason: {reason}")
        with locked_state(self.config):
            record, summary, missing = self._load_or_placeholder(task_id)
            if summary is None:
                return self._persist_synthetic_invalid(task_id, "block", "invalid_json", "task record unreadable")
            if record is None:
                # Missing records are turned into a blocked placeholder so the wrapper has traceability.
                blocked = TaskLightTaskRecord(
                    task_id=task_id,
                    title=task_id,
                    slug=slugify(task_id),
                    status="blocked",
                    phase="missing",
                    progress=0.0,
                    reason=reason,
                    message=message,
                    evidence=evidence,
                    created_at=iso_now(),
                    started_at=iso_now(),
                    updated_at=iso_now(),
                    heartbeat_at=iso_now(),
                    ttl_seconds=self.config.ttl_seconds,
                    last_error="task record missing",
                )
                return self._persist_task_and_state(
                    blocked,
                    event_name="block",
                    previous_status="missing",
                    sound_type="blocked",
                    details={"reason": reason, "message": message, "evidence": evidence},
                )
            timestamp = iso_now()
            effective = record.effective_status(
                ttl_seconds=self.config.ttl_seconds,
                verification_ttl_seconds=self.config.verification_ttl_seconds,
            )
            if (
                record.status == "blocked"
                and record.reason == reason
                and record.message == message
                and record.evidence == evidence
            ):
                record.updated_at = record.updated_at or timestamp
            else:
                record.status = "blocked"
                record.reason = reason
                record.message = message
                record.evidence = evidence
                record.updated_at = timestamp
            record.last_error = None
            record.current_event_id = secrets.token_hex(16)
            return self._persist_task_and_state(
                record,
                event_name="block",
                previous_status=effective,
                sound_type="blocked",
                details={"reason": reason, "message": message, "evidence": evidence},
            )

    def done_task(self, task_id: str, summary_text: str) -> tuple[TaskLightTaskRecord | TaskLightTaskSummary, TaskLightAggregateState]:
        validate_task_id(task_id)
        with locked_state(self.config):
            record, summary, missing = self._load_or_placeholder(task_id)
            if summary is None:
                return self._persist_synthetic_invalid(task_id, "done", "invalid_json", "task record unreadable")
            if record is None:
                blocked = TaskLightTaskRecord(
                    task_id=task_id,
                    title=task_id,
                    slug=slugify(task_id),
                    status="blocked",
                    phase="missing",
                    progress=0.0,
                    reason="missing_input",
                    message="task record not found",
                    evidence=f"task_id={task_id}",
                    created_at=iso_now(),
                    started_at=iso_now(),
                    updated_at=iso_now(),
                    heartbeat_at=iso_now(),
                    ttl_seconds=self.config.ttl_seconds,
                    last_error="task record missing",
                )
                return self._persist_task_and_state(
                    blocked,
                    event_name="done",
                    previous_status="missing",
                    sound_type="blocked",
                    details={"reason": "missing_input", "summary": summary_text},
                )
            effective = record.effective_status(
                ttl_seconds=self.config.ttl_seconds,
                verification_ttl_seconds=self.config.verification_ttl_seconds,
            )
            if effective == "blocked":
                blocked = self._blocked_from_record(
                    record,
                    reason="needs_human_review",
                    message="done called while the task is blocked",
                    evidence=record.message or record.reason or "blocked state",
                )
                return self._persist_task_and_state(
                    blocked,
                    event_name="done",
                    previous_status=effective,
                    sound_type="blocked",
                    details={"reason": "needs_human_review", "summary": summary_text},
                )
            timestamp = iso_now()
            record.status = "done_verified" if effective == "done_verified" else "done_unverified"
            record.summary = summary_text
            record.done_at = record.done_at or timestamp
            if record.status == "done_verified":
                record.verified_at = record.verified_at or timestamp
            record.updated_at = timestamp
            record.heartbeat_at = timestamp
            record.last_error = None
            record.current_event_id = secrets.token_hex(16)
            return self._persist_task_and_state(
                record,
                event_name="done",
                previous_status=effective,
                sound_type=None,
                details={"summary": summary_text},
            )

    def verify_task(self, task_id: str) -> tuple[TaskLightTaskRecord | TaskLightTaskSummary, TaskLightAggregateState]:
        validate_task_id(task_id)
        with locked_state(self.config):
            record, summary, missing = self._load_or_placeholder(task_id)
            if summary is None:
                return self._persist_synthetic_invalid(task_id, "verify", "invalid_json", "task record unreadable")
            if record is None:
                blocked = TaskLightTaskRecord(
                    task_id=task_id,
                    title=task_id,
                    slug=slugify(task_id),
                    status="blocked",
                    phase="missing",
                    progress=0.0,
                    reason="missing_input",
                    message="task record not found",
                    evidence=f"task_id={task_id}",
                    created_at=iso_now(),
                    started_at=iso_now(),
                    updated_at=iso_now(),
                    heartbeat_at=iso_now(),
                    ttl_seconds=self.config.ttl_seconds,
                    last_error="task record missing",
                )
                return self._persist_task_and_state(
                    blocked,
                    event_name="verify",
                    previous_status="missing",
                    sound_type="blocked",
                    details={"reason": "missing_input"},
                )
            effective = record.effective_status(
                ttl_seconds=self.config.ttl_seconds,
                verification_ttl_seconds=self.config.verification_ttl_seconds,
            )
            if effective != "done_unverified" and effective != "done_verified":
                blocked = self._blocked_from_record(
                    record,
                    reason="needs_human_review",
                    message="verify requires a done_unverified task",
                    evidence=f"task status={effective}",
                )
                return self._persist_task_and_state(
                    blocked,
                    event_name="verify",
                    previous_status=effective,
                    sound_type="blocked",
                    details={"reason": "needs_human_review"},
                )
            timestamp = iso_now()
            if effective == "done_verified":
                record.updated_at = record.updated_at or timestamp
                record.current_event_id = record.current_event_id or secrets.token_hex(16)
                return self._persist_task_and_state(
                    record,
                    event_name="verify",
                    previous_status=effective,
                    sound_type=None,
                    details={"summary": record.summary or ""},
                )
            record.status = "done_verified"
            record.verified_at = record.verified_at or timestamp
            record.updated_at = timestamp
            record.last_error = None
            record.current_event_id = secrets.token_hex(16)
            return self._persist_task_and_state(
                record,
                event_name="verify",
                previous_status=effective,
                sound_type="done_verified",
                details={"summary": record.summary or ""},
            )

    def clear_task(self, task_id: str) -> tuple[TaskLightTaskRecord | TaskLightTaskSummary, TaskLightAggregateState]:
        validate_task_id(task_id)
        with locked_state(self.config):
            record, summary, missing = self._load_or_placeholder(task_id)
            if summary is None:
                return self._persist_synthetic_invalid(task_id, "clear", "invalid_json", "task record unreadable")
            if record is None:
                cancelled = TaskLightTaskRecord(
                    task_id=task_id,
                    title=task_id,
                    slug=slugify(task_id),
                    status="cancelled",
                    phase="cleared",
                    progress=0.0,
                    reason=None,
                    message=None,
                    evidence=None,
                    created_at=iso_now(),
                    started_at=iso_now(),
                    updated_at=iso_now(),
                    cancelled_at=iso_now(),
                    ttl_seconds=self.config.ttl_seconds,
                )
                return self._persist_task_and_state(
                    cancelled,
                    event_name="clear",
                    previous_status="missing",
                    sound_type=None,
                    details={"result": "cancelled"},
                )
            effective = record.effective_status(
                ttl_seconds=self.config.ttl_seconds,
                verification_ttl_seconds=self.config.verification_ttl_seconds,
            )
            timestamp = iso_now()
            record.status = "cancelled"
            record.cancelled_at = record.cancelled_at or timestamp
            record.updated_at = timestamp
            record.last_error = None
            record.current_event_id = secrets.token_hex(16)
            return self._persist_task_and_state(
                record,
                event_name="clear",
                previous_status=effective,
                sound_type=None,
                details={"result": "cancelled"},
            )

    def release_task(self, task_id: str) -> tuple[TaskLightTaskRecord | TaskLightTaskSummary, TaskLightAggregateState]:
        validate_task_id(task_id)
        with locked_state(self.config):
            record, summary, missing = self._load_or_placeholder(task_id)
            if summary is None:
                return self._persist_synthetic_invalid(task_id, "release", "invalid_json", "task record unreadable")
            if record is None:
                released = TaskLightTaskRecord(
                    task_id=task_id,
                    title=task_id,
                    slug=slugify(task_id),
                    status="cancelled",
                    phase="released",
                    progress=0.0,
                    created_at=iso_now(),
                    started_at=iso_now(),
                    updated_at=iso_now(),
                    cancelled_at=iso_now(),
                    ttl_seconds=self.config.ttl_seconds,
                )
                return self._persist_task_and_state(
                    released,
                    event_name="release",
                    previous_status="missing",
                    sound_type=None,
                    details={"result": "released"},
                )
            effective = record.effective_status(
                ttl_seconds=self.config.ttl_seconds,
                verification_ttl_seconds=self.config.verification_ttl_seconds,
            )
            timestamp = iso_now()
            record.status = "cancelled"
            record.phase = "released"
            record.cancelled_at = record.cancelled_at or timestamp
            record.updated_at = timestamp
            record.last_error = None
            record.current_event_id = secrets.token_hex(16)
            return self._persist_task_and_state(
                record,
                event_name="release",
                previous_status=effective,
                sound_type=None,
                details={"result": "released"},
            )


def configure_from_args() -> TaskLightConfig:
    return TaskLightConfig.from_env()


def _emit_json(payload: Any) -> None:
    print(json_dump(payload), end="")


def _emit_error(payload: Any) -> None:
    print(json_dump(payload), file=sys.stderr, end="")


def print_status(store: TaskLightStore) -> TaskLightAggregateState:
    state = store.load_state()
    _emit_json(state.to_dict())
    return state


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="tasklight", description="66TaskLight multi-task status bus")
    subparsers = parser.add_subparsers(dest="command", required=True)

    start_parser = subparsers.add_parser("start", help="Start a new task")
    start_parser.add_argument("--title", required=True)
    start_parser.add_argument("--print-id", action="store_true")

    heartbeat_parser = subparsers.add_parser("heartbeat", help="Record a task heartbeat")
    heartbeat_parser.add_argument("--task-id", required=True)
    heartbeat_parser.add_argument("--phase", required=True)
    heartbeat_parser.add_argument("--progress", required=True, type=float)

    block_parser = subparsers.add_parser("block", help="Mark a task as blocked")
    block_parser.add_argument("--task-id", required=True)
    block_parser.add_argument("--reason", required=True)
    block_parser.add_argument("--message", required=True)
    block_parser.add_argument("--evidence", required=True)

    done_parser = subparsers.add_parser("done", help="Mark a task as done_unverified")
    done_parser.add_argument("--task-id", required=True)
    done_parser.add_argument("--summary", required=True)

    verify_parser = subparsers.add_parser("verify", help="Promote done_unverified to done_verified")
    verify_parser.add_argument("--task-id", required=True)

    clear_parser = subparsers.add_parser("clear", help="Cancel a task")
    clear_parser.add_argument("--task-id", required=True)

    release_parser = subparsers.add_parser("release", help="Release a current binding without sound")
    release_parser.add_argument("--task-id", required=True)

    subparsers.add_parser("list", help="List tasks")
    show_parser = subparsers.add_parser("show", help="Show one task")
    show_parser.add_argument("task_id")
    subparsers.add_parser("status", help="Show aggregate status")
    observe_parser = subparsers.add_parser("observe-local", help="Scan local Codex/Hermes processes")
    observe_parser.add_argument("--watch", action="store_true")
    subparsers.add_parser("observations", help="Show observed thread snapshot")
    subparsers.add_parser("clear-observations", help="Remove observation snapshots")
    return parser


def _stringify_result(result: TaskLightAggregateState | TaskLightObservationsState | TaskLightTaskRecord | TaskLightTaskSummary) -> dict[str, Any]:
    if isinstance(result, TaskLightAggregateState):
        return result.to_dict()
    if isinstance(result, TaskLightObservationsState):
        return result.to_dict()
    if isinstance(result, TaskLightTaskSummary):
        return result.to_dict()
    return result.to_dict()


def _is_failure_result(result: Any) -> bool:
    status = getattr(result, "status", None)
    if status == "blocked":
        return True
    if status == "invalid_json":
        return True
    return False


def dispatch(args: argparse.Namespace) -> int:
    config = configure_from_args()
    store = TaskLightStore(config)
    try:
        store.ensure_layout()
        if args.command == "start":
            with locked_state(config):
                record, state = store.start_task(args.title)
                _emit_json(record.to_dict())
                if args.print_id:
                    print(record.task_id, file=sys.stderr)
                return 1 if _is_failure_result(record) else 0
        if args.command == "heartbeat":
            result, state = store.heartbeat_task(args.task_id, args.phase, args.progress)
            _emit_json(_stringify_result(result))
            return 1 if _is_failure_result(result) else 0
        if args.command == "block":
            result, state = store.block_task(args.task_id, args.reason, args.message, args.evidence)
            _emit_json(_stringify_result(result))
            return 0
        if args.command == "done":
            result, state = store.done_task(args.task_id, args.summary)
            _emit_json(_stringify_result(result))
            return 1 if _is_failure_result(result) else 0
        if args.command == "verify":
            result, state = store.verify_task(args.task_id)
            _emit_json(_stringify_result(result))
            return 1 if _is_failure_result(result) else 0
        if args.command == "clear":
            result, state = store.clear_task(args.task_id)
            _emit_json(_stringify_result(result))
            return 1 if _is_failure_result(result) else 0
        if args.command == "release":
            result, state = store.release_task(args.task_id)
            _emit_json(_stringify_result(result))
            return 1 if _is_failure_result(result) else 0
        if args.command == "list":
            state = store.list_tasks()
            _emit_json(state.to_dict())
            return 0
        if args.command == "show":
            _emit_json(store.show_task(args.task_id))
            return 0
        if args.command == "status":
            _emit_json(store.load_state().to_dict())
            return 0
        if args.command == "observe-local":
            state = store.observe_local(watch=args.watch)
            _emit_json(state.to_dict())
            return 0
        if args.command == "observations":
            state = store.list_observations()
            _emit_json(state.to_dict())
            return 0
        if args.command == "clear-observations":
            state = store.clear_observations()
            _emit_json(state.to_dict())
            return 0
        raise TaskLightError(f"unknown command: {args.command}")
    except TaskLightError as exc:
        _emit_error({"error": str(exc)})
        return 2
    except OSError as exc:
        _emit_error({"error": str(exc)})
        return 2


def main(argv: Optional[list[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return dispatch(args)


if __name__ == "__main__":
    raise SystemExit(main())
