# 66TaskLight 完整产品审计报告

## 结论先行

**Decision: REJECT**

本轮审计不能通过 MVP/发布硬门禁。原因不是主灯算法、quota 数据源或安全边界当前已出现假绿灯，而是 `./script/check_all.sh` 在当前日期下失败，命中既定硬门禁。失败定位到 `script/smoke_reliability_m38.sh` 的固定历史 `occurred_at` fixture 被 signal bus retention 清理，导致 `ids=[]` 断言失败。

当前版本可以作为本地开发/诊断工具继续使用，但不应在修复该硬门禁、处理 LaunchAgent stale 观察和性能增长风险前宣称“审计通过”或直接生产化。

## 审计元数据

- 审计时间：2026-07-13 00:00 CST 附近
- 审计范围：当前 branch 的代码、脚本、架构文档、运行态 sidecar、LaunchAgent、状态/额度 read model、菜单栏/雷达/视觉矩阵/胶囊交互
- 当前 branch：`codex/m6-m7-reliability-expansion`
- 审计基线：`3986dcd fix(tasklight): make quota snapshots authoritative`
- 审计期间：未修改核心功能代码，未修 bug，未 commit，未 push
- 工作区基线：审计开始时 clean；本轮仅新增本审计目录

## Findings

### P0：check_all 当前失败

- 证据：`./script/check_all.sh` exit 1；失败步骤为 `smoke_reliability_m38.sh`
- 直接原因：fixture 在 `script/smoke_reliability_m38.sh:39` 使用 `2026-07-10T00:00:00Z`，而 `script/tasklight_signal_bus.py:45` 默认 retention 为 172800 秒；到当前审计时间已超过保留窗口，`compact_signal_bus()` 后 `rows` 为空，`script/smoke_reliability_m38.sh:81` 触发 `AssertionError: []`
- 影响：按既定验收规则，`check_all` 失败即 REJECT；后续 check_all 阶段不会继续执行
- 当前处理：只定位和记录，未在审计模式自动修复

### P1：LaunchAgent 健康状态仍有 stale 观察

- 证据：`check_hook_bridge_launch_agent.sh` 返回进程 running、最新信号年龄为 0，但语义状态为 `STATUS=stale`
- 影响：真实运行时仍可能出现“进程存在但 bridge offset/health 判定不新鲜”的分裂，不能只看 launchctl running 就宣称 bridge 健康
- 判断：不是当前已证实的假绿灯，但属于 runtime-health residual observation，需单独收口

### P1：状态目录增长已达到会放大交互延迟的规模

- 证据：当前 `~/.66tasklight` 约有 10,301 个 task JSON、2,784 个 turn binding、40MB tasks、11MB bindings、23MB `events.jsonl`
- 代码证据：`script/state_projector.py:548-550` 仍需列出并按 mtime 排序 task 文件；Swift fallback 在 `TaskLightStore.swift:1351-1370` 扫描全部 task JSON；`TaskLightStore.swift:163-174` 的全量 `loadEvents()` 仍会读取整个 events 文件
- 影响：projector stale/missing、启动初始化或 fallback 路径下可能阻塞主线程，能够解释历史上启动慢、面板/菜单卡顿的部分现象
- 判断：当前正常 fresh projector 路径已通过异步 snapshot coordinator，但增长后的 fallback 路径仍是架构级风险

### P1：渲染 snapshot 存在超过预算的间歇性 outlier

- 证据：`render_telemetry.jsonl` 1,590 条记录，p50 约 49.95ms，p95 约 72.71ms，最大约 4,323.51ms；预算为 `TaskLightUIPerformanceBudget.renderSnapshotLoadMaxMilliseconds = 160`
- 当前自测：菜单栏/雷达/矩阵/交互 smoke 均能通过，说明不是每次必现；但 max outlier 与用户此前的几十秒卡顿历史不能忽略
- 影响：菜单、视觉矩阵、完整面板打开时可能出现偶发明显延迟，尤其在 sidecar 文件增长或状态刷新同时发生时

