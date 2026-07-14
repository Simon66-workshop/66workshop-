# 66TaskLight M7.1 Reliability Closure Audit

## Decision

**NEEDS_HUMAN_REVIEW**

Score: **90 / 100**

The previous P0 is cleared: the retention smoke is now time-independent and `check_all` passed three consecutive final runs. The MVP is not closed as production-ready because the real LaunchAgent Bridge still reproduces a heartbeat timeout under the current runtime backlog, and the current 100-sample render window has a p99 of 233.577 ms. These are runtime reliability observations, not reasons to weaken a hard gate.

## Scope

- Reliability smoke and retention boundary
- Hook Bridge machine-readable health semantics
- State volume and report-only lifecycle maintenance
- Large-state active-path latency
- Render telemetry long-tail analysis
- Workspace coverage layering
- Existing UI/state/quota/security gates

No auth, cookie, Keychain, token, prompt, response, raw log body, external API, auto-trust, purchase, reset, commit, or push action was performed.

## Evidence Highlights

| Area | Result |
|---|---|
| `check_all` | 3 consecutive final runs passed |
| Previous P0 | Cleared; no fixed historical fixture date remains in the retention smoke |
| Retention boundary | New and boundary events preserved; old events removed; idempotence verified |
| Hook Bridge fixture timeline | 12 samples / 57.03s, all `STATUS=ok`, max pending 4 |
| Real Hook Bridge after full gates | `STATUS=error`/heartbeat timeout observed; manual one-shot drained 47 signals successfully |
| Large-state smoke | heartbeat 0.102s, start 0.099s, release 0.100s |
| Render recent 100 | p50 153.510ms, p95 178.573ms, p99 233.577ms, max 233.577ms; no >500ms |
| State volume | 10,477+ task records, 2,794 bindings, 965 UI clients; report-only maintenance |
| Workspace coverage | 42 total, 35 trusted, 7 missing hooks; preferred 7/7 trusted; discovery probe available |
| Quota | Local `codex_appserver`, fresh, display-only; low quota did not change the lamp decision |

## Acceptance

The P0 hard gate is restored, but the independent audit does not promote the product to `PASS`. The operational state is `TRIAL_READY_PENDING_HUMAN_PREFLIGHT`, not an instruction to start the clock immediately. A controlled 3-day trial may begin only after a human-approved 30-minute preflight confirms one Bridge, one managed observer, no LaunchAgent restart, monotonic offset progress, pending returning to zero after bursts, no heartbeat timeout, and `ok`/`idle` as the final health state. Direct productionization is not recommended.

## Human Preflight Gate

Before the 3-day trial starts, record a 30-minute runtime sample. Stop the trial if `health_state=error`, `tasklight heartbeat timed out`, pending remains elevated, the Bridge restarts, or any new render sample exceeds 500ms. The preflight is a human approval gate, not a smoke-test substitution.

## Remaining Blockers

1. Real LaunchAgent Bridge timeout under backlog/observer interaction must be explained and closed with a persistent runtime sample, not only a fixture smoke.
2. Current render p99 is above the 160ms target, although the read-model stage itself is now bounded and no sample exceeded 500ms.
3. Workspace discovery probe is `available`, while the separate hooks trust probe is `unavailable`; no automatic trust was attempted.

See the linked evidence files in `evidence-index.md`.
