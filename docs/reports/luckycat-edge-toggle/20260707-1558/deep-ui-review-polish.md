# LuckyCat Deep UI Review And Polish

## 结论

本轮做了代码、交互、性能和胶囊态 UI 的收敛复盘。核心状态链路、quota 数据源、Hook Bridge、State Projector、Turn Runtime Arbiter 均未改动。

## 已处理优化

### 1. 胶囊拖动热路径减负

- 发现胶囊窗口移动时会频繁刷新位置并写入持久化数据。
- 改为移动时只实时更新内存位置，磁盘写入做 240ms 防抖。
- 点击恢复和拖动结束仍立即保存，避免位置丢失。

### 2. 胶囊渲染稳定性

- 胶囊 hosting view 开启图层 rasterize，降低拖动时重复合成玻璃视图的压力。
- 胶囊 SwiftUI 根视图禁用隐式动画，避免状态刷新引起轻微跳动。

### 3. 胶囊 UI 可读性与稳定布局

- 运行/待验/观察数字改为固定宽度，减少数字变化时横向抖动。
- quota 数字固定宽度，避免剩余量变化造成视觉位移。
- 增加 hover 提示“拖动移动，点击恢复小猫”，不增加可见 UI 噪音。

### 4. 代码质量

- 清理 `swift build` 中已有的 `try? seekToEnd()` 未使用 warning。
- 回归门禁新增对防抖保存、图层缓存、禁用隐式动画的检查。

## 验证结果

- `swift build`: pass
- `script/smoke_luckycat_edge_toggle_atomic.sh`: pass
- `script/smoke_luckycat_edge_toggle_runtime.sh`: pass
- `script/check_ui_client.sh`: pass
- `script/check_all.sh`: pass

关键运行态结果：

- `compact_drag_pass=True`
- `edge_drag_pass=True`
- `restored_from_moved_edge_pass=True`
- `check_all`: pass

## 剩余观察点

- 胶囊跟手性已尽量交给 AppKit 原生拖窗处理；如果用户仍感觉个别机器/屏幕组合有轻微卡顿，下一步应考虑把胶囊从 SwiftUI material 视图降级为更轻的 AppKit/CALayer 绘制层。
- 当前工作区仍包含多轮 LuckyCat/M3.x 累计改动，提交前建议按功能分组 staged review，避免把无关报告或旧自审样本混入同一 commit。
