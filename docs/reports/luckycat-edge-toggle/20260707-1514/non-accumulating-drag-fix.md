# LuckyCat Drag Drift Fix

## 结论

本轮修复针对“小猫态和胶囊态拖动时乱漂移”。根因是拖动路径仍使用上一帧到当前帧的增量移动，并从全局鼠标位置读取当前点。透明浮窗、屏幕坐标转换或多屏环境中，这种写法容易把坐标误差逐帧累积，表现为拖动漂移、回弹或窗口乱跑。

## 修复方式

- 小猫态和胶囊态统一使用非累积拖动模型。
- 鼠标按下时记录窗口初始 frame。
- 每个 dragged 事件从 panel event 转成 screen point。
- 每次移动都按 `startFrame + totalMouseDelta` 直接计算窗口目标位置。
- mouse polling fallback 也改为使用同一套非累积 frame 应用方式。
- 保留点击/拖动分离：短点击切换，小幅移动以下不拖动，长按不触发切换。

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

- collapse_apply_ms: 约 34ms
- restore_apply_ms: 约 34ms
- transition_duration_ms: 100ms
- compact_drag_pass: true
- edge_drag_pass: true
- body_click_pass: true
- click_path_collapsed: true

## 人工复测重点

- 小猫态按住拖动：应跟手，不应自动切胶囊。
- 胶囊态按住拖动：应自由移动，不应吸回右侧，不应乱飘。
- 小猫态短点击状态球：应切换胶囊。
- 胶囊态短点击：应恢复小猫。
