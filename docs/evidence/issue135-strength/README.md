# #135第二片证据 · 2026-10-20

父片#167/1749dfb，实现b0f959a，规则v37。完整职责与限制见[接入说明](../../quality/issue135_trigger_strength.md)。

| 运行 | 实际结果 |
| --- | --- |
| RED | 首批10测试中7项失败，14/30断言通过，0.088秒；red-output.log |
| 首次GREEN | 10/10测试、30断言，0.26秒；first-green-output.log |
| 定向 | 3脚本25/25测试、129断言，0.114秒；target-output.log |
| v37独立回放 | 415条记录通过，error为空，退出0；replay-output.log |
| v36边界 | record_version_mismatch、checked_records=0，退出1；old-replay-output.log |
| 完整回归 | 82脚本、599/599测试、22519断言，436.792秒、退出0；无脚本解析错误，full-output.log/full-engine.log/script-results.json |
| 机器人 | seed133000、greedy、65上限，44行动、714分、3次选卡、满盘结束；新记录落盘读回OK、退出0 |

新记录bot-record.jsonl来自本片v37实现；日志保留系统根证书与资源提示，不以测试成功声称引擎输出零错误。manifest.json保存机器文件字节数与SHA256；README、.gitattributes、manifest自身除外。line-counts.json覆盖本片代码，全部≤500行。

复现（实际游戏仓库PowerShell，Godot4.7.2）：

```powershell
$env:APPDATA = Join-Path (Get-Location) '.godot/issue135-strength/reproduce-sandbox'
$env:LOCALAPPDATA = $env:APPDATA
& 'D:/GameMaker/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --fixed-fps 60 -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
& 'D:/GameMaker/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe' --headless --text-driver Dummy --path . -s tools/bot_testing/batch_cli.gd -- replay res://docs/evidence/issue135-strength/bot-record.jsonl
```

定向替换目录参数为`-gtest=res://tests/rules/test_trigger_strength.gd,res://tests/rules/test_composite_boundaries.gd,res://tests/rules/test_ability_composite_effects.gd`。原始自定义S夹具是规则层验证，正式Catalog跨层命令与回放沿全量回归；不冒充自定义卡已走磁盘恢复或新正式技能。
