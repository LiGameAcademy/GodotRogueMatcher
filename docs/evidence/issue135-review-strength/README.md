# #168同步#167 review修复 · 2026-10-20

父片fc16bc7，同步实现f522fe8，规则run-commands-v39-target-strength。初版v37强度证据保持原字节；当前运行需同时验证正式目标生命周期与强度快照。

首次切回#168时本地Godot全局类缓存缺少RemovalStrength注册，初次完整/机器人运行出现解析连锁错误，已停止。invalid-cache-output.log与invalid-cache-bot-output.log保留，不计为有效回归；重新执行--headless --editor --path . --quit导入，再运行最终回归。

实际范围见[强度说明](../../quality/issue135_trigger_strength.md)与[正式目标说明](../../quality/issue135_composite_boundaries.md)。#135未整体完成；异形、空盘恢复、全部B/S/T与存档恢复未标通过。

复现使用Godot4.7.2、独立APPDATA/LOCALAPPDATA；新checkout或切换含新全局类的分支先导入：

```powershell
$env:APPDATA = Join-Path (Get-Location) '.godot/issue135-review-strength/reproduce-sandbox'
$env:LOCALAPPDATA = $env:APPDATA
& 'D:/GameMaker/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe' --headless --editor --path . --quit
& 'D:/GameMaker/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe' --headless --verbose --path . --fixed-fps 60 -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
& 'D:/GameMaker/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe' --headless --text-driver Dummy --path . -s tools/bot_testing/batch_cli.gd -- replay res://docs/evidence/issue135-review-strength/bot-record.jsonl
```

manifest保存机器文件字节与SHA256（README/.gitattributes/自身除外）；line-counts覆盖两片当前修改代码并检查≤500行。原始日志不移除引擎提示，不以用例通过称输出零错误。

同步实现最终完整回归：83脚本、605/605测试、22616断言，188.59秒、退出0，无SCRIPT ERROR或Parse Error，83个脚本均参与。v39新局seed133000/greedy，44行动714分3次选卡；落盘读回与415条独立回放成功。v38明确拒绝，检查0条。此次完整详细运行未报告ObjectDB/Resource泄漏；保留全部verbose退出诊断，不将#167那次退出提示抹掉。
