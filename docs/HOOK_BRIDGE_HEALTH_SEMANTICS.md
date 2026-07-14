# Hook Bridge Health Semantics

The LaunchAgent health check separates worker liveness from input processing.

## Fields

- `process_alive`: launchctl/pgrep process evidence
- `launchctl_status`: LaunchAgent registration state
- `latest_input_signal_age_sec`: newest hook input age
- `latest_processed_signal_age_sec`: newest processed ledger age
- `offset_updated_age_sec`: offset file progress age
- `health_written_age_sec`: health file write age
- `last_processed_signal_id`: sanitized signal identity hash
- `pending_signal_count`: unprocessed input count based on file offsets
- `bridge_poll_age_sec`: last bridge cycle age
- `stale_threshold_sec`: processing freshness threshold
- `idle_threshold_sec`: quiet-worker observation threshold
- `final_status_reason`: machine-readable explanation

## Status Rules

- `ok`: process is alive, inputs are being processed or health is fresh.
- `idle`: process is alive, there is no pending input, and the worker is quiet.
- `stale`: pending input exists while offsets and processed/health progress have
  exceeded the stale threshold.
- `error`: health/offset files are unreadable or the bridge reports an error.
- `not_running`: process or LaunchAgent is not available.

A quiet worker with no pending signal is not stale merely because its last
heartbeat is older than the active-processing threshold. This prevents the old
false `STATUS=stale` result when `latest signal age=0` and health state is ok.
