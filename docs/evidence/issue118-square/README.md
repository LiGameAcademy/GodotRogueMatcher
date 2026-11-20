# 九格实心方块验收证据

2026-10-24。前置#181，基础提交57829d3435eec3629bf3e92d6405b310e29c3c09；受测代码676cb9666b61ff303bae084228bf8c0c79b6f74f。Godot4.7.2 / Compatibility，GUT9.6.0，固定60FPS，进程级用户目录隔离于.godot/issue118-square/。

- full-output.log：完整119脚本、870/870、25137断言、213.86秒，退出0；无新增解析错误或Resource/ObjectDB泄漏。summary.json为实测汇总，script-results.json为逐脚本统计。
- import.log导入检查。target.log保留新测试的未标类型数组失败，target2.log最终31/31、294断言；没有为测试改生产规则。
- line-counts.json为自有GDScript物理行数，全部不超过500。
- 新记录square-unlock-record.jsonl（19）、order-ring-square.jsonl/order-square-ring.jsonl（各23）、center-playground.jsonl（11）、move-playground.jsonl（20）。保留真实126分或104分触发的经典额外奖励；中心异色0分不消除。
- replay-*.log为29个独立进程的精确回放：新5＋既有24。summary保存记录路径、SHA256、实测输出和退出码。仅v43，不代表v42兼容。
- human-output.log/human-error.log为可见游戏启动快照，human-window.png为已查看的稳定引擎截帧；不代替真人体验验收。
- manifest.json包含原始字节数与SHA256，README不纳入；文本证据禁用换行转换。

完整回归：

```powershell
& $engine --headless --verbose --path . --fixed-fps 60 -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
```

专项另加-gselect=square_。逐记录新进程回放：

```powershell
& $engine --headless --text-driver Dummy --path . -s tools/bot_testing/batch_cli.gd -- replay <记录路径>
```

试玩入口tools/square_template_playground/square_template_playground.tscn，F6运行。步骤与范围见[质量结论](../../quality/issue118_square_template.md)。只读复审APPROVE，无阻断项。PR保留作者review，不自动合并；O4冻结。
