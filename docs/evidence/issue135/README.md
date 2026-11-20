# #135首片证据 · 2026-10-20

基线`36ffe5b`（#166已合并），实现`e8bf0b3`，规则版本v36。对应[接入检查与未交付边界](../../quality/issue135_composite_boundaries.md)。Godot4.7.2 / Compatibility / GUT9.6.0，独立APPDATA沙箱。

| 运行 | 结果 |
| --- | --- |
| 初版RED | 原实现下B01/B02及嵌套抽样失败；测试读取第4个结果还引发下标错误，保留red-output.log，不作为纯规则失败统计 |
| 长度保护后的RED | 3项全部失败，18/30断言通过，0.054秒，见red2-output.log |
| 加异常夹具时的无效定向 | 新脚本类型错误被GUT跳过，剩余4脚本17项虽通过，但不是完整成功；targeted-output.log保留解析错误和跳过警告 |
| 初轮定向 | 5脚本22/22测试、122断言，0.094秒，退出0，boundary-final-output.log |
| 首次全量 | 81脚本585/586通过，22469/22472断言，285.223秒、退出1；双批转化夹具依赖隐式重选，见first-full-output.log |
| 转化修正定向 | 6脚本31/31测试、544断言，0.783秒，退出0，conversion-output.log |
| 最终全量 | 81脚本、587/587测试、22477断言，518.065秒、退出0，无脚本解析错误，full-output.log |
| 新v36局 | seed133000、greedy、上限65；44行动、714分、3次选卡、满盘结束，新记录落盘读回OK、退出0 |
| v36独立复放 | 415条记录逐项通过，error为空，退出0，replay-output.log |
| v35拒绝 | #165归档返回record_version_mismatch、checked_records=0、退出1，符合版本边界，old-replay-output.log |

新v36原始落盘记录归档为bot-record.jsonl，可独立复核。完整回归以full-output.log、full-engine.log和script-results.json为准。原始日志保留ANSI、系统根证书及引擎资源提示，不把测试通过称为输出零错误。

line-counts.json覆盖本片修改代码，全部≤500物理行。manifest记录机器文件字节数与SHA256，不包含README、manifest和.gitattributes自身；仅原始.log排除空白格式检查以保留原字节。

## 复现

在实际游戏仓库使用PowerShell，运行前设置独立APPDATA。完整回归：

```powershell
$env:APPDATA = Join-Path (Get-Location) '.godot/issue135/reproduce-sandbox'
& 'D:/GameMaker/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --fixed-fps 60 -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
```

定向将目录参数替换为`-gtest=res://tests/rules/test_special_conversion.gd,res://tests/rules/test_composite_boundaries.gd,res://tests/rules/test_ability_composite_effects.gd,res://tests/rules/test_composite_preview.gd,res://tests/rules/test_composite_score_events.gd,res://tests/rules/test_composite_empty_dye.gd`。

```powershell
& 'D:/GameMaker/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe' --headless --text-driver Dummy --path . -s tools/bot_testing/batch_cli.gd -- replay res://docs/evidence/issue135/bot-record.jsonl
& 'D:/GameMaker/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe' --headless --text-driver Dummy --path . -s tools/bot_testing/batch_cli.gd -- --count=1 --seed=133000 --moves=65 --strategy=greedy --output=res://.godot/issue135/reproduce-bot --record-output=res://.godot/issue135/reproduce-bot/records --telemetry-output=res://.godot/issue135/reproduce-bot/telemetry --commit=e8bf0b3
```

B01/B02为规则层自定义测试组合；本证据不代表其正式卡入池、专项场景/存档或完整S/T已验收。实际Catalog的场景/命令/回放由既有回归覆盖，完整#135与#136出口仍另行跟踪。没有执行编辑器人工试玩或Web导出。
