# O3 取得后观察窗

2026-11-04。Refs #122。在自然取得父局上记录 startup / sustain / upgrade 事实；`pass_line=null`；`synergy` 因机会埋点缺口保持 null。

## 身份

| 项 | 值 |
| --- | --- |
| Godot | 4.7.2 `ed1daf0bf` |
| 工具 | `tools/o3_builds/route_observe.gd` / `route_observe_cli.gd` |
| 守卫 | `tests/rules/test_o3_route_observe.gd` |
| 种子 / 预算 | 与探索批同：`13000` 起，目标 30 / 上限 100 |
| 行动上限 | 基线 120；`--complete-windows` 默认取得后预算 240、预取得天花板 300、`timeout_ms=180s`，三窗决议后早停 |
| 证据 | [route-observe-summary.json](../evidence/issue122_observe/route-observe-summary.json)、[route-observe-complete.json](../evidence/issue122_observe/route-observe-complete.json) |

有效作用：对应路线 cause 且 `removed>0`（空爆/空扫不算）。等待按取得后的玩家行动（move/detonate/activate_line）计；取得当次结算即时有效记 0。成长窗看取得后接下来 3 次 `Offer` 是否出现/选中该路线 `growth`。截尾未满窗不进分母充数。

## 本机结果（观察事实，非正式门槛）

### 基线批（moves=120）

CLI：`--target=30 --max-scan=100 --seed=13000 --moves=120`，`failures=0`。六路线均满 30 取得父局。

| 路线 | startup≤4 | startup≤8 | sustain≤10 | upgrade offered/3 | upgrade taken/3 |
| --- | --- | --- | --- | --- | --- |
| B1 | 3/30 | 7/30 | 3/16 | 1/1 | 0/1 |
| L1 | 5/29 | 7/29 | 6/16 | 4/5 | 0/5 |
| B2 | 5/29 | 5/29 | 2/10 | 0/3 | 0/3 |
| L2 | 2/30 | 5/30 | 10/17 | 7/8 | 1/8 |
| M1 | 2/30 | 5/30 | 3/17 | 1/5 | 0/5 |
| M2 | 2/29 | 4/29 | 0/9 | 0/1 | 0/1 |

### 完整窗批（`--complete-windows`，约 7 分钟）

CLI：`--target=30 --max-scan=100 --seed=13000 --complete-windows`（默认取得后 240 步），`failures=0`。窗命中与基线批**相同**；新增 `resolved_parents` / `stop_reasons`：

| 路线 | resolved/30 | 主要 stop_reasons |
| --- | --- | --- |
| B1 | 1 | board_full 29 / windows_resolved 1 |
| L1 | 5 | board_full 25 / windows_resolved 5 |
| B2 | 3 | board_full 27 / windows_resolved 3 |
| L2 | 8 | board_full 22 / windows_resolved 8 |
| M1 | 5 | board_full 25 / windows_resolved 5 |
| M2 | 1 | board_full 29 / windows_resolved 1 |

说明：

- 分母是**完整观察窗**父局数，不是扫描局数；sustained/upgrade 分母明显小于 30，属截尾/奖励不足，记覆盖不足，不删短局凑比例。
- 加长取得后预算**未能**抬升 sustain/upgrade 分母：截尾主因是 `board_full`（局结束），不是 `move_limit` / timeout。三窗齐备的父局很少（每路线 1～8）。
- 试验参考 70%/60%/60% **未**用作通过线；本批不宣布达标或需调参结论。
- `synergy=null`；`all_ability_attempts=false` 下不报完整机会率。
- Greedy 选卡意愿不能代替真人意愿。

## 复现

```powershell
$env:APPDATA = Join-Path (Get-Location) '.godot/o3-sandbox'
$env:O3_EVIDENCE_DIR = Join-Path (Get-Location) '.godot/o3-observe-rerun'
$godot = 'D:/GameMaker/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe'
& $godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/rules/test_o3_route_observe.gd -gexit
& $godot --headless --path . -s tools/o3_builds/route_observe_cli.gd -- --target=30 --max-scan=100 --seed=13000 --moves=120
& $godot --headless --path . -s tools/o3_builds/route_observe_cli.gd -- --target=30 --max-scan=100 --seed=13000 --complete-windows
```

## 出口

取得后三窗事实已落盘；完整窗早停与结束原因直方图已补。不关闭 #122；不定正式接受线。下一步：在 `board_full` 约束下另寻覆盖策略（例如更长寿 bot 配置 / 分段观察协议），或核定埋点后补 synergy/机会率；真人片段仍外置。
