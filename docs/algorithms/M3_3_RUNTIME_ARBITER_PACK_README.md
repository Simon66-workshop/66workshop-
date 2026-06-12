# 66TaskLight M3.3｜Turn Runtime Arbiter Pack

这个包用于把“多线程状态不稳定”的解决算法迁移到 66TaskLight 项目，让 Codex 直接读取完整工程任务词和算法参数，避免口头转述错漏。

## 包内容

```text
codex/M3_3_Turn_Runtime_Arbiter_Codex_Prompt.md
algorithms/TURN_RUNTIME_ARBITER.md
algorithms/SIGNAL_CONFIDENCE_MATRIX.md
algorithms/RUNTIME_SCORE_FORMULA.md
algorithms/UI_STATE_SCHEMA.md
algorithms/PROJECTOR_WRITER_IDENTITY_GUARD.md
algorithms/OBSERVED_ACTIVE_POLICY.md
algorithms/STATE_PRECEDENCE.md
params/runtime_confidence.json
params/runtime_ttl.json
params/ui_state_schema.json
params/display_scope_rules.json
smoke/SMOKE_TEST_MATRIX.md
scripts/install_m3_3_runtime_arbiter_pack.sh
scripts/verify_m3_3_runtime_arbiter_pack.sh
scripts/print_codex_context.sh
```

## 目标

让 `state_projector.py` 从普通投影器升级为：

```text
Signal Reader
+ Turn Runtime Arbiter
+ UI Projector
```

核心纪律：

```text
强信号主导
弱信号只辅助
所有信号统一评分
旧 projector 写入必须能被发现
LuckyCat 永远只读最终裁判结果 ui_state.json
```

## 安全边界

- 不调用外部 API
- 不读 `~/.codex/auth.json`
- 不输出 prompt / response / auth / raw log body
- 不自动 commit
- 不 push
- 安装脚本只复制文档、任务词、参数，不修改运行代码

