# Evidence Index

## Commands

| Evidence | Result |
|---|---|
| `python3 -m py_compile cli/*.py script/*.py script/self-review/*.py script/self-review/auditors/*.py` | pass |
| `python3 -m unittest discover -s cli/tests -p 'test_*.py'` | 18 tests pass |
| `cd mac/66TaskLight && swift build` | pass |
| `cd mac/66TaskLight && swift run TaskLightChecks` | pass |
| `./script/check_all.sh` | final runs 1/2/3 exit 0 |
| `./script/smoke_signal_retention_time_boundary.sh` | pass |
| `./script/smoke_hook_bridge_health_timeline.sh` | three standalone runs pass |
| `./script/smoke_storage_lifecycle.sh` | pass |
| `./script/smoke_large_state_render_performance.sh` | pass |
| `./script/check_state_projector.sh` | exit 0 |
| `./script/check_ui_client.sh` | exit 0 |
| `./script/check_codex_quota.sh` | exit 0 |
| `./script/check_codex_quota_watcher_launch_agent.sh` | exit 0 |
| `./script/check_codex_workspaces_coverage.sh --skip-appserver` | pass with needs_hooks summary |
| `./script/check_codex_hooks_trust.sh` | `hooks_trust_probe_unavailable`, exit 1; no trust action |
| `./script/check_codex_workspaces_coverage.sh --skip-appserver` | `workspace_discovery_probe=available` |

## Files

- `evidence/storage-volume-baseline.json` and `.md`: sanitized size/count/timing baseline.
- `evidence/render-performance.json` and `.md`: retained render population.
- `evidence/render-performance-recent-100.json` and `.md`: current rolling window.
- `evidence/bridge-health-timeline.json`: sanitized 12-sample fixture timeline.
- `evidence/check_all` proof is represented by `/tmp/66tasklight-checkall-m71-final-1/2/3.log` during execution; no raw log body is included in this package.

## Safety

The report package contains no auth, cookie, Keychain, credential, token, prompt, response, or raw log body. Real maintenance was not applied.
