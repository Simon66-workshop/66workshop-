# Risk Register

| ID | 风险描述 | 严重级别 | 证据 | 影响 | 建议修复 | 是否阻塞 MVP |
|---|---|---|---|---|---|---|
| R-001 | 总验收 smoke 使用固定历史时间，受 signal retention 影响 | P0 | `smoke_reliability_m38.sh:39,75-81`; `check_all.sh:14` | check_all 失败，发布门禁永远不稳定 | 使用动态时间或隔离 retention fixture，并复跑完整 check_all | 是 |
| R-002 | Hook Bridge 进程存在但 semantic status stale | P1 | `check_hook_bridge_launch_agent.sh`：running + latest signal age 0 + STATUS stale | runtime health 解释分裂，可能延迟发现桥接异常 | 对 heartbeat/offset/stale 判定做连续时序审计 | 是，正式试运行前 |
| R-003 | task/event/binding 数据持续增长 | P1 | tasks 40MB/10,301，bindings 11MB/2,784，events 23MB | fallback 和启动路径可能阻塞，放大 UI 卡顿 | bounded retention、归档、索引、尾读、异步 fallback | 生产化阻塞 |
| R-004 | render snapshot 存在 4.3s 长尾 | P1 | telemetry 1,590 条，max 4,323.51ms，预算 160ms | 菜单/矩阵/面板偶发卡顿 | 分段 telemetry + 大状态 fixture + repeated interaction replay | 交互承诺阻塞 |
| R-005 | UI client 目录无界增长 | P2 | 957 files / 3.7MB；无清理路径 | 诊断扫描变慢，旧实例噪音增多 | 保留最近 N 条并清理死亡 PID | 否 |
| R-006 | 6 个 workspace 缺 hooks | P2 | coverage 41 total / 35 trusted / 6 missing | 对应 workspace 的 managed 状态可能缺失 | 用户确认后安装，手动 Trust，重跑 coverage | 局部阻塞 |
| R-007 | trust probe unavailable | P2 | check exit 1 / probe_unavailable | 无法独立证明实时 Trust | 保持 human review 标记，不推断为 trusted | 否 |
| R-008 | WidgetKit 还未真机签名和桌面添加 | P2 | WidgetKitScaffold README remaining items | 不能宣称 Widget production-ready | 独立完成 Team ID/App Group/桌面验收 | 否 |
| R-009 | 多个 UI 大文件承载窗口、I/O、presentation | P3 | ViewModel 1,932 行；Panel 2,246 行；Radar 925 行 | 未来修 bug 容易扩大回归面 | 继续模块化，但不与新业务线混做 | 否 |

## 安全边界判断

- 未读取 `~/.codex/auth.json`。
- 未输出 prompt、response、token、auth 或 raw log body。
- 未调用外部 API；Codex quota 只验证现有本地 AppServer/read-model 路径。
- 未自动 trust hooks，未自动购买 credits，未自动 reset quota。
- quota 当前与 UI sidecar 一致，且没有进入主灯聚合路径。
