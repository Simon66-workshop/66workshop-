# Turn Runtime Arbiter Algorithm｜M3.3

## Problem

多线程状态不稳定的根因不是 UI，而是多源状态仲裁不够强。当前系统可能同时看到：

- `codex_hook`
- `codex_appserver`
- `codex_private_probe`
- `process_observer`
- `current_thread_watcher`
- `explicit tasklight`

这些来源的可信度、TTL、身份粒度不同。如果直接把它们的 `active` 都算进全局灯，LuckyCat 会出现假 RUNNING / 假 BLOCKED。

## Principle

```text
Codex Thread = 会话容器
Codex Turn = 一次用户请求 / agent 执行单元
TaskLight Task = 一个 turn 的本地可视化投影
Runtime Candidate = 可能正在运行的候选对象
UI State = State Projector / Arbiter 输出的最终裁判结果
```

## Architecture

```text
codex_hook
codex_appserver
codex_private_probe
process_observer
current_thread_watcher
explicit tasklight
        ↓
normalized_signals.jsonl
        ↓
Turn Runtime Arbiter
        ↓
ui_state.json
        ↓
LuckyCat UI
```

## Candidate Model

每一个可能的运行对象先归一成 candidate：

```json
{
  "candidate_id": "turn:019eb571",
  "kind": "codex_turn",
  "task_id": "20260611-xxx",
  "thread_id": "optional",
  "turn_id": "019eb571",
  "pid": null,
  "source_set": ["codex_hook", "codex_appserver"],
  "last_signal_at": "2026-06-11T15:20:00+08:00",
  "last_event_type": "item_started",
  "base_confidence": 0.95,
  "freshness_score": 1.0,
  "identity_score": 1.0,
  "consistency_score": 1.0,
  "runtime_score": 0.95,
  "display_scope": "active_execution",
  "state_cause": "hook:item_started"
}
```

## Runtime Score

```text
runtime_score = base_confidence × freshness_score × identity_score × consistency_score
```

## Display Scope

```text
runtime_score >= 0.85              -> active_execution
0.55 <= runtime_score < 0.85       -> observed_active_high_confidence
0.35 <= runtime_score < 0.55       -> observed_only
runtime_score < 0.35               -> ignored
```

## Global Status Precedence

```text
1. explicit/wrapper open_blocker                     -> BLOCKED
2. fresh hook/appserver needs_human_review            -> BLOCKED
3. any active_execution                               -> RUNNING
4. appserver observed_active_high_confidence          -> RUNNING
5. pending_verify                                     -> PENDING
6. visible recent done_verified                       -> DONE
7. otherwise                                          -> IDLE
```

## Hard Rules

1. `process_observer` alone must not set global `RUNNING`.
2. `private_probe` global-only signal must not set global `RUNNING`.
3. `current_thread_watcher` alone must not set global `RUNNING` unless backed by fresh appserver / hook / private thread-scoped confidence threshold.
4. `codex_appserver` active thread may set global `RUNNING` even without managed task, because it is a cross-thread active signal.
5. `Stop` maps to `done_unverified`, never `done_verified`.
6. `verify` is the only green completion transition.
7. UI reads `ui_state.json`; Swift must not reimplement precedence.

