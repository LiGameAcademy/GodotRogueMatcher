# O3 M1/M2 固定因果盘

2026-11-03。Refs #122。fixture/automated，不是自然混搭成型、布局策略样本或路线达标。B2/L2 见 [o3_b2l2_fixed_chains.md](o3_b2l2_fixed_chains.md)。

## 身份

| 项 | 值 |
| --- | --- |
| Godot | 4.7.2 stable `ed1daf0bf`，GUT 9.6.0 |
| 规则 / 抽选 | `run-commands-v46-unified-offer-audit` / `offer-unified-trial-v2` |
| 夹具 | `tests/support/o3_chain_fixture.gd`（`blast_starts_line` / `line_starts_blast`） |
| 测试 | `tests/rules/test_o3_chain_builds.gd`（M1/M2 四例） |
| 清单 | M1=`blast_starts_line`，M2=`line_starts_blast` |

自定义初始化不在 RuleReplay 白名单。载体由夹具预置；仅主动卡经 `SkillRules` 安装并记 `choices_consumed=1`，不伪造自然取得史。

## M1：爆破 → 扫线

正式命令 `DetonateCoreCommand`；安装 `core_manual_detonation`。

| 案例 | 盘面 | 断言 |
| --- | --- | --- |
| 命中扫线手 | 核心邻接行轴扫线手，同行另有 2 枚目标 | 出现 `line_clear`；`sweep_hits=2`；选择消耗 1 |
| 未命中 | 扫线手在爆破半径外，邻格仅普通棋 | 无 `line_clear`；不把同盘持有两系当成协同 |

不证明扫线供给持续性，也不把主动引爆成本外推为自然局唯一成本。

## M2：扫线 → 爆破

正式命令 `ActivateLineCommand`；安装 `line_manual_clear`。爆破邻域目标刻意不放在被扫行上，避免被行清除先吃掉。

| 案例 | 盘面 | 断言 |
| --- | --- | --- |
| 有效链 | 行轴扫到核心，上下邻格各 1 枚 | 有 `line_clear`；爆破命中 2；选择消耗 1 |
| 空爆链 | 同行扫到核心，无额外邻域 | 仍有爆破代际，但 `blast_removed=0`——规则链 ≠ 有效兑现 |

不证明引信装填/传递，也不估计提前消耗布局的自然频率。

## 验证

```powershell
$env:APPDATA = Join-Path (Get-Location) '.godot/o3-sandbox'
$env:O3_EVIDENCE_DIR = Join-Path (Get-Location) '.godot/o3-chain-rerun'
& 'D:/GameMaker/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe' --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/rules/test_o3_chain_builds.gd -gexit
```

本机整文件：8/8、54 断言，退出 0。

## 出口

六路线正确性固定案例已齐（B1 partial / L1 / B2 / L2 / M1 / M2）。不关闭 #122；下一步另片：每路线烟测 10 → 自然取得探索批。
