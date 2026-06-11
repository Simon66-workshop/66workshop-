# 66TaskLight Real Trial Guide

This is a low-risk runbook for trying 66TaskLight in real wrapper workflows.
It is intentionally conservative and does not add new product features.

## Day 1

- Run a single low-risk task through one wrapper.
- Watch for a clean `running -> done_unverified -> verify -> done_verified` flow.
- Log any false red lights, missed state updates, or unexpected sounds.
- Start the observer before the task:
  - manual: `./tasklight observe-local --watch`
  - or install the LaunchAgent with `./script/install_observer_launch_agent.sh`

## Day 2

- Run two wrappers in parallel.
- Confirm the board stays consistent when one task is blocked and the other is still running.
- Check that counts, ordering, and `pending_verify_count` remain stable.

## Day 3

- Intentionally create one failed task and one normal task.
- Confirm the failed task turns red and the normal task stays visible.
- Verify that red sounds do not repeat for the same event burst.
- If you also run `observe-local`, confirm a manual Codex-like process appears and then disappears silently after a few scans.

## What To Record

- False positives
- False negatives
- Repeated sounds
- UI update delay
- Corrupt JSON handling
- Any mismatch between CLI output and the dashboard
- Observed thread appear/disappear timing

## Suggested Routine

```bash
./script/smoke_multitask.sh
./script/smoke_verify_gate.sh
./script/smoke_ttl.sh
./script/smoke_invalid_task_json.sh
./script/smoke_observations.sh
./script/check_all.sh
```

If you are manually validating audio, do it separately from the automated smoke
suite so the scripts remain reliable in CI-like runs.
