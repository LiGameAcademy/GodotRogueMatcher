# O3 B2/L2 固定因果盘

2026-11-03。Refs #122。fixture/automated 技术证据，不是自然成型、持续供给、烟测样本或路线达标。

## 身份

| 项 | 值 |
| --- | --- |
| Godot | 4.7.2 stable `ed1daf0bf`，GUT 9.6.0 |
| 规则 / 抽选 | `run-commands-v46-unified-offer-audit` / `offer-unified-trial-v2` |
| 夹具 | `tests/support/o3_chain_fixture.gd` |
| 测试 | `tests/rules/test_o3_chain_builds.gd` |
| 清单登记 | `O3BuildRoutes`：B2=`fuse_chain`，L2=`cross_pair` |

未改生产规则、Resource、抽选参数或正式池。自定义初始化 `o3_custom_b2` / `o3_custom_l2` 不在 RuleReplay 白名单；L2 另复用已支持的 `fixture_line_cross` 做磁盘回放。

## B2：引信连锁

正式命令 `DetonateCoreCommand`；引信经 `assign_fuse` 标记；`core_manual_detonation` 经 `SkillRules` 安装（计入选择次数，非伪造历史）。

| 案例 | 盘面要点 | 断言 |
| --- | --- | --- |
| 有效链 | 核心邻接已标记棋，且该棋邻域另有存活目标 | ≥2 代；后代 `removed>0`；父事件 id 相连；标记载体被移除 |
| 空爆链 | 同标记布局，无额外邻域目标 | 后代代际仍出现，但 `removed=0`——只证明规则链，不算有效兑现 |

不证明装填供给持续性、自然取得发动机、或 `marked_reward`/`fuse_relay` 成长价值。

## L2：十字扫线

| 案例 | 做法 | 断言 |
| --- | --- | --- |
| 成对对照 | 同行 2 + 列独占 2；仅升级盘安装 `line_cross_upgrade` | 基线 `cross_radius=-1`、独占命中 0、清除 2；升级盘独占 2、清除 4；并集大小 = 行命中 + 独占（无双计） |
| 现成十字夹具 | `fixture_line_cross` + `ActivateLineCommand` + 磁盘 RuleReplay | 4 段匹配可回放；不把链式混搭计作 L2 自然成型 |

边缘截断另有 `test_line_cross`；本片不重复扩写。不证明跨度成长或自然抽到十字卡。

## 验证

```powershell
$env:APPDATA = Join-Path (Get-Location) '.godot/o3-sandbox'
$env:O3_EVIDENCE_DIR = Join-Path (Get-Location) '.godot/o3-chain-rerun'
& 'D:/GameMaker/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe' --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/rules/test_o3_chain_builds.gd -gexit
```

本机：4/4、31 断言，退出 0。另复跑 `test_o3_fixed_builds` / `test_o3_build_routes` 作回归冒烟。

## 出口

正确性固定案例已覆盖 B2 有效/空爆分诊与 L2 独占轴增量。不关闭 #122；不定 70%/60% 线；不跑 10 局烟测或自然探索批。M1/M2 见 [o3_m1m2_fixed_chains.md](o3_m1m2_fixed_chains.md)。下一步另片：每路线烟测 → 自然取得扫描。
