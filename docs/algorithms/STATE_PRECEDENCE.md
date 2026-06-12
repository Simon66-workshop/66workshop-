# State Precedence｜M3.3

The global lamp must be computed exactly once by the Turn Runtime Arbiter.

## Precedence

```text
1. explicit/wrapper open_blocker                    -> BLOCKED
2. fresh hook/appserver needs_human_review           -> BLOCKED
3. active_execution candidate                        -> RUNNING
4. appserver observed_active_high_confidence         -> RUNNING
5. pending_verify                                    -> PENDING
6. visible recent done_verified                      -> DONE
7. otherwise                                         -> IDLE
```

## Why this order

- Explicit blocker is a real operational problem.
- Approval pending must be red because human action is required.
- Active execution is blue.
- AppServer cross-thread active is strong enough to keep blue.
- Pending verification is not running and not done.
- Done verified is green only when nothing else requires attention.
- Idle means no active, blocked, pending, or visible recent done signal.

## Hard Guards

```text
process_observer only         -> never global RUNNING
private global-only active    -> never global RUNNING
stale hook blocker            -> never permanent BLOCKED
Stop                          -> done_unverified, not done_verified
verify                        -> only path to DONE / green
```

