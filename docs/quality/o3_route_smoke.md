# O3 每路线烟测 10

2026-11-03。Refs #122。预装路线发动机后的机器人烟测；记录事实，不判达标、不做自然取得分母。

## 身份

| 项 | 值 |
| --- | --- |
| Godot | 4.7.2 `ed1daf0bf`，GUT 9.6.0 |
| 规则 | `run-commands-v46-unified-offer-audit` |
| 工具 | `tools/o3_builds/route_smoke.gd` / `route_smoke_cli.gd` |
| 测试 | `tests/rules/test_o3_route_smoke.gd` |
| 策略 | Greedy `greedy-v1`，阶段模式 `stage_config.tres` |
| 本批参数 | 每路线 10 局，种子起点 9200，行动上限 60 |

开局经正式 `ChooseSkillCommand` 预装该路线 `engines`（fixture 意图，非自然抽卡）。合成候选不在 RuleReplay 白名单承诺内；烟测门禁只看局内 `rule_error`，不做整段磁盘回放验收。

## 本机结果（不构成通过线）

`test_o3_route_smoke`：**2/2、36 断言**，约 124s。全量 60 局 `failures=0`。

| 路线 | 局数 | rule_errors | synergy_games（观察） | 主要 cause 合计 |
| --- | --- | --- | --- | --- |
| B1 | 10 | 0 | 10 | explosion 8 / match 56 |
| L1 | 10 | 0 | 10 | line_clear 67 / match 78 |
| B2 | 10 | 0 | 5 | explosion 41（含后代计数） |
| L2 | 10 | 0 | 1 | line_clear 80；`cross_events` 少见 |
| M1 | 10 | 0 | 10 | explosion+line_clear 同局 |
| M2 | 10 | 0 | 10 | 同上 |

`synergy_games` 仅观察：B2=爆破后代、L2=`cross_radius>=0`、M1/M2=同局双 cause、其余=有任意 cause。L2 十字在仅装发动机、未装 `line_cross_upgrade` 时预期偏低，不据此判失败。

## 复现

```powershell
$env:APPDATA = Join-Path (Get-Location) '.godot/o3-sandbox'
$env:O3_EVIDENCE_DIR = Join-Path (Get-Location) '.godot/o3-smoke-rerun'
& 'D:/GameMaker/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe' --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/rules/test_o3_route_smoke.gd -gexit
# 或 CLI：
& $godot --headless --path . -s tools/o3_builds/route_smoke_cli.gd -- --per-route=10 --seed=9200 --moves=60
```

## 出口

六路线各 10 局无规则异常。不关闭 #122；不定 70%/60%。自然取得探索批见 [o3_route_explore.md](o3_route_explore.md)。
