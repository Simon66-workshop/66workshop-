# Hook Bridge Health Timeline

## Fixture timeline

The new timeline smoke sampled the isolated bridge for 57.03 seconds at 5-second intervals. All 12 samples returned `STATUS=ok`; maximum pending signal count was 4. The idle phase returned `idle`/`ok`, and only a deliberately unprocessed pending signal returned `stale` with reason `pending_input_not_processed_within_threshold`.

Evidence: `evidence/bridge-health-timeline.json`.

## Real runtime observation

The real LaunchAgent was running and machine-readable, but after the three full `check_all` runs it reproduced `health_state=error` with `tasklight heartbeat timed out after 10s` and a pending backlog. A manual one-shot bridge run processed 47 signals with decisions aggregated as heartbeat, coalesced heartbeat, and stop-to-done-unverified. This proves the signal data is processable but does not close the persistent LaunchAgent failure under load.

## Semantic conclusion

The old false-stale condition is fixed in the health model: a quiet worker with no pending input is `idle`, not `stale`. A pending signal with no offset/health progress is still `stale`. The remaining issue is operational throughput/launch reliability, not a reason to weaken the semantic gate.
