# LuckyCat Native Edge Drag Handoff

## 结论

胶囊态仍有轻微跟手延迟时，继续压 SwiftUI 重绘和窗口 frame 更新已经收益有限。本轮将胶囊态拖动切换为 AppKit 原生窗口拖动：一旦判断用户是在拖动而不是短点击，胶囊窗口交给系统 `performDrag` 处理，避免 SwiftUI/自定义事件循环参与每一帧移动。

## 修复方式

- 小猫态保持现有非累积拖动模型，因为人工反馈已顺滑。
- 胶囊态检测到超过拖动阈值后，调用 AppKit 原生窗口拖动。
- 保留短点击恢复小猫，不把点击误判为拖动。
- 回归检查新增约束：胶囊态必须使用原生拖窗路径。

## 未改动范围

- 未改状态灯算法。
- 未改 quota 数据源。
- 未改 Hook Bridge、State Projector、Turn Runtime Arbiter。
- 未 commit，未 push。

## 验证结果

- `swift build`: pass
- `script/smoke_luckycat_edge_toggle_atomic.sh`: pass
- `script/smoke_luckycat_edge_toggle_runtime.sh`: pass
- `script/check_ui_client.sh`: pass
- `script/check_all.sh`: pass

运行态自检结果摘要：

- click_path_collapsed: true
- compact_drag_pass: true
- edge_drag_pass: true
- restored_pass: true
- check_all: pass

## 人工复测重点

- 胶囊态按住拖动：应比手写逐帧移动更跟手。
- 胶囊态短点击：仍应恢复完整小猫。
- 小猫态拖动：应保持上一版的顺滑表现。
