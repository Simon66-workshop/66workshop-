# Bug List

## P0

### P0-1 `check_all` 被历史日期 fixture 触发失败

- **类别**：hard gate / test reliability
- **证据**：`script/check_all.sh:14` 调用 `script/smoke_reliability_m38.sh`；fixture `occurred_at=2026-07-10T00:00:00Z` 位于 `script/smoke_reliability_m38.sh:39`；默认 signal retention 为 172800 秒；`script/smoke_reliability_m38.sh:81` 得到空 `ids`
- **影响**：任何超过 fixture 保留窗口的日期都会使总验收失败，当前直接造成 REJECT
- **建议**：让 smoke fixture 使用当前时间，或在测试中显式关闭/隔离 retention，同时增加“压缩后仍保留本测试事件”的明确断言
- **是否阻塞 MVP**：是

## P1

### P1-1 Hook Bridge semantic status stale

- **类别**：LaunchAgent / runtime health
- **证据**：`check_hook_bridge_launch_agent.sh` 当前进程 running、latest signal age 0，但最终 `STATUS=stale`
- **影响**：进程存在不代表 bridge read/write health 新鲜；可能造成 UI 与 bridge health 解释不一致
- **建议**：审查 health heartbeat、offset 更新和 stale 判定的时间基准；加入连续观测 smoke，而不是只测一次 launchctl
- **是否阻塞 MVP**：当前与 P0 叠加阻塞；单独属于试运行前必须处理的 P1

### P1-2 状态数据增长导致 fallback/启动路径存在明显性能风险

- **类别**：performance / storage lifecycle
- **证据**：10,301 task JSON、2,784 binding JSON、40MB tasks、23MB events；Swift fallback 全量扫描 task，`loadEvents()` 全量读取 events
- **影响**：projector stale/missing 时，主线程 fallback 可能变慢；与此前启动慢、菜单和完整面板卡顿历史相吻合
- **建议**：为 tasks/bindings/events/ui_clients 增加保留与归档；fallback 只读 bounded tail/index；把启动首次 read model 完全移出 main actor
- **是否阻塞 MVP**：阻塞正式生产化，内部观察可继续

### P1-3 Render snapshot 存在超预算长尾

- **类别**：UI responsiveness
- **证据**：render telemetry p95 72.71ms，但 max 4,323.51ms；预算 160ms；当前 visual matrix self-test 115.91ms 不能覆盖长尾
- **影响**：偶发菜单、视觉矩阵、完整面板明显卡住；单项 smoke 通过不能证明真实高负载下毫秒级交互
- **建议**：把 snapshot load 分段 telemetry 化，定位 I/O、JSON decode、SwiftUI construction 和 main apply 的最长阶段；加真实大状态目录 fixture 和 repeated open/scroll 回放
- **是否阻塞 MVP**：阻塞“交互无明显卡顿”的产品承诺；不改变状态算法

## P2

### P2-1 UI client 诊断文件无清理策略

- **证据**：957 个 `ui_clients/*.json`，约 3.7MB；写入按 PID 文件，检查和 projector 遍历目录
- **影响**：长期运行后诊断目录膨胀，增加扫描成本和旧实例噪音
- **建议**：按 PID 存活性和时间做 bounded cleanup，保留最近 N 条；将 cleanup 从主线程和主灯路径隔离
- **是否阻塞 MVP**：否；阻塞长期稳定性

### P2-2 workspace hooks coverage 尚未完整

- **证据**：41 个 workspace 中 6 个 missing hooks，0 invalid；overall `needs_hooks`
- **影响**：这些 workspace 无法稳定产生 managed turn 信号，可能回退到观察/诊断而非准确 task 状态
- **建议**：只在用户确认后分批安装；安装后提醒手动 Trust；不要自动 trust
- **是否阻塞 MVP**：对未覆盖 workspace 是；对已有 trusted preferred workspace 否

### P2-3 Hooks trust probe 当前不可用

- **证据**：`check_codex_hooks_trust.sh` exit 1 / `STATUS=probe_unavailable`
- **影响**：本轮不能独立证明所有 workspace 的实时 trust 状态
- **建议**：保留 NEEDS_HUMAN_REVIEW 标记，区分“探针不可用”与“未 Trust”，不要把不可用当成 trusted
- **是否阻塞 MVP**：否，但阻塞完整覆盖审计结论

### P2-4 WidgetKit 尚未完成真机签名和桌面验收

- **证据**：`WidgetKitScaffold/README.md` 明确 Team ID/provisioning profile 和桌面添加仍待完成
- **影响**：Widget 只能算 scaffold/开发能力，不能算 production-ready
- **建议**：单独走签名、App Group、安装、桌面添加和时间线刷新验收
- **是否阻塞 MVP**：否，Widget 不属于当前核心灯/胶囊 MVP

## P3

### P3-1 核心 UI 文件仍偏大

- **证据**：`TaskLightViewModel.swift` 1,932 行、`TaskLightPanelController.swift` 2,246 行、`TaskRadarPopoverView.swift` 925 行、`LuckyCatExpandedDashboardView.swift` 1,129 行
- **影响**：后续继续扩展时容易把 presentation、I/O、交互和窗口管理耦合回去
- **建议**：继续拆 presentation adapters、window actions、radar sections 和 glass primitives；只做结构重构，不混入视觉大改
- **是否阻塞 MVP**：否
