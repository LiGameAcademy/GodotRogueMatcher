# Z/S家族与黑盒试玩验收证据

2026-10-23。基线为 PR #175 代码/文档提交05f89a5a054d998367447038db45fbc88f30cc87；受测代码41ef81422fade875b33391a7b0352904d288d97c。

Godot4.7.2 / Compatibility，GUT9.6.0，无界面回归固定60FPS，使用.godot/issue118-zs/下进程级APPDATA/LOCALAPPDATA隔离目录。

- full-output.log：107脚本，781/781，24288断言，257.998秒，退出0；没有新增脚本解析错误或Resource/ObjectDB泄漏。
- target.log：首轮25/26，三个Z摆放实际构成五个合法互异命中，原夹具误期望3个；不视为规则错误RED。
- target2.log：修正预期并补重复家族合法池检查后26/26。target3.log：补真实重开隔离后28/28、260断言；最终再补五个origin和实体集合互异共10断言，完整回归确认本片270断言。
- import.log：编辑器资源导入检查。script-results.json：完整逐脚本统计；line-counts.json：350个自有GDScript，最大474行。
- 新记录：zs-unlock-record.jsonl（13）、order-l-zs.jsonl（17）、order-zs-l.jsonl（17）、mirror-playground.jsonl（11）、move-playground.jsonl（14）；后两份由真实试玩场景测试产生，不是绕过棋盘的规则命令代替。
- replay-*.log：十四次独立进程精确回放，新五份加../issue118-t/、../issue118-plus/、../issue118-x/各三份旧v43记录。summary.json列出每份来源、记录SHA256及成功结果。
- human-output.log/human-error.log：实际可见桌面窗口启动时快照，READY与OpenGL设备已确认，错误日志为空；窗口保留供作者操作。不是完整真人试玩结论或退出资源诊断，日志在快照后可能继续增长。
- manifest.json：证据原始字节数及SHA256，README不纳入；log/JSON/JSONL禁止换行转换。

完整回归命令：

```powershell
& $engine --headless --verbose --path . --fixed-fps 60 -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
```

专项另加-gselect=zs_。每次CLI回放使用新进程、隔离目录：

```powershell
& $engine --headless --text-driver Dummy --path . -s tools/bot_testing/batch_cli.gd -- replay <记录路径>
```

桌面试玩入口：tools/zs_template_playground/zs_template_playground.tscn，编辑器打开该场景按F6，或引擎以该场景路径启动。本轮已实际启动；步骤详见../../quality/issue118_zs_template.md。

只读复审发现原生重开及旧快捷键隔离缺口，已修复并补真实菜单/结算重试回归；最终APPROVE，无阻断项。规则仍v43，不恢复v42精确重算兼容。单家族身份与自动回归不替代真人理解/布局/选择意愿验收。PR依赖待审查#175，不自动合并。
