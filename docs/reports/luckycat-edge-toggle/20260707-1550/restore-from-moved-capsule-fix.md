# LuckyCat Restore From Moved Capsule Fix

## 结论

胶囊态拖动已跟手，但移动到新位置后恢复小猫时会跳回旧屏幕位置。根因是恢复小猫时没有稳定使用“最新胶囊 frame”作为锚点；原生拖窗、拖动结束保存、点击恢复之间存在时序差，可能读到旧位置。

## 修复方式

- 新增 `lastKnownEdgeRailFrame`，作为胶囊最新位置的内存锚点。
- 胶囊窗口 `windowDidMove` 时实时记录位置。
- 胶囊拖动结束、程序移动、点击恢复前都刷新同一份位置。
- 恢复小猫时统一从 `currentEdgeRailFrame` 取锚点，而不是回落到旧 compact 位置。
- 运行态自检新增 `restored_from_moved_edge_pass`，验证“先移动胶囊，再恢复小猫”时位置跟随移动后的胶囊。

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

关键自检结果：

- `edge_drag_pass=True`
- `restored_pass=True`
- `restored_from_moved_edge_pass=True`
- `check_all`: pass

## 人工复测重点

- 胶囊拖到任意位置。
- 点击胶囊恢复小猫。
- 小猫应出现在移动后的胶囊附近，不应跳回移动前的旧位置。
