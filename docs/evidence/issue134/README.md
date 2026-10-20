# #134迁移与回归证据 · 2026-10-20

基线`91154e2`（已合并#165），实现`0123c43`，Godot`4.7.2.stable.official.ed1daf0bf` / Compatibility / GUT9.6.0。对应[迁移、保留与验收说明](../../quality/issue134_legacy_retirement.md)。

| 运行 | 实际结果 | 文件 |
| --- | --- | --- |
| 迁移前隔离RED | 4项全部失败，6/18断言通过；局部效果写全局、旧根节点仍存在 | red-output.log |
| 第一组定向回归 | 5脚本50/50，972断言，43.588秒，退出0 | targeted-output.log |
| 补充隔离/出生边界 | 2脚本8/8，49断言，0.892秒，退出0 | boundary-final-output.log |
| 完整自有回归 | 80脚本581/581，22418断言，285.006秒，退出0，无脚本解析错误 | full-output.log、full-engine.log、script-results.json |
| 新机器人局落盘读回 | seed133000，greedy，上限65；44行动、714分、成功选卡3次，满盘结束，回放OK，退出0；与#165样本相同 | bot-output.log、bot-runs.csv、bot-summary.json |
| 迁移前归档精确回放 | #165归档的415条记录在#134实现下逐项通过，error为空、退出0 | baseline-replay-output.log |
| 截图工具解析 | goal_progress_capture可实例化，退出0；没有执行截图产出 | tool-probe-output.log |

consumers-before.txt通过基线git grep记录旧调用，consumers-after.txt记录当前运行脚本/场景/资源/Autoload线索。删除的三个脚本UID在gameplay/ui/tools/tests/data及project.godot中均无引用。静态搜索不单独作为行为验收，结合完整回归、显式夹具与精确回放。

line-counts.json列改动代码物理行数（before/after，null表示新增/删除），全部现存文件≤500。manifest.json记录机器文件字节数及SHA256，不包含README、manifest及.gitattributes自身。原始日志保留ANSI、引擎证书及资源提示；仅原始.log不做空白格式检查，未改动日志字节掩盖诊断。

## 复现

在实际游戏仓库使用PowerShell，每次测试设置独立APPDATA：

```powershell
$env:APPDATA = Join-Path (Get-Location) '.godot/issue134/reproduce-sandbox'
& 'D:/GameMaker/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --fixed-fps 60 -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
```

第一组定向将目录参数替换为`-gtest=res://tests/rules/test_legacy_item_isolation.gd,res://tests/test_core_loop.gd,res://tests/integration/test_explosion_loop.gd,res://tests/integration/test_skip_recovery.gd,res://tests/integration/test_stage_scene.gd`。补充边界使用`-gtest=res://tests/rules/test_legacy_item_isolation.gd,res://tests/integration/test_refill_lifecycle.gd`。第一组在补充两条局部案例之前执行，因此统计与当前单独运行会有差异，最终完整结果包含全部案例。

```powershell
& 'D:/GameMaker/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe' --headless --text-driver Dummy --path . -s tools/bot_testing/batch_cli.gd -- replay res://docs/evidence/issue133/bot-record.jsonl
& 'D:/GameMaker/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe' --headless --text-driver Dummy --path . -s tools/bot_testing/batch_cli.gd -- --count=1 --seed=133000 --moves=65 --strategy=greedy --output=res://.godot/issue134/reproduce-bot --record-output=res://.godot/issue134/reproduce-bot/records --telemetry-output=res://.godot/issue134/reproduce-bot/telemetry --commit=0123c43
```

新局原始记录保存在本机.gitignore下的.godot/issue134/bot/records，未在本证据目录重复归档；保留新局CSV与落盘回放结果。可直接复核的归档记录沿用#165的v35文件。没有运行编辑器人工体验或Web导出，不把一局样本当成平衡/通关证据。
