from __future__ import annotations

import io
import json
import os
import re
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest.mock import patch

from cli.tasklight import TaskLightConfig, TaskLightStore, build_parser, main


class TaskLightTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory()
        self.addCleanup(self.tempdir.cleanup)
        self.state_dir = Path(self.tempdir.name)
        self.config = TaskLightConfig(state_dir=self.state_dir, ttl_seconds=1, refresh_seconds=0.25)
        self.store = TaskLightStore(self.config)
        self.store.ensure_layout()

    def read_json(self, path: Path) -> dict[str, object]:
        with open(path, "r", encoding="utf-8") as handle:
            return json.load(handle)

    def corrupt(self, path: Path, text: str = "{broken") -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def test_atomic_write_and_reload_valid_state(self) -> None:
        record, state = self.store.start_task("Example task")
        self.assertTrue(re.match(r"^\d{8}-\d{6}-[a-z0-9-]+-[0-9a-f]{8}$", record.task_id))
        self.assertTrue((self.state_dir / "state.json").exists())
        self.assertTrue((self.state_dir / "tasks" / f"{record.task_id}.json").exists())

        loaded = self.store.load_state()
        self.assertEqual(loaded.global_status, "running")
        self.assertEqual(len(loaded.tasks), 1)
        self.assertEqual(loaded.tasks[0].task_id, record.task_id)
        self.assertEqual(loaded.tasks[0].status, "running")

    def test_corrupt_state_json_falls_back_to_stale(self) -> None:
        record, state = self.store.start_task("Recover me")
        self.corrupt(self.config.state_path)

        loaded = self.store.load_state()
        self.assertEqual(loaded.source_health, "corrupt_state")
        self.assertEqual(loaded.lamp_status, "stale")
        self.assertEqual(loaded.global_status, "running")
        self.assertEqual(len(loaded.tasks), 1)
        self.assertEqual(loaded.tasks[0].task_id, record.task_id)

    def test_corrupt_task_json_isolated(self) -> None:
        a, _ = self.store.start_task("Alpha")
        b, _ = self.store.start_task("Beta")
        self.corrupt(self.config.tasks_dir / f"{b.task_id}.json", '{"task_id":')

        loaded = self.store.load_state()
        self.assertEqual(len(loaded.tasks), 1)
        self.assertEqual(loaded.tasks[0].task_id, a.task_id)
        self.assertEqual(len(loaded.invalid_tasks), 1)
        self.assertEqual(loaded.invalid_tasks[0].task_id, b.task_id)
        self.assertEqual(loaded.global_status, "running")

    def test_invalid_transition_writes_blocked_state(self) -> None:
        record, _ = self.store.start_task("Blocked transition")
        result, _ = self.store.verify_task(record.task_id)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.reason, "needs_human_review")

        loaded = self.store.load_task(record.task_id)
        self.assertEqual(loaded.status, "blocked")
        self.assertEqual(loaded.reason, "needs_human_review")

    def test_heartbeat_ttl_becomes_stale(self) -> None:
        record, _ = self.store.start_task("Timer")
        task_path = self.config.tasks_dir / f"{record.task_id}.json"
        data = self.read_json(task_path)
        data["heartbeat_at"] = "2020-01-01T00:00:00Z"
        data["updated_at"] = "2020-01-01T00:00:00Z"
        data["status"] = "running"
        task_path.write_text(json.dumps(data, ensure_ascii=True, indent=2) + "\n", encoding="utf-8")

        loaded = self.store.load_state()
        self.assertEqual(loaded.tasks[0].status, "stale")
        self.assertEqual(loaded.global_status, "blocked")
        self.assertEqual(loaded.counts.stale, 1)

    def test_repeated_identical_block_keeps_alert_fingerprint_stable(self) -> None:
        record, _ = self.store.start_task("Block stable")
        first, _ = self.store.block_task(
            record.task_id,
            "missing_input",
            "dependency missing",
            "npm not installed",
        )
        second, _ = self.store.block_task(
            record.task_id,
            "missing_input",
            "dependency missing",
            "npm not installed",
        )
        self.assertEqual(first.alert_fingerprint(), second.alert_fingerprint())
        self.assertEqual(second.status, "blocked")

    def test_repeated_identical_done_keeps_alert_fingerprint_stable(self) -> None:
        record, _ = self.store.start_task("Done stable")
        first, _ = self.store.done_task(record.task_id, "verified complete")
        second, _ = self.store.done_task(record.task_id, "verified complete")
        self.assertEqual(first.alert_fingerprint(), second.alert_fingerprint())
        self.assertEqual(second.status, "done_unverified")

        verified, _ = self.store.verify_task(record.task_id)
        self.assertEqual(verified.status, "done_verified")

    def test_done_unverified_counts_pending_then_expires_to_stale(self) -> None:
        record, _ = self.store.start_task("Pending verify")
        done_record, state = self.store.done_task(record.task_id, "awaiting acceptance")
        self.assertEqual(done_record.status, "done_unverified")
        self.assertIsNone(state.tasks[0].sound_type)
        self.assertEqual(state.counts.pending_verify_count, 1)
        self.assertEqual(state.global_status, "running")

        task_path = self.config.tasks_dir / f"{record.task_id}.json"
        data = self.read_json(task_path)
        data["done_at"] = "2020-01-01T00:00:00Z"
        data["updated_at"] = "2020-01-01T00:00:00Z"
        data["status"] = "done_unverified"
        task_path.write_text(json.dumps(data, ensure_ascii=True, indent=2) + "\n", encoding="utf-8")

        loaded = self.store.load_state()
        self.assertEqual(loaded.tasks[0].status, "stale")
        self.assertEqual(loaded.counts.pending_verify_count, 0)
        self.assertEqual(loaded.counts.stale, 1)
        self.assertEqual(loaded.global_status, "blocked")
        self.assertEqual(loaded.tasks[0].last_error, "acceptance gate expired")

    def test_cli_parser_covers_required_subcommands(self) -> None:
        parser = build_parser()
        self.assertIsNotNone(parser.parse_args(["start", "--title", "Demo", "--print-id"]))
        self.assertIsNotNone(parser.parse_args(["heartbeat", "--task-id", "20260609-000000-demo-abc12345", "--phase", "run", "--progress", "0.2"]))
        self.assertIsNotNone(parser.parse_args(["block", "--task-id", "20260609-000000-demo-abc12345", "--reason", "missing_input", "--message", "m", "--evidence", "e"]))
        self.assertIsNotNone(parser.parse_args(["done", "--task-id", "20260609-000000-demo-abc12345", "--summary", "ok"]))
        self.assertIsNotNone(parser.parse_args(["verify", "--task-id", "20260609-000000-demo-abc12345"]))
        self.assertIsNotNone(parser.parse_args(["clear", "--task-id", "20260609-000000-demo-abc12345"]))
        self.assertIsNotNone(parser.parse_args(["release", "--task-id", "20260609-000000-demo-abc12345"]))
        self.assertIsNotNone(parser.parse_args(["list"]))
        self.assertIsNotNone(parser.parse_args(["show", "20260609-000000-demo-abc12345"]))
        self.assertIsNotNone(parser.parse_args(["status"]))
        self.assertIsNotNone(parser.parse_args(["observe-local"]))
        self.assertIsNotNone(parser.parse_args(["observe-local", "--watch"]))
        self.assertIsNotNone(parser.parse_args(["observations"]))
        self.assertIsNotNone(parser.parse_args(["clear-observations"]))

    def test_list_orders_tasks_by_required_priority(self) -> None:
        blocked, _ = self.store.start_task("Blocked")
        running, _ = self.store.start_task("Running")
        done, _ = self.store.start_task("Done")
        self.store.block_task(blocked.task_id, "missing_input", "blocked", "evidence")
        self.store.done_task(done.task_id, "summary")
        self.store.verify_task(done.task_id)
        self.store.clear_task(running.task_id)

        state = self.store.list_tasks()
        statuses = [task.status for task in state.tasks]
        self.assertEqual(statuses[0], "blocked")
        self.assertIn("done_verified", statuses)
        self.assertEqual(statuses[-1], "cancelled")

    def test_release_marks_cancelled_without_sound(self) -> None:
        record, _ = self.store.start_task("Release me")
        released, _ = self.store.release_task(record.task_id)
        self.assertEqual(released.status, "cancelled")
        self.assertEqual(released.phase, "released")
        self.assertIsNone(self.store.load_state().tasks[0].sound_type)

    def test_show_returns_full_record(self) -> None:
        record, _ = self.store.start_task("Show me")
        shown = self.store.show_task(record.task_id)
        self.assertEqual(shown["task_id"], record.task_id)
        self.assertEqual(shown["status"], "running")
        self.assertEqual(shown["title"], "Show me")

    def test_events_append_required_fields(self) -> None:
        record, _ = self.store.start_task("Events")
        self.store.block_task(record.task_id, "missing_input", "blocked", "evidence")
        with open(self.config.events_path, "r", encoding="utf-8") as handle:
            lines = handle.readlines()
        self.assertGreaterEqual(len(lines), 2)
        event = json.loads(lines[-1])
        self.assertIn("event_id", event)
        self.assertIn("task_id", event)
        self.assertIn("from", event)
        self.assertIn("to", event)
        self.assertIn("created_at", event)
        self.assertIn("sound_type", event)

    def test_main_prints_json(self) -> None:
        stdout = io.StringIO()
        stderr = io.StringIO()
        old_env = os.environ.get("TASKLIGHT_STATE_DIR")
        os.environ["TASKLIGHT_STATE_DIR"] = str(self.state_dir)
        try:
            with redirect_stdout(stdout), redirect_stderr(stderr):
                rc = main(["status"])
        finally:
            if old_env is None:
                os.environ.pop("TASKLIGHT_STATE_DIR", None)
            else:
                os.environ["TASKLIGHT_STATE_DIR"] = old_env
        self.assertEqual(rc, 0)
        payload = json.loads(stdout.getvalue())
        self.assertIn("global_status", payload)

    def test_observe_local_scans_and_clears_observations(self) -> None:
        live_rows = [
            {
                "pid": 100,
                "ppid": 1,
                "uid": os.getuid(),
                "lstart": "Tue Jun 10 11:59:50 2026",
                "command": "/Applications/Codex.app/Contents/MacOS/Codex",
            },
            {
                "pid": 200,
                "ppid": 100,
                "uid": os.getuid(),
                "lstart": "Tue Jun 10 11:59:51 2026",
                "command": "/Applications/Codex.app/Contents/Resources/codex app-server --analytics-default-enabled",
            },
            {
                "pid": 4321,
                "ppid": 200,
                "uid": os.getuid(),
                "lstart": "Tue Jun 10 12:00:00 2026",
                "command": "codex exec smoke-observed-thread",
            },
            {
                "pid": 4322,
                "ppid": 200,
                "uid": os.getuid(),
                "lstart": "Tue Jun 10 12:00:01 2026",
                "command": "codex exec --json --config model_provider=\"openai-memgen\" smoke-observed-thread",
            },
            {
                "pid": 4323,
                "ppid": 200,
                "uid": os.getuid(),
                "lstart": "Tue Jun 10 12:00:02 2026",
                "command": "codex exec TASKLIGHT_TASK_ID=20260609-000000-demo-abc12345 smoke-managed-thread",
            },
            {
                "pid": 4324,
                "ppid": 200,
                "uid": os.getuid(),
                "lstart": "Tue Jun 10 12:00:03 2026",
                "command": "python3 /tmp/66tasklight/script/hook_signal_bridge.py --watch",
            },
        ]
        cwd_map = {
            4321: "/tmp/codex-observed",
            4322: "/tmp/codex-observed",
            4323: "/tmp/codex-observed",
            4324: "/tmp/66tasklight",
        }
        with patch("cli.tasklight._parse_ps_snapshot", return_value=live_rows), patch(
            "cli.tasklight._process_cwd", side_effect=lambda pid: cwd_map.get(pid)
        ):
            state = self.store.observe_local()
        self.assertEqual(state.counts.active, 1)
        self.assertEqual(len(state.observations), 1)
        self.assertEqual(state.observations[0].status, "observed_active")
        self.assertIn("smoke-observed-thread", state.observations[0].command)
        self.assertTrue((self.state_dir / "observations_state.json").exists())
        self.assertTrue((self.state_dir / "observations" / f"{state.observations[0].observation_id}.json").exists())

        with patch("cli.tasklight._parse_ps_snapshot", return_value=[]), patch("cli.tasklight._process_cwd", return_value=None):
            self.store.observe_local()
            self.store.observe_local()
            final_state = self.store.observe_local()
        self.assertEqual(final_state.counts.active, 0)
        self.assertEqual(final_state.counts.disappeared, 1)
        self.assertEqual(len(final_state.observations), 0)

        cleared = self.store.clear_observations()
        self.assertEqual(cleared.counts.total, 0)
        self.assertEqual(cleared.counts.active, 0)
        self.assertTrue((self.state_dir / "observations_state.json").exists())

    def test_observe_local_requires_codex_lineage(self) -> None:
        live_rows = [
            {
                "pid": 5001,
                "ppid": 1,
                "uid": os.getuid(),
                "lstart": "Tue Jun 10 12:10:00 2026",
                "command": "codex exec detached-thread",
            },
        ]
        with patch("cli.tasklight._parse_ps_snapshot", return_value=live_rows), patch(
            "cli.tasklight._process_cwd", return_value="/tmp/detached-thread"
        ):
            state = self.store.observe_local()
        self.assertEqual(state.counts.active, 0)
        self.assertEqual(len(state.observations), 0)


if __name__ == "__main__":
    unittest.main()
