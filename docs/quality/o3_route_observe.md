# O3 取得后观察窗

2026-11-04。Refs #122。在自然取得父局上记录 startup / sustain / upgrade 事实；`pass_line=null`；`synergy` 因机会埋点缺口保持 null。

## 身份

| 项 | 值 |
| --- | --- |
| Godot | 4.7.2 `ed1daf0bf` |
| 工具 | `tools/o3_builds/route_observe.gd` / `route_observe_cli.gd` |
| 守卫 | `tests/rules/test_o3_route_observe.gd` |
| 种子 / 预算 | 与探索批同：`13000` 起；取得目标 30 / 上限 100；完整窗齐备目标见下 |
| 行动上限 | 基线 120；`--complete-windows` / `--target-resolved` 默认取得后预算 240、预取得天花板 300、`timeout_ms=180s`，三窗决议后早停 |
| 证据 | [route-observe-summary.json](../evidence/issue122_observe/route-observe-summary.json)、[route-observe-complete.json](../evidence/issue122_observe/route-observe-complete.json)、[route-observe-resolved.json](../evidence/issue122_observe/route-observe-resolved.json) |

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

### 完整窗批（`--complete-windows`）

CLI：`--target=30 --max-scan=100 --seed=13000 --complete-windows`，`failures=0`。窗命中与基线批**相同**。截尾主因 `board_full`，不是 move_limit；三窗齐备仅 1～8/30。

### 齐备父局覆盖批（`--target-resolved`，约 19 分钟）

应对 `board_full`：继续扫描直到凑够三窗齐备父局（默认目标 10 / 上限 300），窗比率只在 **resolved_parents** 上计——条件化于活到齐备，**不是**全体自然取得率。

CLI：`--target-resolved --target=10 --max-scan=300 --seed=13000`，`failures=0`。

| 路线 | 扫描 | 取得 | 齐备 | stop | startup≤4 | startup≤8 | sustain≤10 | upgrade offered/3 | upgrade taken/3 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| B1 | 300 | 137 | 9 | scan_cap（缺 1） | 2/9 | 5/9 | 1/8 | 6/9 | 5/9 |
| L1 | 87 | 38 | 10 | target_reached | 0/10 | 1/10 | 8/10 | 5/10 | 1/10 |
| B2 | 119 | 78 | 10 | target_reached | 0/10 | 2/10 | 3/9 | 5/10 | 0/10 |
| L2 | 123 | 44 | 10 | target_reached | 0/10 | 1/10 | 5/10 | 9/10 | 0/10 |
| M1 | 124 | 95 | 10 | target_reached | 1/10 | 3/10 | 7/10 | 7/10 | 2/10 |
| M2 | 78 | 66 | 10 | target_reached | 1/10 | 2/10 | 4/10 | 2/10 | 2/10 |

说明：

- 分母是**完整观察窗**父局数（resolved 模式下即齐备样本），不删短局凑比例。
- B1 在 300 扫描内只凑到 9 齐备，记覆盖缺口；其余五路线满 10。
- 试验参考 70%/60%/60% **未**用作通过线；条件化样本不宣布自然达标。
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
& $godot --headless --path . -s tools/o3_builds/route_observe_cli.gd -- --target-resolved --target=10 --max-scan=300 --seed=13000
```

## 出口

取得后三窗事实、完整窗早停、以及 board_full 下的齐备父局覆盖采样均已落盘。#122 已按 [o3_kr1_soft_closeout.md](o3_kr1_soft_closeout.md) 降范围关闭；不定正式接受线。下一步归 #123/#124：核定埋点后补 synergy/机会率，或开 H=20 成对主窗；真人片段仍外置。