### P2：UI client 诊断文件没有可见保留上限

- 证据：当前 `~/.66tasklight/ui_clients` 有 957 个 JSON、约 3.7MB；`TaskLightStore.saveUIClientRecord()` 以 PID 文件写入，`check_ui_client.sh` 和 projector 会遍历目录，但未发现清理策略
- 影响：诊断扫描和目录噪音会随每次 app 进程增长，长期增加启动/巡检成本，也容易让“旧 app/多实例”诊断变得嘈杂

### P2：workspace coverage 仍不是全覆盖

- 证据：当前报告 41 个 workspace，trusted 35，missing hooks 6，invalid 0；`check_codex_workspaces_coverage.sh --skip-appserver` 为 `STATUS=needs_hooks`
- 影响：缺 hooks 的 workspace 无法稳定提供 managed turn 信号，仍可能出现观察不到任务或依赖弱 appserver 证据的情况
- 边界：不能自动 trust；本项是覆盖风险，不是允许绕过 trust 的理由

### P2：WidgetKit 仍是 scaffold，不是完整真机发布能力

- 证据：`mac/66TaskLight/WidgetKitScaffold/README.md` 明确剩余真实 Team ID/provisioning profile、安装 signed app、桌面添加验收
- 影响：WidgetKit 不能作为当前产品已完成能力计入核心 MVP 通过结论

## 已确认通过的关键面

- 主灯状态矩阵 smoke 通过：hook running、process-only、private/global-only、appserver unknown/notLoaded、active-like、permission blocked、stop pending、verify done、old writer、multiple projector
- quota 当前为 `codex_appserver`、fresh=true；UI read model 与 `quota_state.json` 的 short/long/effective 值一致；quota 不改变 global/lamp status
- reset credits 仅保存 normalized status/issued/expires/redeemed；当前可用 3 次，下一次精确到期时间存在；不执行 reset/redeem
- `swift build`、`swift run TaskLightChecks`、Python `py_compile` 通过
- 胶囊切换、状态球交互回放、菜单栏、雷达、完整面板、视觉矩阵、Focus、Hooks Doctor、Widget snapshot、provider adapter 等单项 smoke 通过
- 静态审查未发现生产代码读取 `~/.codex/auth.json`、输出 auth/token、外部 API provider 默认联网或自动 trust 的路径

## 3 天真实试运行判断

**当前不建议进入正式 3 天真实试运行。**

若只做内部开发观察，可在人工监控下短时运行；正式试运行前至少需要：

1. 修复 `smoke_reliability_m38` 的时间冻结/retention 设计并让 `check_all` 真正通过。
2. 解释并消除 hook bridge `STATUS=stale`，或将其明确降为可诊断的非阻塞状态并补证据。
3. 对 10k+ task 文件和 20MB+ event 日志做 bounded retention/索引/异步 fallback 验证。
4. 重新做一次真实 app 菜单、矩阵、完整面板滚动和胶囊拖动验收，不只跑 smoke。

## 审计评分

详见 `mvp-acceptance-scorecard.md`。当前得分 **87 / 100**，但硬门禁优先，结论仍为 **REJECT**。

## 给 ChatGPT 的复核请求

请重点复核以下四点，而不是只看单项 smoke 的绿色结果：

1. `smoke_reliability_m38` 是否应改为动态时间/隔离 retention fixture，使 `check_all` 在任意日期稳定通过。
2. Hook Bridge 在“进程 running + 最新信号新鲜 + semantic STATUS=stale”时，应该判为 stale、warning 还是 check script bug；需要哪组连续证据才能关闭。
3. 10,301 task 文件、23MB events 和 4.3s render 长尾是否足以升级为 M7.1 性能 P1，先做 retention/index/fallback，再继续扩功能。
4. 当前 AppServer quota 与 `ui_state` sidecar 已匹配，但 `check_codex_hooks_trust` probe unavailable；是否应保持 NEEDS_HUMAN_REVIEW，不能把覆盖报告直接当成实时 Trust 证明。
