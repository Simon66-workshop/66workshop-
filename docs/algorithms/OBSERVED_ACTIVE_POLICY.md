# Observed Active Policy｜M3.3

## Goal

Prevent weak process / private signals from incorrectly driving global RUNNING.

## Observed Categories

```text
appserver_active      = high-value Codex AppServer active thread signal
process_observed     = low-confidence process observation
observed_active      = total visible observed candidates
```

## Rules

1. `codex_appserver` active thread may affect global RUNNING if fresh and confidence is high.
2. `process_observer` alone must not affect global RUNNING.
3. `private_probe global-only` must not affect global RUNNING.
4. `private_probe thread-scoped` can assist but must not dominate without fresh hook/appserver evidence.
5. Observation chip can still display process observations, but title should not become RUNNING from process-only evidence.

## Freshness

```text
TASKLIGHT_OBSERVED_ACTIVE_TTL_SECONDS=5
TASKLIGHT_OBSERVED_MIN_CONFIRMATIONS=2
TASKLIGHT_OBSERVED_MISSING_RELEASE_COUNT=3
```

## UI

Compact UI can keep one `观察` chip, but diagnostics must split:

```text
appserver_active_count
process_observed_count
observed_false_positive_count
```

## False Positive Denylist

These should not be active observed tasks:

```text
app-server
node_repl
chronicle
Computer Use
crash handler
Hermes gateway
background helper / infrastructure process
```

