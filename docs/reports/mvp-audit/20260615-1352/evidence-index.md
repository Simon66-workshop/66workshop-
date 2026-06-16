# Evidence Index

Generated: 2026-06-15T06:03:47.271Z

| Evidence | Status | Hash | Safe Summary |
| --- | --- | --- | --- |
| README.md | read | d8b76c5c5457 | State Projector is documented as read-only for task state and writes UI read-model files.; ui_state.json is the final LuckyCat read model.; Quota is display-only and must not change main lamp/status.; Safety boundary forbids auth-file reads and secret output.; Workspace hooks still require manual Codex UI trust.; Projector writer identity must detect old or multiple writers. |
| docs/STATUS_PROTOCOL.md | read | e9f0799e762e | Quota is display-only and must not change main lamp/status.; Projector writer identity must detect old or multiple writers.; Status model covers RUNNING, BLOCKED, PENDING, DONE, and IDLE. |
| docs/STATE_PROJECTOR.md | read | 474fcdc4a1e4 | State Projector is documented as read-only for task state and writes UI read-model files.; ui_state.json is the final LuckyCat read model.; Process-only evidence must not drive RUNNING.; Projector writer identity must detect old or multiple writers.; Status model covers RUNNING, BLOCKED, PENDING, DONE, and IDLE. |
| docs/HOOK_SIGNAL_BRIDGE.md | read | ec4dfdcc878c | Safety boundary forbids auth-file reads and secret output.; Status model covers RUNNING, BLOCKED, PENDING, DONE, and IDLE. |
| docs/HOOK_BRIDGE_LAUNCH_AGENT.md | read | 80993dc9247f | Status model covers RUNNING, BLOCKED, PENDING, DONE, and IDLE. |
| docs/CODEX_WORKSPACE_ONBOARDING.md | read | 9920c378593f | Safety boundary forbids auth-file reads and secret output.; Workspace hooks still require manual Codex UI trust.; Status model covers RUNNING, BLOCKED, PENDING, DONE, and IDLE. |
| docs/self-review/66TASKLIGHT_SELF_REVIEW_ENGINE.md | read | d88c0adf32c1 | Status model covers RUNNING, BLOCKED, PENDING, DONE, and IDLE. |
| docs/self-review/66TASKLIGHT_REVIEW_MATRIX.md | read | 70e6147174b1 | Process-only evidence must not drive RUNNING.; Status model covers RUNNING, BLOCKED, PENDING, DONE, and IDLE. |
| docs/self-review/66TASKLIGHT_FAILURE_TAXONOMY.md | read | 943ae49e81fe | Process-only evidence must not drive RUNNING.; Status model covers RUNNING, BLOCKED, PENDING, DONE, and IDLE. |
| docs/CODEX_QUOTA_WIDGET.md | read | 37b910def747 | Quota is display-only and must not change main lamp/status.; Status model covers RUNNING, BLOCKED, PENDING, DONE, and IDLE. |
| ./script/check_all.sh | FAIL | 0b0d453aaf04 | TaskLightChecks passed; smoke_ui_refresh_latency: ok; smoke_signal_bus: ok; smoke_state_projector: ok; smoke_codex_quota: ok; smoke_codex_quota_watcher: ok; smoke_workspace_coverage=ok; smoke_hooks_config: ok; smoke_hook_signal_bridge: ok; OK; Traceback (most recent call last):; KeyError: 'total' |
| ./script/check_state_projector.sh | PASS | 9cccbac09e1e | launchctl_status=running; ui_state_status=readable; writer_status=ok; ui_state_global_status=running; global_status=running; display_title=RUNNING; quota_captured_at=2026-06-15T14:02:29+08:00; quota_captured_age_sec=19.330672025680542; quota_state_path=/Users/macmini-simon66/.66tasklight/quota_state.json; state_projector_health_status=readable; state_projector_health_state=ok; STATUS=ok |
| ./script/check_hook_bridge_launch_agent.sh | PASS | 4ef871963285 | launchctl_status=running; hook_bridge_health_path=/Users/macmini-simon66/.66tasklight/hook_bridge_health.json; hook_bridge_health_status=readable; hook_bridge_health_state=ok; STATUS=ok |
| ./script/check_ui_client.sh | PASS | ebf34390fb3b | running_app_pid=none; STATUS=ok |
| ./script/check_codex_hooks_trust.sh | PASS | c940dfec769a | PROJECT_ROOT: ok; CODEX_DIR: ok; HOOK_CONFIG: ok; HOOK_REFERENCE: ok; HOOK_HANDLER: ok; HOOK_HEALTH: ok; CODEX_APPSERVER_HOOKS: trusted=6; PROJECT_TRUST: trusted_possible; HOOK_VISIBILITY: visible_trusted; HOOK_VISIBILITY_REASON: Codex UI 已加载这个 workspace 的 hooks，而且它们已可信; STATUS: trusted_possible; NEXT_ACTION: hooks appear trusted; trigger a new Codex turn to verify spool events |
| ./script/check_codex_workspaces_coverage.sh --skip-appserver | PASS | 92b83914dc53 | STATUS=needs_hooks; workspace_count=35; trusted=6; installed_needs_trust=0; missing_hooks=29; invalid_hooks=0; workspace=/Volumes/2T扩展盘/66_PROJECTS/66Workshop_AI_Website_V1/10_Repo/66workshop-site-v0.47-rc9 coverage_status=missing_hooks hook_status=missing reason=这个 workspace 还没安装 hooks; workspace=/Volumes/2T扩展盘/AI机器人/66-ai-perception coverage_status=missing_hooks hook_status=missing reason=这个 workspace 还没安装 hooks; workspace=/Volumes/2T扩展盘/AI机器人/66-ai-perception-cleanwork coverage_status=missing_hooks hook_status=missing reason=这个 workspace 还没安装 hooks; workspace=/Volumes/2T扩展盘/AI机器人/66-ai-perception-ui-clean coverage_status=missing_hooks hook_status=missing reason=这个 workspace 还没安装 hooks; workspace=/Volumes/2T扩展盘/AI机器人/66-ai-perception-wf-ui-only coverage_status=missing_hooks hook_status=missing reason=这个 workspace 还没安装 hooks; workspace=/Volumes/2T扩展盘/AI机器人/_local_tools/whisper.cpp coverage_status=missing_hooks hook_status=missing reason=这个 workspace 还没安装 hooks |
| ./script/check_codex_quota.sh | PASS | 86a96226ecc5 | quota_state_path=/Users/macmini-simon66/.66tasklight/quota_state.json; quota_status=watch; warnings=duplicate_quota_buckets_collapsed_to_display_windows; ui_state_quota_exists=yes; ui_state_quota_probe_mode=poll_fallback; ui_state_quota_bucket_id=codex; ui_state_quota_raw_window_count=4; STATUS=ok |
| ./script/smoke_codex_quota.sh | PASS | 029b8aadc2bd | smoke_codex_quota: ok |
| ./script/smoke_turn_runtime_arbiter.sh | PASS | e5b7a2766011 | smoke_turn_runtime_arbiter: ok |
| ./script/smoke_state_projector.sh | PASS | 29dd6c9c527f | smoke_state_projector: ok |
| ./script/smoke_hook_signal_bridge.sh | PASS | fbd63ff4f5b9 | smoke_hook_signal_bridge: ok |
| ./script/smoke_workspace_coverage.sh | PASS | 78bca90d7afa | smoke_workspace_coverage=ok |
| ./script/smoke_self_review.sh | PASS | b193e714c38f | smoke_self_review: ok |
| ./script/smoke_self_review_scope.sh | PASS | 90377b6b860e | smoke_self_review_scope: ok |
| ./script/smoke_self_review_generate_scope.sh | PASS | 99be3effeb4b | smoke_self_review_generate_scope: ok |
| ~/.66tasklight/normalized_signals.jsonl | aggregated | - | sourceCounts=7 |
