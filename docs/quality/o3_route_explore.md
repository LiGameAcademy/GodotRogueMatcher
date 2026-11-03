# O3 自然取得探索批

2026-11-03。Refs #122。正常池 Greedy 扫描；**不预装**发动机；未取得局保留；不定达标线。

## 身份

| 项 | 值 |
| --- | --- |
| Godot | 4.7.2 `ed1daf0bf` |
| 规则 / 抽选 | `run-commands-v46-unified-offer-audit` / `offer-unified-trial-v2` |
| 工具 | `tools/o3_builds/route_explore.gd` / `route_explore_cli.gd` |
| 守卫 | `tests/rules/test_o3_route_explore.gd`（每路线最多扫 3、目标 1） |
| 策略 | Greedy，阶段模式，行动上限 80 |
| 预算 | 每路线目标 30 个取得父局，扫描上限 100，先到停 |
| 取得定义 | 本局 `SkillAcquired` 命中该路线任一 `engines` 技能 |
| 证据 | [route-explore-summary.json](../evidence/issue122_explore/route-explore-summary.json) |

种子起点 13000；路线间种子区间错开 `max_scan`，避免共用父局。失败仅计 `rule_error`；取得率是观察事实，不是通过线。

## 本机全量结果

CLI：`--target=30 --max-scan=100 --seed=13000 --moves=80`，约 10 分钟，`failures=0`。六路线均 `target_reached`，无覆盖缺口。

| 路线 | 扫描局 | 取得父局 | 观察取得率 | 停止 |
| --- | --- | --- | --- | --- |
| B1 | 54 | 30 | 0.556 | target_reached |
| L1 | 67 | 30 | 0.448 | target_reached |
| B2 | 59 | 30 | 0.508 | target_reached |
| L2 | 73 | 30 | 0.411 | target_reached |
| M1 | 36 | 30 | 0.833 | target_reached |
| M2 | 35 | 30 | 0.857 | target_reached |

M1/M2 发动机集合更大（多供给源），观察率偏高属预期，不能写成混搭自然成型率。未跑首次作用窗 / H=10 / 成长 3 奖励窗；完整机会率仍受 `all_ability_attempts=false` 限制。

## 复现

```powershell
$env:APPDATA = Join-Path (Get-Location) '.godot/o3-sandbox'
$env:O3_EVIDENCE_DIR = Join-Path (Get-Location) '.godot/o3-explore-rerun'
& 'D:/GameMaker/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe' --headless --path . -s tools/o3_builds/route_explore_cli.gd -- --target=30 --max-scan=100 --seed=13000 --moves=80
```

守卫：

```powershell
& $godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/rules/test_o3_route_explore.gd -gexit
```

## 出口

探索批父局样本已齐（每路线 30）。不关闭 #122；不定正式门槛；不宣称路线验收通过。下一步：在取得父局上挂首次作用/持续/成长观察窗，或先核定埋点缺口后再报机会率。
