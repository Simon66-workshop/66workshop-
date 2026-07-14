# MVP 验收评分卡

## 总分

**87 / 100**

**Decision: REJECT**。硬门禁优先于总分；`check_all` exit 1，不能用 87 分覆盖。

| 维度 | 权重 | 得分 | 判断 |
|---|---:|---:|---|
| 功能完整度 | 20 | 18 | 主灯、Hook Bridge、Projector、quota、菜单栏、雷达、Doctor、回放、Focus、矩阵均有实现；WidgetKit 仍为 scaffold，Provider 仍为 disabled placeholder |
| 状态准确性 | 25 | 22 | 状态矩阵和仲裁 smoke 全通过；当前 live state 没有观察到 weak signal 假绿灯；仍需保留 appserver/bridge stale 观察 |
| 稳定性 | 15 | 9 | projector/quota 当前 healthy，但 hook bridge semantic stale、状态目录过大、render max 4.3s、check_all 硬门禁失败 |
| 测试覆盖 | 15 | 14 | 单项 smoke 覆盖很广，Swift 10 tests 通过；总门禁失败且真实人工滚动/卡顿证据仍不能由 smoke 完全替代 |
| 安全边界 | 10 | 10 | 未发现 auth 读取、secret 输出、默认外联、auto trust、auto purchase/reset；quota 仍不影响主灯 |
| 可解释性诊断 | 10 | 9 | writer、signal、runtime candidate、quota、Hooks Doctor、24h replay、reset expiry 诊断齐全；bridge stale 和 probe unavailable 仍需更清晰闭环 |
| 报告质量 | 5 | 5 | 本轮输出 summary、JSON、scorecard、bug、risk、evidence 五类审计材料 |
| **合计** | **100** | **87** | **硬门禁 REJECT** |

## 硬门禁判定

| 门禁 | 结果 | 证据 |
|---|---|---|
| 假绿灯 | 未在本轮 live snapshot 观察到 | state accuracy smokes + 当前 `ui_state` |
| 读取 auth/secret | 未发现 | 静态边界搜索 + provider/widget smokes |
| process-only 点亮 RUNNING | 通过防守 | runtime arbiter smoke |
| quota 改变主灯 | 通过防守 | Swift tests + quota smokes + live sidecar 对比 |
| `check_all` 通过 | **失败** | `smoke_reliability_m38` assertion `[]` |
| 关键报告可生成 | 通过 | 本目录审计包已生成 |

## 验收结论

- 当前代码不是“全部有 bug”；状态真值、quota sidecar 一致性、安全边界和单项测试面总体较强。
- 但当前版本仍不能宣称 MVP 通过，因为 `check_all` hard gate 失败，且运行态还有 stale/性能容量风险。
- 结论只能是 `REJECT`，不是 `CONDITIONAL_PASS`。
