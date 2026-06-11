# Acceptance Checklist｜LuckyCat UI

Run after Codex implementation.

```bash
./script/check_all.sh
./script/build_and_run.sh --verify
```

Manual UI checks:

- [ ] No tasks: compact title is `IDLE`.
- [ ] Running or done_unverified task: compact title is `RUNNING`.
- [ ] Observed active thread with no managed active task: compact title is `RUNNING`.
- [ ] Blocked or stale task: compact title is `BLOCKED`.
- [ ] Only verified completion remains: compact title is `DONE`.
- [ ] Compact panel is LuckyCat style.
- [ ] Subtitle shows `M{managed_count} · O{observed_count}`.
- [ ] Five paw chips show 阻塞 / 运行 / 完成 / 待验 / 观察.
- [ ] `done_unverified` displays amber/pending but global remains blue.
- [ ] `done_verified` is the only green completed state.
- [ ] `observed_active` is blue/cyan display-only.
- [ ] Observed thread disappearance is silent.
- [ ] Managed blocked still plays red sound once.
- [ ] Managed done_verified still plays green sound once.
- [ ] Existing CLI smoke tests still pass.
