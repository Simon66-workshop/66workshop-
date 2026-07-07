# LuckyCat Capsule Drag Smoothness Fix

## 结论

上一轮修复已解决漂移，但胶囊态拖动仍有卡顿。根因不是坐标错误，而是拖动与切换热路径里仍存在不必要的重绘、动画和同步文件写入。

## 修复方式

- 拖动同尺寸窗口时改用 `setFrameOrigin`，避免每帧 `setFrame(... display: true)` 强制刷新玻璃内容。
- 胶囊态取消入场 scale/opacity 动画，避免拖动时 SwiftUI 动画抢占主线程。
- 胶囊态状态球取消持续脉冲，减少透明小窗的持续重绘。
- 切换到胶囊时移除不必要的强制 app 激活和重复 key window 操作。
- startup trace 改为后台写入，避免交互路径同步文件 IO。

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

- collapse_apply_ms: 约 2.8ms
- restore_apply_ms: 约 6.1ms
- compact_drag_pass: true
- edge_drag_pass: true
- body_click_pass: true

## 人工复测重点

- 胶囊态按住拖动：应比上一版明显更跟手，不应卡顿或跳帧明显。
- 小猫态按住拖动：应保持顺滑，不应误切胶囊。
- 短点击状态球/胶囊：仍应正常切换。
