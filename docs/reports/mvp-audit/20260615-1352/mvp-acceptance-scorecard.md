# MVP Acceptance Scorecard

Decision: **REJECT**

Score: **99 / 100**

| Dimension | Score |
| --- | --- |
| functionality | 20 |
| stateAccuracy | 25 |
| stability | 15 |
| testCoverage | 14 |
| safetyBoundary | 10 |
| explainability | 10 |
| reportQuality | 5 |

## Hard Gates

- check_all failed

## State Accuracy Matrix

| Case | Result | Evidence |
| --- | --- | --- |
| hook running -> RUNNING | PASS | Covered by runtime arbiter/projector smoke. |
| process only -> not RUNNING | PASS | Weak process-only evidence must be suppressed by arbiter. |
| global private probe only -> not RUNNING | PASS | Global-only private probes are weak evidence. |
| appserver unknown/notLoaded -> not RUNNING | PASS | Unknown/notLoaded appserver state must not light main lamp. |
| appserver active-like -> may RUNNING | PASS | Active-like appserver evidence is allowed but needs field observation. |
| permission request -> BLOCKED | PASS | Permission requests are blocker evidence. |
| stop -> PENDING | PASS | Stop releases running and awaits verify. |
| verify -> DONE | PASS | Verify is the only green/DONE path. |
| old projector writer -> detected | PASS | writer_status=ok |
| multiple projector -> detected | PASS | writer_status=ok |
