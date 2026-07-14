# Evidence Index

## 代码与协议

| Evidence | Purpose |
|---|---|
| `docs/STATUS_PROTOCOL.md` | 状态枚举、UI read model、主灯优先级、quota display-only 规则 |
| `docs/STATE_PROJECTOR.md` | projector 输入、runtime arbiter、writer identity、fallback 语义 |
| `docs/HOOK_SIGNAL_BRIDGE.md` | turn identity、hook event mapping、stop/done_unverified、lease/coalesce |
| `docs/HOOK_BRIDGE_LAUNCH_AGENT.md` | bridge LaunchAgent health/status 语义 |
| `docs/CODEX_QUOTA_WIDGET.md` | AppServer quota、reset credits、fresh/stale、display-only 边界 |
| `docs/CODEX_WORKSPACE_ONBOARDING.md` | workspace coverage、手动 Trust、禁止自动 trust |
| `docs/self-review/66TASKLIGHT_SELF_REVIEW_ENGINE.md` | hard boundary、evidence、REJECT 规则 |
| `docs/self-review/66TASKLIGHT_REVIEW_MATRIX.md` | 状态准确性矩阵 |
| `docs/self-review/66TASKLIGHT_FAILURE_TAXONOMY.md` | false blue/green、stale writer、privacy 等分类 |

## 测试命令证据

- `./script/check_all.sh`：失败，P0-1；没有保存 raw log body
- `python3 -m py_compile ...`：通过
- `cd mac/66TaskLight && swift build`：通过
- `cd mac/66TaskLight && swift run TaskLightChecks`：通过，10 tests
- `./script/check_state_projector.sh`：`STATUS=ok`、writer ok、fresh
- `./script/check_codex_quota.sh`：`STATUS=ok`、AppServer source
- `./script/check_codex_quota_watcher_launch_agent.sh`：`STATUS=ok`
- `./script/check_hook_bridge_launch_agent.sh`：进程/信号存在，但 semantic `STATUS=stale`
- `./script/check_codex_workspaces_coverage.sh --skip-appserver`：`needs_hooks`、41/35/6/0
- `./script/check_codex_hooks_trust.sh`：`probe_unavailable`
- 状态仲裁、交互回放、菜单栏、雷达、完整面板、视觉矩阵、quota、Hooks Doctor、Focus、provider、Widget snapshot、自审 smoke：单项通过；具体清单见 `test-results.json`

## 当前运行态摘要

- `ui_state.global_status=running`、`lamp_status=running`
- managed active/running：2
- blocked：0；pending verify：0
- quota source：`codex_appserver`
- quota fresh：true；short 77；long 69；effective 69
- reset available：3；next precise expiry：2026-07-18 08:28:29 +08:00
- UI quota 与 `quota_state.json` 对比：match=true
- normalized signal source counts：codex_appserver 146、codex_hook 1390、codex_private_probe 73、current_thread_watcher 71、explicit 1826、hook_bridge 1494

## 性能证据

- `~/.66tasklight/render_telemetry.jsonl`：1,590 records；p50 49.95ms；p95 72.71ms；max 4,323.51ms
- `~/.66tasklight/menu_bar_self_test.json`：status ok；task radar total 51.28ms；menu open apply 303.44ms
- `~/.66tasklight/visual_matrix_self_test.json`：status ok；open apply 115.91ms
- `~/.66tasklight/expanded_panel_self_test.json`：status ok；visible apply 507.67ms
- `~/.66tasklight/edge_toggle_self_test.json`：status ok；transition 60ms
- `~/.66tasklight/interaction_event_replay_self_test.json`：status ok；single tap collapse、double tap diagnostics、drag no toggle 均为 true

## 数据容量证据

- tasks：10,301 files / 40MB
- turn bindings：2,784 files / 11MB
- observations：19 files / 76KB
- events：23MB
- ui event flow：3.0MB
- normalized signals：4.0MB
- ui clients：957 files / 3.7MB

## 审计限制

- 本轮没有人工重复操作真实菜单、滚动视觉矩阵和拖动胶囊的视频级验收，因此 smoke 通过不等价于所有真实机器负载下无卡顿。
- `check_codex_hooks_trust` 因 probe unavailable 未能独立验证全部 workspace 的实时 Trust 状态。
- 报告不保存 raw logs、prompt、response、auth 或任何 secret body。
