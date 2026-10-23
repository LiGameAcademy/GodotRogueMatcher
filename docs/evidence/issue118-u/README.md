# U模板与黑盒试玩验收证据

2026-10-23。基线为#176提交6daf664620af3817372d1dd42af10e1956701d59；受测代码84af6173355ddd5ee06c2dbf9df881ce0ce68de5。

Godot4.7.2 / Compatibility，GUT9.6.0。无界面回归固定60FPS，进程级APPDATA/LOCALAPPDATA隔离于.godot/issue118-u/。

- full-output.log：111脚本、810/810、24569断言、220.811秒，退出0；无新增脚本解析错误或Resource/ObjectDB泄漏。
- target.log：U专项29/29、281断言；import.log：编辑器导入检查。
- script-results.json为完整回归逐脚本统计；line-counts.json核对357个自有GDScript，最大474行。
- 新记录u-unlock-record.jsonl（13条）、order-l-u.jsonl/order-u-l.jsonl（各17条）、rotated-playground.jsonl（11条）、move-playground.jsonl（14条）。后两份来自真实试玩场景、选卡弹窗和棋盘输入入口。
- 十九份记录分别以独立进程回放成功：新五份，既有T/＋/×各三份、Z/S五份。summary.json列出来源、SHA256、成功结果与退出码；不代表v42兼容。
- human-output.log/human-error.log为实际桌面启动日志快照，确认READY/OpenGL设备且错误为空。human-window.png是引擎稳定绘制后的真实窗口截帧，已人工查看；截图、启动和按钮操作记录不代表真人体验验收结论。
- manifest.json保存原始证据字节数与SHA256（README自身不纳入）；文本证据禁用换行转换，保证跨平台复核。

完整回归命令：

```powershell
& $engine --headless --verbose --path . --fixed-fps 60 -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
```

专项另加-gselect=u_（本轮实际匹配四个U测试脚本）。回放逐记录使用独立进程及数据目录：

```powershell
& $engine --headless --text-driver Dummy --path . -s tools/bot_testing/batch_cli.gd -- replay <记录路径>
```

试玩入口：tools/u_template_playground/u_template_playground.tscn。Godot打开该场景按F6；本轮已实际启动，工具内四题和原生重开均使用独立fixture记录。完整步骤见../../quality/issue118_u_template.md。

只读复审APPROVE，无阻断项；核对七格、四方向、中心/外围并集、计分、L/U材料消耗、重开隔离、旧profile与类型/行数。其后主agent完成完整回归和十九次独立回放。旧生产池不变；正式配方、后批环/方块和真人体验仍待完成，不关闭#118。
