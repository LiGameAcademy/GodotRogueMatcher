# #167 review修复证据 · 2026-10-20

实现8c7d5e3，规则run-commands-v38-target-lifecycle；基于初版PR head1749dfb。旧v36证据保持原字节，不能作为本次正式生命周期通过的依据。

- first-rules-output.log：初次迁移有11失败，旧单卡固定预览被默认动态破坏；正式资源补显式FIXED后保留原约定。
- target2-output.log：6脚本38项中37通过，旧手工指定行夹具未声明FIXED。
- target3-output.log：39项中36通过，预检新增只读观察影响检查点计数，动态空染色缺少明确声明；已分别修正夹具。
- target4-output.log：7脚本43/43测试、671断言，0.498秒，退出0；随后增加预算不可被跳过策略抹除的检查，一并纳入最终完整回归。
- bot-output.log：seed133000/greedy/65上限，44行动714分3次选卡，满盘结束；落盘读回OK，退出0。
- replay-output.log：v38独立回放415条成功；old-replay-output.log：v36返回record_version_mismatch、0条，符合版本边界。

原始日志保留引擎提示，不以测试通过称“零错误输出”。自定义新组合的正式候选/规则应用与实际Catalog命令入口分别记录覆盖，不声称自定义卡已实现存档恢复。职责、作者五项review及未交付验收见[质量说明](../../quality/issue135_composite_boundaries.md)。

复现：在游戏仓库设置独立APPDATA/LOCALAPPDATA，使用Godot4.7.2。

```powershell
$env:APPDATA = Join-Path (Get-Location) '.godot/issue135-review/reproduce-sandbox'
$env:LOCALAPPDATA = $env:APPDATA
& 'D:/GameMaker/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --fixed-fps 60 -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
& 'D:/GameMaker/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe' --headless --text-driver Dummy --path . -s tools/bot_testing/batch_cli.gd -- replay res://docs/evidence/issue135-review/bot-record.jsonl
```

定向使用-gtest=res://tests/rules/test_composite_offer_lifecycle.gd及相关组合脚本。manifest.json记录机器文件字节与SHA256（排除README/.gitattributes/自身）；line-counts.json覆盖本次修改代码，均≤500行。

最终完整回归：82脚本、593/593测试、22574断言，211.194秒、退出0；无SCRIPT ERROR或Parse Error，82个脚本均参与。退出保留2个ObjectDB/1个Resource提示，不称引擎零错误。
